import { config } from '../config.js';

function authHeader() {
    return 'Basic ' + Buffer.from(`${config.emqx.apiKey}:${config.emqx.apiSecret}`).toString('base64');
}

function buildHeaders(requestId) {
    const headers = {
        'Content-Type': 'application/json',
        Authorization: authHeader(),
    };
    if (typeof requestId === 'string' && requestId.trim() !== '') {
        headers['X-Request-Id'] = requestId;
    }
    return headers;
}

async function emqxFetch(path, method, body, options = {}) {
    const timeout = AbortSignal.timeout(config.emqx.apiTimeoutMs);
    let res;
    try {
        res = await fetch(`${config.emqx.apiUrl}${path}`, {
            method,
            headers: buildHeaders(options.requestId),
            body: body ? JSON.stringify(body) : undefined,
            signal: timeout,
        });
    } catch (err) {
        if (err?.name === 'TimeoutError' || err?.name === 'AbortError') {
            throw new Error(`EMQX API ${method} ${path} timed out after ${config.emqx.apiTimeoutMs}ms`, { cause: err });
        }
        throw err;
    }
    const okStatuses = new Set(options.okStatuses || []);
    if (!res.ok && !okStatuses.has(res.status)) {
        await res.text();
        throw new Error(`EMQX API ${method} ${path} failed with status ${res.status}`);
    }
    return res;
}

async function createAuthUser(userId, password, requestId = null) {
    return emqxFetch(
        '/api/v5/authentication/password_based:built_in_database/users',
        'POST',
        { user_id: userId, password, is_superuser: false },
        { okStatuses: [409], requestId }
    );
}

async function updateAuthUser(userId, password, requestId = null) {
    return emqxFetch(
        `/api/v5/authentication/password_based:built_in_database/users/${encodeURIComponent(userId)}`,
        'PUT',
        { password, is_superuser: false },
        { requestId }
    );
}

async function clearAuthorizationCache(requestId = null) {
    await emqxFetch('/api/v5/authorization/cache', 'DELETE', undefined, { okStatuses: [404], requestId });
}

async function upsertUserRules(username, rules, requestId = null) {
    const body = { username, rules };
    const createRes = await emqxFetch(
        '/api/v5/authorization/sources/built_in_database/rules/users',
        'POST',
        [body],
        { okStatuses: [409], requestId }
    );
    if (createRes.status === 409) {
        await emqxFetch(
            `/api/v5/authorization/sources/built_in_database/rules/users/${encodeURIComponent(username)}`,
            'PUT',
            body,
            { requestId }
        );
    }
}

function deviceRules(deviceId) {
    return [
        { topic: `device/${deviceId}/status`, action: 'publish', permission: 'allow' },
        { topic: `device/${deviceId}/telemetry`, action: 'publish', permission: 'allow' },
        { topic: `device/${deviceId}/response`, action: 'publish', permission: 'allow' },
        { topic: `device/${deviceId}/shadow/report`, action: 'publish', permission: 'allow' },
        { topic: `device/${deviceId}/shadow/get`, action: 'publish', permission: 'allow' },
        { topic: `device/${deviceId}/ota/progress`, action: 'publish', permission: 'allow' },
        { topic: `device/${deviceId}/command`, action: 'subscribe', permission: 'allow' },
        { topic: `device/${deviceId}/shadow/get_response`, action: 'subscribe', permission: 'allow' },
        { topic: `device/${deviceId}/ota/update`, action: 'subscribe', permission: 'allow' },
    ];
}

function bridgeRules() {
    return [
        { topic: 'device/+/status', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/telemetry', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/response', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/shadow/report', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/shadow/get', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/ota/progress', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/command', action: 'publish', permission: 'allow' },
        { topic: 'device/+/shadow/get_response', action: 'publish', permission: 'allow' },
        { topic: 'device/+/ota/update', action: 'publish', permission: 'allow' },
    ];
}

export async function ensureBridgeUser() {
    const username = config.emqx.mqttUser;
    const password = config.emqx.mqttPassword;
    if (!password) throw new Error('EMQX_MQTT_PASSWORD is required to provision bridge user');
    const userRes = await createAuthUser(username, password);
    if (userRes.status === 409) {
        await updateAuthUser(username, password);
    }
    await upsertUserRules(username, bridgeRules());
    await clearAuthorizationCache();
}

export async function ensureAiUser() {
    const username = config.ai.mqttUser;
    const password = config.ai.mqttPassword;
    if (!password) return; // AI service not configured, skip silently
    const aiRules = [
        { topic: 'device/+/telemetry', action: 'subscribe', permission: 'allow' },
        { topic: 'device/+/command',   action: 'publish',   permission: 'allow' },
    ];
    const userRes = await createAuthUser(username, password);
    if (userRes.status === 409) {
        await updateAuthUser(username, password);
    }
    await upsertUserRules(username, aiRules);
    await clearAuthorizationCache();
}

export async function checkEmqxApiHealth(requestId = null) {
    await emqxFetch('/status', 'GET', undefined, { requestId });
}

export async function createDeviceUser(deviceId, secretKey, logger = null, requestId = null) {
    const userRes = await createAuthUser(deviceId, secretKey, requestId);

    const userCreated = userRes.status !== 409;
    if (!userCreated) return { userCreated: false };

    try {
        await upsertUserRules(deviceId, deviceRules(deviceId), requestId);
    } catch (err) {
        // Compensation: delete user if ACL creation failed and user was just created
        if (userCreated) {
            try {
                await emqxFetch(
                    `/api/v5/authentication/password_based:built_in_database/users/${encodeURIComponent(deviceId)}`,
                    'DELETE',
                    undefined,
                    { okStatuses: [404], requestId }
                );
            } catch (delErr) {
                logger?.error(
                    { err: delErr, deviceId },
                    'EMQX compensation delete failed after ACL setup error'
                );
            }
        }
        throw err;
    }

    return { userCreated };
}

export async function deleteDeviceUser(deviceId) {
    await emqxFetch(
        `/api/v5/authentication/password_based:built_in_database/users/${encodeURIComponent(deviceId)}`,
        'DELETE',
        undefined,
        { okStatuses: [404] }
    );
    await emqxFetch(
        `/api/v5/authorization/sources/built_in_database/rules/users/${encodeURIComponent(deviceId)}`,
        'DELETE',
        undefined,
        { okStatuses: [404] }
    );
}
