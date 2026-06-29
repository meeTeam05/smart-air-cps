/**
 * @file mqtt.c
 *
 * @brief MQTT client — MQTT over TLS/WSS to EMQX, LWT, pub/sub.
 *
 * Architecture:
 *   - mqtt_start() creates mqtt_task (Core 1, Priority 6, 6144 B).
 *   - mqtt_task initialises esp_mqtt_client, registers events, calls start,
 *     reports that setup result back to mqtt_start(), then deletes itself.
 *   - after setup succeeds, the library manages the connection lifecycle internally.
 *   - All subscriptions are (re)registered in MQTT_EVENT_CONNECTED per FW-05.
 *   - MQTT_EVENT_DATA payload is copied before the handler returns per FW-04.
 *
 * Copyright (C) 2026 MinhNhat & BaoViet
 */

#include "mqtt.h"

#include "config.h"
#include "device_mode.h"
#include "esp_crt_bundle.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "led.h"
#include "mqtt_client.h"
#include "ota.h"
#include "cJSON.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *TAG = "mqtt";

static const char *mqtt_error_type_name(esp_mqtt_error_type_t error_type)
{
    switch (error_type) {
    case MQTT_ERROR_TYPE_NONE:
        return "none";
    case MQTT_ERROR_TYPE_TCP_TRANSPORT:
        return "tcp_transport";
    case MQTT_ERROR_TYPE_CONNECTION_REFUSED:
        return "connection_refused";
    case MQTT_ERROR_TYPE_SUBSCRIBE_FAILED:
        return "subscribe_failed";
    default:
        return "unknown";
    }
}

static const char *mqtt_connect_return_code_name(esp_mqtt_connect_return_code_t code)
{
    switch (code) {
    case MQTT_CONNECTION_ACCEPTED:
        return "accepted";
    case MQTT_CONNECTION_REFUSE_PROTOCOL:
        return "refuse_protocol";
    case MQTT_CONNECTION_REFUSE_ID_REJECTED:
        return "refuse_id_rejected";
    case MQTT_CONNECTION_REFUSE_SERVER_UNAVAILABLE:
        return "refuse_server_unavailable";
    case MQTT_CONNECTION_REFUSE_BAD_USERNAME:
        return "refuse_bad_username";
    case MQTT_CONNECTION_REFUSE_NOT_AUTHORIZED:
        return "refuse_not_authorized";
    default:
        return "unknown";
    }
}

/* ── Driver state ────────────────────────────────────────────────────────── */

static esp_mqtt_client_handle_t s_client = NULL;
static mqtt_time_sync_cb_t s_time_sync_cb = NULL;
static mqtt_shadow_sync_cb_t s_shadow_sync_cb = NULL;
static portMUX_TYPE s_client_lock = portMUX_INITIALIZER_UNLOCKED;
static uint32_t s_client_users;

#define MAX_CMD_HANDLERS 8
#define MQTT_COMMAND_ID_LEN 40
#define MQTT_TRACKED_COMMANDS_MAX 20
#define MQTT_MAX_INBOUND_PAYLOAD_LEN 512
typedef struct {
    char type[MQTT_MAX_COMMAND_TYPE_LEN + 1];
    mqtt_command_cb_t cb;
} cmd_handler_entry_t;
static cmd_handler_entry_t s_cmd_handlers[MAX_CMD_HANDLERS];
static int s_cmd_handler_count = 0;

typedef enum {
    MQTT_COMMAND_STATE_EMPTY = 0,
    MQTT_COMMAND_STATE_PENDING,
    MQTT_COMMAND_STATE_DONE,
    MQTT_COMMAND_STATE_ERROR,
} mqtt_command_state_t;

typedef struct {
    char command_id[MQTT_COMMAND_ID_LEN];
    mqtt_command_state_t state;
    uint32_t generation;
} tracked_command_entry_t;

static tracked_command_entry_t s_tracked_commands[MQTT_TRACKED_COMMANDS_MAX];
static portMUX_TYPE s_tracked_commands_lock = portMUX_INITIALIZER_UNLOCKED;
static uint32_t s_tracked_command_generation;

