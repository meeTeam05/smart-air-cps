import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const REQUIRED_RUNTIME_ENV_VARS = [
    'JWT_SECRET',
    'POSTGRES_PASSWORD',
    'REDIS_PASSWORD',
    'EMQX_API_KEY',
    'EMQX_API_SECRET',
    'EMQX_MQTT_PASSWORD',
];

function env(name, fallback = '') {
    const value = process.env[name];
    return typeof value === 'string' && value.trim() !== '' ? value : fallback;
}

function envOptional(name) {
    const value = process.env[name];
    return typeof value === 'string' && value.trim() !== '' ? value : null;
}

function intEnv(name, fallback) {
    const value = Number.parseInt(process.env[name] || '', 10);
    return Number.isInteger(value) && value > 0 ? value : fallback;
}

function parseAllowedOrigins() {
    const origins = env('CORS_ORIGINS', 'https://minhnhat05.xyz')
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean);

    if (process.env.NODE_ENV === 'production') {
        const hasInvalidOrigin = origins.length === 0
            || origins.some((origin) => origin === '*' || !origin.startsWith('https://'));
        if (hasInvalidOrigin) {
            throw new Error('CORS_ORIGINS must contain explicit HTTPS origins in production');
        }
    }

    return origins;
}

export function getMissingRequiredEnvVars(requiredVars = REQUIRED_RUNTIME_ENV_VARS) {
    return requiredVars.filter((name) => {
        const value = process.env[name];
        return typeof value !== 'string' || value.trim() === '';
    });
}

export const config = Object.freeze({
    get nodeEnv() { return env('NODE_ENV'); },
    get isProduction() { return process.env.NODE_ENV === 'production'; },
    get isDevelopment() { return process.env.NODE_ENV === 'development'; },
    get port() { return intEnv('PORT', 3000); },
    get logLevel() { return env('LOG_LEVEL', 'info'); },
    get bodyLimitBytes() { return intEnv('BODY_LIMIT_BYTES', 65_536); },
    get corsOrigins() { return parseAllowedOrigins(); },
    db: Object.freeze({
        get host() { return env('POSTGRES_HOST', 'postgres'); },
        get port() { return intEnv('POSTGRES_PORT', 5432); },
        get database() { return env('POSTGRES_DB', 'smartair'); },
        get user() { return env('POSTGRES_USER', 'smartair'); },
        get password() { return process.env.POSTGRES_PASSWORD; },
        get poolMax() { return intEnv('PG_POOL_MAX', 20); },
        get idleTimeoutMs() { return intEnv('PG_IDLE_TIMEOUT_MS', 30_000); },
        get connectionTimeoutMs() { return intEnv('PG_CONNECTION_TIMEOUT_MS', 5_000); },
        get statementTimeoutMs() { return intEnv('PG_STATEMENT_TIMEOUT_MS', 10_000); },
    }),
    redis: Object.freeze({
        get host() { return env('REDIS_HOST', 'redis'); },
        get port() { return intEnv('REDIS_PORT', 6379); },
        get password() { return process.env.REDIS_PASSWORD; },
    }),
    jwt: Object.freeze({
        get secret() { return process.env.JWT_SECRET; },
        get expiresIn() { return env('JWT_EXPIRES_IN', '15m'); },
    }),
    refreshTokens: Object.freeze({
        get expiresDays() { return intEnv('REFRESH_TOKEN_EXPIRES_DAYS', 30); },
        get reuseMarkerSweepIntervalMs() { return intEnv('REFRESH_REUSE_MARKER_SWEEP_INTERVAL_MS', 3_600_000); },
    }),
    emqx: Object.freeze({
        get apiUrl() { return env('EMQX_API_URL', 'http://emqx:18083'); },
        get apiTimeoutMs() { return intEnv('EMQX_API_TIMEOUT_MS', 5_000); },
        get apiKey() { return env('EMQX_API_KEY'); },
        get apiSecret() { return env('EMQX_API_SECRET'); },
        get mqttUrl() { return env('EMQX_MQTT_URL', 'mqtt://emqx:1883'); },
        get mqttUser() { return env('EMQX_MQTT_USER', 'sa-server'); },
        get mqttPassword() { return env('EMQX_MQTT_PASSWORD'); },
        get mqttClientId() { return env('EMQX_MQTT_CLIENT_ID', 'sa-api-bridge'); },
        get cleanupRetryIntervalMs() { return 300_000; },
        get cleanupRetryLimit() { return 100; },
    }),
    mqtt: Object.freeze({
        get publishTimeoutMs() { return intEnv('MQTT_PUBLISH_TIMEOUT_MS', 5_000); },
        get provisionRetryMs() { return intEnv('MQTT_PROVISION_RETRY_MS', 5_000); },
        get reconnectPeriodMs() { return 2_000; },
        get connectTimeoutMs() { return 30_000; },
    }),
    ai: Object.freeze({
        get mqttUser() { return envOptional('MQTT_USERNAME') ?? 'sa-ai'; },
        get mqttPassword() { return envOptional('MQTT_PASSWORD'); },
    }),
    ota: Object.freeze({
        get filesDir() { return env('OTA_FILES_DIR', path.resolve(__dirname, '../../ota-files')); },
        get publicBaseUrl() { return env('OTA_PUBLIC_BASE_URL', 'https://minhnhat05.xyz').replace(/\/+$/, ''); },
    }),
    commands: Object.freeze({
        get sentTimeoutSeconds() { return intEnv('COMMAND_SENT_TIMEOUT_SECONDS', 420); },
        get pendingTimeoutSeconds() { return intEnv('COMMAND_PENDING_TIMEOUT_SECONDS', 90); },
        get timeoutSweepIntervalMs() { return intEnv('COMMAND_TIMEOUT_SWEEP_INTERVAL_MS', 30_000); },
    }),
    devices: Object.freeze({
        get staleThresholdSeconds() { return intEnv('STALE_DEVICE_THRESHOLD_SECONDS', 180); },
        get staleSweepIntervalMs()  { return intEnv('STALE_DEVICE_SWEEP_INTERVAL_MS', 120_000); },
    }),
    realtime: Object.freeze({
        get replayLimit() { return intEnv('REALTIME_REPLAY_LIMIT', 1_000); },
        get heartbeatMs() { return intEnv('REALTIME_HEARTBEAT_MS', 25_000); },
        get maxClients() { return intEnv('REALTIME_MAX_CLIENTS', 1_000); },
        get maxClientsPerIp() { return intEnv('REALTIME_MAX_CLIENTS_PER_IP', 10); },
        get reconnectInitialDelayMs() { return 1_000; },
        get reconnectMaxDelayMs() { return 30_000; },
        get eventRetentionHours() { return intEnv('REALTIME_EVENT_RETENTION_HOURS', 24); },
        get eventRetentionSweepIntervalMs() { return intEnv('REALTIME_EVENT_RETENTION_SWEEP_INTERVAL_MS', 3_600_000); },
    }),
    dataRetention: Object.freeze({
        get commandRetentionDays() { return intEnv('COMMAND_RETENTION_DAYS', 30); },
        get refreshTokenRetentionDays() { return 30; },
        get sweepIntervalMs() { return intEnv('DATA_RETENTION_SWEEP_INTERVAL_MS', 3_600_000); },
    }),
});