typedef struct {
    TaskHandle_t waiter;
    esp_err_t result;
} mqtt_start_ctx_t;

/* Buffers filled once in mqtt_start() and kept alive for the MQTT client/task */
static char s_broker_uri[128];
static char s_device_id[64];
static char s_secret_key[64];
static char s_status_topic[96];   /* device/{id}/status */
static char s_cmd_topic[96];      /* device/{id}/command */
static char s_response_topic[96]; /* device/{id}/response */
static char s_shadow_get_topic[96];           /* device/{id}/shadow/get */
static char s_shadow_get_response_topic[128]; /* device/{id}/shadow/get_response */
static char s_ota_topic[96];      /* device/{id}/ota/update */
static char *s_rx_topic = NULL;
static char *s_rx_payload = NULL;
static int s_rx_total_len;

static bool mqtt_event_topic_equals(const char *topic, int topic_len, const char *expected)
{
    size_t expected_len = strlen(expected);
    return topic != NULL && topic_len >= 0 && (size_t)topic_len == expected_len &&
           memcmp(topic, expected, expected_len) == 0;
}

static int mqtt_inbound_payload_limit(const char *topic, int topic_len)
{
    if (mqtt_event_topic_equals(topic, topic_len, s_cmd_topic) ||
        mqtt_event_topic_equals(topic, topic_len, s_shadow_get_response_topic) ||
        mqtt_event_topic_equals(topic, topic_len, s_ota_topic)) {
        return MQTT_MAX_INBOUND_PAYLOAD_LEN;
    }

    return 0;
}

static void mqtt_pending_rx_reset(void)
{
    free(s_rx_topic);
    free(s_rx_payload);
    s_rx_topic = NULL;
    s_rx_payload = NULL;
    s_rx_total_len = 0;
}

static esp_err_t mqtt_pending_rx_append(const esp_mqtt_event_handle_t ev, char **topic_out, char **payload_out)
{
    if (ev == NULL || topic_out == NULL || payload_out == NULL || ev->topic == NULL || ev->topic_len < 0 ||
        ev->data == NULL || ev->data_len < 0 || ev->current_data_offset < 0 || ev->total_data_len < 0 ||
        ev->total_data_len < ev->data_len) {
        mqtt_pending_rx_reset();
        return ESP_ERR_INVALID_ARG;
    }

    if (ev->current_data_offset == 0) {
        int payload_limit = mqtt_inbound_payload_limit(ev->topic, ev->topic_len);

        mqtt_pending_rx_reset();
        if (payload_limit <= 0 || ev->total_data_len > payload_limit) {
            return ESP_ERR_INVALID_SIZE;
        }

        s_rx_topic = strndup(ev->topic, (size_t)ev->topic_len);
        s_rx_payload = malloc((size_t)ev->total_data_len + 1U);
        if (s_rx_topic == NULL || s_rx_payload == NULL) {
            mqtt_pending_rx_reset();
            return ESP_ERR_NO_MEM;
        }

        s_rx_total_len = ev->total_data_len;
        s_rx_payload[s_rx_total_len] = '\0';
    } else if (s_rx_topic == NULL || s_rx_payload == NULL || ev->total_data_len != s_rx_total_len) {
        mqtt_pending_rx_reset();
        return ESP_ERR_INVALID_STATE;
    }

    if (ev->current_data_offset + ev->data_len > s_rx_total_len) {
        mqtt_pending_rx_reset();
        return ESP_ERR_INVALID_SIZE;
    }

    memcpy(s_rx_payload + ev->current_data_offset, ev->data, (size_t)ev->data_len);
    if (ev->current_data_offset + ev->data_len < s_rx_total_len) {
        return ESP_ERR_NOT_FINISHED;
    }

    *topic_out = s_rx_topic;
    *payload_out = s_rx_payload;
    return ESP_OK;
}

static const char *mqtt_command_state_name(mqtt_command_state_t state)
{
    switch (state) {
    case MQTT_COMMAND_STATE_PENDING:
        return "pending";
    case MQTT_COMMAND_STATE_DONE:
        return "done";
    case MQTT_COMMAND_STATE_ERROR:
        return "error";
    default:
        return "empty";
    }
}

static void mqtt_command_cache_reset(void)
{
    portENTER_CRITICAL(&s_tracked_commands_lock);
    memset(s_tracked_commands, 0, sizeof(s_tracked_commands));
    s_tracked_command_generation = 0;
    portEXIT_CRITICAL(&s_tracked_commands_lock);
}

static int mqtt_command_cache_find_locked(const char *command_id)
{
    for (size_t i = 0; i < MQTT_TRACKED_COMMANDS_MAX; i++) {
        if (s_tracked_commands[i].state != MQTT_COMMAND_STATE_EMPTY &&
            strcmp(s_tracked_commands[i].command_id, command_id) == 0) {
            return (int)i;
        }
    }

    return -1;
}

static int mqtt_command_cache_select_slot_locked(void)
{
    int oldest_terminal = -1;
    uint32_t oldest_terminal_generation = UINT32_MAX;
    int oldest_any = -1;
    uint32_t oldest_any_generation = UINT32_MAX;

    for (size_t i = 0; i < MQTT_TRACKED_COMMANDS_MAX; i++) {
        if (s_tracked_commands[i].state == MQTT_COMMAND_STATE_EMPTY) {
            return (int)i;
        }

        if (s_tracked_commands[i].generation < oldest_any_generation) {
            oldest_any_generation = s_tracked_commands[i].generation;
            oldest_any = (int)i;
        }

        if (s_tracked_commands[i].state != MQTT_COMMAND_STATE_PENDING &&
            s_tracked_commands[i].generation < oldest_terminal_generation) {
            oldest_terminal_generation = s_tracked_commands[i].generation;
            oldest_terminal = (int)i;
        }
    }

    return oldest_terminal >= 0 ? oldest_terminal : oldest_any;
}

static bool mqtt_command_cache_lookup(const char *command_id, mqtt_command_state_t *state_out)
{
    bool found = false;

    if (command_id == NULL || command_id[0] == '\0') {
        return false;
    }

    portENTER_CRITICAL(&s_tracked_commands_lock);
    int index = mqtt_command_cache_find_locked(command_id);
    if (index >= 0) {
        found = true;
        if (state_out != NULL) {
            *state_out = s_tracked_commands[index].state;
        }
    }
    portEXIT_CRITICAL(&s_tracked_commands_lock);

    return found;
}

static void mqtt_command_cache_set(const char *command_id, mqtt_command_state_t state)
{
    if (command_id == NULL || command_id[0] == '\0') {
        return;
    }

    portENTER_CRITICAL(&s_tracked_commands_lock);
    int index = mqtt_command_cache_find_locked(command_id);
    if (index < 0) {
        index = mqtt_command_cache_select_slot_locked();
    }
    if (index >= 0) {
        strlcpy(s_tracked_commands[index].command_id, command_id, sizeof(s_tracked_commands[index].command_id));
        s_tracked_commands[index].state = state;
        s_tracked_commands[index].generation = ++s_tracked_command_generation;
    }
    portEXIT_CRITICAL(&s_tracked_commands_lock);
}

static esp_mqtt_client_handle_t mqtt_client_acquire(void)
{
    esp_mqtt_client_handle_t client = NULL;

    portENTER_CRITICAL(&s_client_lock);
    if (s_client != NULL) {
        s_client_users++;
        client = s_client;
    }
    portEXIT_CRITICAL(&s_client_lock);

    return client;
}

static void mqtt_client_release(void)
{
    portENTER_CRITICAL(&s_client_lock);
    if (s_client_users > 0) {
        s_client_users--;
    }
    portEXIT_CRITICAL(&s_client_lock);
}

static void mqtt_client_wait_for_users(void)
{
    while (1) {
        uint32_t active_users = 0;

        portENTER_CRITICAL(&s_client_lock);
        active_users = s_client_users;
        portEXIT_CRITICAL(&s_client_lock);

        if (active_users == 0) {
            return;
        }

        vTaskDelay(pdMS_TO_TICKS(1));
    }
}

static esp_err_t mqtt_publish_command_ack_internal(const char *command_id, bool success)
{
    if (command_id == NULL || command_id[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    mqtt_command_cache_set(command_id, success ? MQTT_COMMAND_STATE_DONE : MQTT_COMMAND_STATE_ERROR);

    esp_mqtt_client_handle_t client = mqtt_client_acquire();
    if (client == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    char response[128];
    int written = snprintf(response,
                           sizeof(response),
                           "{\"command_id\":\"%s\",\"status\":\"%s\"}",
                           command_id,
                           success ? "done" : "error");
    if (written < 0 || written >= (int)sizeof(response)) {
        mqtt_client_release();
        return ESP_ERR_INVALID_SIZE;
    }

    if (esp_mqtt_client_publish(client, s_response_topic, response, 0, 1, 0) < 0) {
        mqtt_client_release();
        return ESP_FAIL;
    }

    mqtt_client_release();
    ESP_LOGI(TAG, "Command ack → %s", s_response_topic);
    return ESP_OK;
}

static esp_err_t mqtt_publish_shadow_get_request(esp_mqtt_client_handle_t client)
{
    if (client == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    char payload[48];
    time_t now = time(NULL);
    unsigned long ts = now > 0 ? (unsigned long)now : 0UL;
    int written = snprintf(payload, sizeof(payload), "{\"ts\":%lu}", ts);
    if (written < 0 || written >= (int)sizeof(payload)) {
        return ESP_ERR_INVALID_SIZE;
    }

    int msg_id = esp_mqtt_client_publish(client, s_shadow_get_topic, payload, 0, 1, 0);
    if (msg_id < 0) {
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Published shadow/get → %s (msg_id=%d)", s_shadow_get_topic, msg_id);
    return ESP_OK;
}

static esp_err_t mqtt_subscribe_required_topics(esp_mqtt_client_handle_t client)
{
    const struct {
        const char *topic;
        const char *label;
    } subscriptions[] = {
        {s_cmd_topic, "command"},
        {s_shadow_get_response_topic, "shadow/get_response"},
        {s_ota_topic, "ota"},
    };

    for (size_t i = 0; i < sizeof(subscriptions) / sizeof(subscriptions[0]); i++) {
        int msg_id = esp_mqtt_client_subscribe(client, subscriptions[i].topic, 1);
        if (msg_id < 0) {
            ESP_LOGE(TAG,
                     "Subscribe enqueue failed for %s topic %s (msg_id=%d)",
                     subscriptions[i].label,
                     subscriptions[i].topic,
                     msg_id);
            return msg_id == -2 ? ESP_ERR_NO_MEM : ESP_FAIL;
        }

        ESP_LOGI(TAG,
                 "Subscribe queued for %s topic %s (msg_id=%d)",
                 subscriptions[i].label,
                 subscriptions[i].topic,
                 msg_id);
    }

    return ESP_OK;
}

/* ── MQTT event handler ──────────────────────────────────────────────────── */

static void mqtt_event_handler(void *arg, esp_event_base_t base, int32_t event_id, void *event_data)
{
    esp_mqtt_event_handle_t ev = (esp_mqtt_event_handle_t)event_data;

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED: {
        ESP_LOGI(TAG, "Connected to broker");
        led_set_state(LED_STATE_ONLINE);

        esp_mqtt_client_handle_t client = mqtt_client_acquire();
        if (client == NULL) {
            ESP_LOGW(TAG, "Connected event ignored because MQTT client is stopping");
            break;
        }

        /* FW-05: subscribe inside CONNECTED so re-connects re-subscribe */
        esp_err_t subscribe_err = mqtt_subscribe_required_topics(client);
        if (subscribe_err != ESP_OK) {
            ESP_LOGE(TAG, "Required topic subscription setup failed (%s) — forcing reconnect", esp_err_to_name(subscribe_err));
            esp_mqtt_client_disconnect(client);
            mqtt_client_release();
            break;
        }

        /* Publish retained online status after subscriptions are ready so
         * shadow/get_response can be received immediately. */
        char msg[80];
        snprintf(msg, sizeof(msg), "{\"online\":true,\"firmware\":\"%s\"}", CONFIG_FIRMWARE_VERSION);
        esp_mqtt_client_publish(client, s_status_topic, msg, 0, 1, 1);
        ESP_LOGI(TAG, "Published online status → %s", s_status_topic);

        esp_err_t shadow_report_err = device_mode_publish_current_shadow();
        if (shadow_report_err != ESP_OK) {
            ESP_LOGW(TAG, "current shadow publish failed after connect: %s", esp_err_to_name(shadow_report_err));
        }

        esp_err_t shadow_get_err = mqtt_publish_shadow_get_request(client);
        if (shadow_get_err != ESP_OK) {
            ESP_LOGW(TAG, "shadow/get publish failed after connect: %s", esp_err_to_name(shadow_get_err));
        }

        mqtt_client_release();
        break;
    }

    case MQTT_EVENT_DISCONNECTED:
        mqtt_pending_rx_reset();
        led_set_state(LED_STATE_WIFI);
        ESP_LOGW(TAG, "Disconnected — reconnecting automatically");
        break;

    case MQTT_EVENT_DATA: {
        /* FW-04: copy topic + payload before returning from handler */
        char *topic = NULL;
        char *payload = NULL;
        esp_err_t copy_err = mqtt_pending_rx_append(ev, &topic, &payload);
        if (copy_err == ESP_ERR_NOT_FINISHED) {
            break;
        }
        if (copy_err != ESP_OK) {
            ESP_LOGE(TAG,
                     "dropping MQTT message fragment: err=%s topic_len=%d data_len=%d total_len=%d offset=%d",
                     esp_err_to_name(copy_err),
                     ev->topic_len,
                     ev->data_len,
                     ev->total_data_len,
                     ev->current_data_offset);
            break;
        }

        ESP_LOGI(TAG, "RX [%s]: %s", topic, payload);

        /* Route: command → dispatch handler → ack with actual result */
        if (strstr(topic, "/command") != NULL) {
            cJSON *root = cJSON_ParseWithLength(payload, strlen(payload));
            if (root != NULL) {
                bool cmd_ok = true;
                bool ack_deferred = false;
                bool command_handled = false;
                bool duplicate_command = false;
                const char *command_id = NULL;

                /* Dispatch command handlers */
                cJSON *j_cmd_id = cJSON_GetObjectItemCaseSensitive(root, "command_id");
                cJSON *j_type = cJSON_GetObjectItemCaseSensitive(root, "type");
                cJSON *j_ts = cJSON_GetObjectItemCaseSensitive(root, "ts");
                if (cJSON_IsString(j_cmd_id) && j_cmd_id->valuestring[0] != '\0') {
                    command_id = j_cmd_id->valuestring;
                }

                if (command_id != NULL) {
                    mqtt_command_state_t cached_state = MQTT_COMMAND_STATE_EMPTY;
                    if (mqtt_command_cache_lookup(command_id, &cached_state)) {
                        duplicate_command = true;
                        command_handled = true;
                        if (cached_state == MQTT_COMMAND_STATE_PENDING) {
                            ack_deferred = true;
                            ESP_LOGI(TAG,
                                     "Duplicate command '%s' ignored while previous execution still pending",
                                     command_id);
                        } else {
                            esp_err_t ack_err =
                                mqtt_publish_command_ack_internal(command_id, cached_state == MQTT_COMMAND_STATE_DONE);
                            if (ack_err != ESP_OK) {
                                ESP_LOGW(TAG,
                                         "Duplicate command ack publish failed for '%s': %s",
                                         command_id,
                                         esp_err_to_name(ack_err));
                            } else {
                                ESP_LOGI(TAG,
                                         "Duplicate command '%s' reused cached status %s",
                                         command_id,
                                         mqtt_command_state_name(cached_state));
                            }
                        }
                    } else {
                        mqtt_command_cache_set(command_id, MQTT_COMMAND_STATE_PENDING);
                    }
                }

                if (!duplicate_command && !cJSON_IsString(j_type)) {
                    cmd_ok = false;
                    ESP_LOGW(TAG, "command message missing string type");
                } else if (!duplicate_command && strcmp(j_type->valuestring, "set_time") == 0) {
                    command_handled = true;
                    if (cJSON_IsNumber(j_ts) && s_time_sync_cb != NULL) {
                        s_time_sync_cb((uint32_t)j_ts->valuedouble);
                        ESP_LOGI(TAG, "set_time dispatched: ts=%lu", (unsigned long)(uint32_t)j_ts->valuedouble);
                    } else {
                        cmd_ok = false;
                        ESP_LOGW(TAG, "set_time command missing ts or callback");
                    }
                } else if (!duplicate_command && strcmp(j_type->valuestring, "set_config") == 0) {
                    command_handled = true;
                    cmd_ok = false;
                    ESP_LOGW(TAG,
                             "set_config is not accepted over MQTT; use local POST /api/config before first login");
                } else if (!duplicate_command) {
                    for (int i = 0; i < s_cmd_handler_count; i++) {
                        if (strcmp(j_type->valuestring, s_cmd_handlers[i].type) == 0) {
                            command_handled = true;
                            esp_err_t hr = s_cmd_handlers[i].cb(j_type->valuestring, payload);
                            if (hr == ESP_ERR_NOT_FINISHED) {
                                ack_deferred = true;
                            } else if (hr != ESP_OK) {
                                cmd_ok = false;
                                ESP_LOGW(TAG,
                                         "Command '%s' handler returned %s",
                                         j_type->valuestring,
                                         esp_err_to_name(hr));
                            }
                            break;
                        }
                    }
                    if (!command_handled) {
                        cmd_ok = false;
                        ESP_LOGW(TAG, "unsupported command type: %s", j_type->valuestring);
                    }
                }

                if (!ack_deferred && !duplicate_command) {
                    /* Send ack AFTER execution with actual status */
                    if (command_id != NULL) {
                        esp_err_t ack_err = mqtt_publish_command_ack_internal(command_id, cmd_ok);
                        if (ack_err != ESP_OK) {
                            ESP_LOGW(TAG,
                                     "Command ack publish failed for '%s': %s",
                                     command_id,
                                     esp_err_to_name(ack_err));
                        }
                    } else {
                        ESP_LOGW(TAG, "command message missing command_id");
                    }
                }

                cJSON_Delete(root);
            } else {
                ESP_LOGW(TAG, "command message is not valid JSON");
            }
        }

        if (strcmp(topic, s_shadow_get_response_topic) == 0) {
            if (s_shadow_sync_cb == NULL) {
                ESP_LOGW(TAG, "shadow/get_response received without registered callback");
            } else {
                esp_err_t sync_err = s_shadow_sync_cb(payload);
                if (sync_err != ESP_OK) {
                    ESP_LOGW(TAG, "shadow/get_response apply failed: %s", esp_err_to_name(sync_err));
                }
            }
        }

        /* Route: OTA update trigger */
        if (strstr(topic, "/ota/update") != NULL) {
            cJSON *root = cJSON_ParseWithLength(payload, strlen(payload));
            if (root != NULL) {
                cJSON *j_url = cJSON_GetObjectItemCaseSensitive(root, "url");
                cJSON *j_sha = cJSON_GetObjectItemCaseSensitive(root, "sha256");
                if (cJSON_IsString(j_url) && cJSON_IsString(j_sha)) {
                    ota_trigger(j_url->valuestring, j_sha->valuestring);
                } else {
                    ESP_LOGW(TAG, "OTA update message missing url or sha256");
                }
                cJSON_Delete(root);
            } else {
                ESP_LOGW(TAG, "OTA update message is not valid JSON");
            }
        }
        mqtt_pending_rx_reset();
        break;
    }

    case MQTT_EVENT_ERROR:
        if (ev->error_handle == NULL) {
            ESP_LOGE(TAG, "MQTT error event missing error_handle (broker=%s)", s_broker_uri);
            break;
        }

        ESP_LOGE(TAG,
                 "MQTT error: type=%s (%d), broker=%s",
                 mqtt_error_type_name(ev->error_handle->error_type),
                 ev->error_handle->error_type,
                 s_broker_uri);

        if (ev->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT) {
            ESP_LOGE(TAG,
                     "Transport details: esp_err=%s (0x%x) tls_stack_err=0x%x cert_flags=0x%x sock_errno=%d (%s)",
                     esp_err_to_name(ev->error_handle->esp_tls_last_esp_err),
                     ev->error_handle->esp_tls_last_esp_err,
                     ev->error_handle->esp_tls_stack_err,
                     ev->error_handle->esp_tls_cert_verify_flags,
                     ev->error_handle->esp_transport_sock_errno,
                     strerror(ev->error_handle->esp_transport_sock_errno));
        } else if (ev->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED) {
            ESP_LOGE(TAG,
                     "Broker refused connection: code=%s (%d)",
                     mqtt_connect_return_code_name(ev->error_handle->connect_return_code),
                     ev->error_handle->connect_return_code);
        } else if (ev->error_handle->error_type == MQTT_ERROR_TYPE_SUBSCRIBE_FAILED) {
            ESP_LOGE(TAG, "Broker reported subscribe failure — forcing reconnect");

            esp_mqtt_client_handle_t client = mqtt_client_acquire();
            if (client != NULL) {
                esp_err_t disconnect_err = esp_mqtt_client_disconnect(client);
                if (disconnect_err != ESP_OK) {
                    ESP_LOGW(TAG, "Disconnect after subscribe failure failed (%s)", esp_err_to_name(disconnect_err));
                }
                mqtt_client_release();
            }
        }
        break;

    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGI(TAG, "Subscribed (msg_id=%d)", ev->msg_id);
        break;

    default:
        break;
    }
}

/* ── FreeRTOS tasks ──────────────────────────────────────────────────────── */

static void mqtt_task(void *arg)
{
    mqtt_start_ctx_t *start_ctx = (mqtt_start_ctx_t *)arg;
    esp_mqtt_client_config_t cfg = {
        .broker =
            {
                .address.uri = s_broker_uri,
                .verification.crt_bundle_attach = esp_crt_bundle_attach,
            },
        .credentials =
            {
                .username = s_device_id,
                .authentication.password = s_secret_key,
                .client_id = s_device_id,
            },
        .session =
            {
                .last_will =
                    {
                        .topic = s_status_topic,
                        .msg = "{\"online\":false}",
                        .qos = 1,
                        .retain = 1,
                    },
                .keepalive = 15,
            },
        .network =
            {
                .reconnect_timeout_ms = 5000,
            },
    };
    esp_err_t err = ESP_OK;

    esp_mqtt_client_handle_t client = esp_mqtt_client_init(&cfg);
    if (client == NULL) {
        ESP_LOGE(TAG, "esp_mqtt_client_init failed");
        err = ESP_FAIL;
        goto done;
    }

    portENTER_CRITICAL(&s_client_lock);
    s_client = client;
    portEXIT_CRITICAL(&s_client_lock);

    err = esp_mqtt_client_register_event(client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_mqtt_client_register_event failed (%s)", esp_err_to_name(err));
        goto fail_client;
    }

    err = esp_mqtt_client_start(client);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_mqtt_client_start failed (%s)", esp_err_to_name(err));
        goto fail_client;
    }

    /* Task work is done — library runs the connection loop internally */
done:
    if (start_ctx != NULL) {
        start_ctx->result = err;
        xTaskNotifyGive(start_ctx->waiter);
    }
    vTaskDelete(NULL);

fail_client:
    portENTER_CRITICAL(&s_client_lock);
    if (s_client == client) {
        s_client = NULL;
    }
    portEXIT_CRITICAL(&s_client_lock);
    esp_mqtt_client_destroy(client);
    goto done;
}

/* ── Public API ──────────────────────────────────────────────────────────── */

void mqtt_register_time_sync_cb(mqtt_time_sync_cb_t cb)
{
    s_time_sync_cb = cb;
}

void mqtt_register_shadow_sync_cb(mqtt_shadow_sync_cb_t cb)
{
    s_shadow_sync_cb = cb;
}

esp_err_t mqtt_register_command_handler(const char *type, mqtt_command_cb_t cb)
{
    if (type == NULL || type[0] == '\0' || cb == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    size_t type_len = strlen(type);
    if (type_len > MQTT_MAX_COMMAND_TYPE_LEN) {
        ESP_LOGW(TAG,
                 "mqtt_register_command_handler: type '%s' too long (%zu > %d)",
                 type,
                 type_len,
                 MQTT_MAX_COMMAND_TYPE_LEN);
        return ESP_ERR_INVALID_SIZE;
    }

    if (s_cmd_handler_count >= MAX_CMD_HANDLERS) {
        ESP_LOGW(TAG, "mqtt_register_command_handler: table full (max %d)", MAX_CMD_HANDLERS);
        return ESP_ERR_NO_MEM;
    }
    memcpy(s_cmd_handlers[s_cmd_handler_count].type, type, type_len + 1);
    s_cmd_handlers[s_cmd_handler_count].cb = cb;
    s_cmd_handler_count++;
    ESP_LOGI(TAG, "Command handler registered: type=%s", type);
    return ESP_OK;
}

esp_err_t mqtt_publish_command_ack(const char *command_id, bool success)
{
    return mqtt_publish_command_ack_internal(command_id, success);
}

esp_err_t mqtt_start(const char *broker_uri, const char *device_id, const char *secret_key)
{
    if (device_id == NULL || device_id[0] == '\0' || secret_key == NULL || secret_key[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    mqtt_start_ctx_t start_ctx = {
        .waiter = xTaskGetCurrentTaskHandle(),
        .result = ESP_FAIL,
    };

    strlcpy(s_broker_uri,
            (broker_uri != NULL && broker_uri[0] != '\0') ? broker_uri : SA_MQTT_BROKER_URI,
            sizeof(s_broker_uri));
    strlcpy(s_device_id, device_id, sizeof(s_device_id));
    strlcpy(s_secret_key, secret_key, sizeof(s_secret_key));
    mqtt_command_cache_reset();

    /* Build topic strings from device ID */
    snprintf(s_status_topic, sizeof(s_status_topic), "device/%s/status", s_device_id);
    snprintf(s_cmd_topic, sizeof(s_cmd_topic), "device/%s/command", s_device_id);
    snprintf(s_response_topic, sizeof(s_response_topic), "device/%s/response", s_device_id);
    snprintf(s_shadow_get_topic, sizeof(s_shadow_get_topic), "device/%s/shadow/get", s_device_id);
    snprintf(s_shadow_get_response_topic, sizeof(s_shadow_get_response_topic), "device/%s/shadow/get_response", s_device_id);
    snprintf(s_ota_topic, sizeof(s_ota_topic), "device/%s/ota/update", s_device_id);

    ESP_LOGI(TAG, "Starting MQTT client (id=%s, broker=%s)", s_device_id, s_broker_uri);

    /* Per task map: Core 1, Priority 6, 6144 B */
    ulTaskNotifyTake(pdTRUE, 0);
    BaseType_t rc = xTaskCreatePinnedToCore(mqtt_task, "mqtt_task", 6144, &start_ctx, 6, NULL, APP_CPU_NUM);
    if (rc != pdPASS) {
        ESP_LOGE(TAG, "xTaskCreatePinnedToCore failed");
        return ESP_FAIL;
    }
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    return start_ctx.result;
}

int mqtt_publish(const char *topic, const char *payload, int qos, bool retain)
{
    esp_mqtt_client_handle_t client = mqtt_client_acquire();
    if (client == NULL) {
        return -1;
    }
    int msg_id = esp_mqtt_client_publish(client, topic, payload, 0, qos, retain ? 1 : 0);
    mqtt_client_release();
    return msg_id;
}

esp_err_t mqtt_stop(void)
{
    esp_mqtt_client_handle_t client = NULL;

    portENTER_CRITICAL(&s_client_lock);
    client = s_client;
    s_client = NULL;
    portEXIT_CRITICAL(&s_client_lock);

    if (client == NULL) {
        return ESP_OK;
    }

    mqtt_client_wait_for_users();
    mqtt_pending_rx_reset();
    mqtt_command_cache_reset();
    esp_mqtt_client_stop(client);
    esp_mqtt_client_destroy(client);
    ESP_LOGI(TAG, "MQTT client stopped");
    return ESP_OK;
}
