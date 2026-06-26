import test from 'node:test';
import assert from 'node:assert/strict';

import Fastify from 'fastify';

import devicesRoutes from '../src/routes/devices.js';

const DEVICE_ID = 'aa:bb:cc:dd:ee:ff';

function buildApp({ deviceExists = true, updateResult = { id: DEVICE_ID, auto_mode: true } } = {}) {
    const app = Fastify({ logger: false });

    app.decorate('authenticate', async (request) => {
        request.user = { sub: 'user-1' };
    });
    app.decorate('db', {
        async query(sql, params) {
            if (sql.includes('SELECT 1 FROM devices d')) {
                return deviceExists
                    ? { rows: [{ ok: 1 }], rowCount: 1 }
                    : { rows: [], rowCount: 0 };
            }
            if (sql.includes('UPDATE devices SET auto_mode')) {
                assert.deepEqual(params[1], DEVICE_ID);
                return updateResult
                    ? { rows: [updateResult], rowCount: 1 }
                    : { rows: [], rowCount: 0 };
            }
            // Catch-all for other device queries (list, etc.)
            return { rows: [], rowCount: 0 };
        },
    });
    app.decorate('redis', {
        async get() { return null; },
        async set() { return 'OK'; },
        async eval() { return 1; },
        async del() { return 1; },
    });
    app.decorate('mqttPublish', async () => {});
    app.decorate('withTransaction', async (fn) => fn(app.db));

    return app;
}

test('PUT /devices/:id/auto_mode sets auto_mode to true', async () => {
    const app = buildApp({ updateResult: { id: DEVICE_ID, auto_mode: true } });

    try {
        await app.register(devicesRoutes);
        const res = await app.inject({
            method: 'PUT',
            url: `/devices/${DEVICE_ID}/auto_mode`,
            payload: { auto_mode: true },
        });

        assert.equal(res.statusCode, 200);
        assert.deepEqual(res.json(), { id: DEVICE_ID, auto_mode: true });
    } finally {
        await app.close();
    }
});

test('PUT /devices/:id/auto_mode sets auto_mode to false', async () => {
    const app = buildApp({ updateResult: { id: DEVICE_ID, auto_mode: false } });

    try {
        await app.register(devicesRoutes);
        const res = await app.inject({
            method: 'PUT',
            url: `/devices/${DEVICE_ID}/auto_mode`,
            payload: { auto_mode: false },
        });

        assert.equal(res.statusCode, 200);
        assert.deepEqual(res.json(), { id: DEVICE_ID, auto_mode: false });
    } finally {
        await app.close();
    }
});

test('PUT /devices/:id/auto_mode rejects non-boolean value', async () => {
    const app = buildApp();

    try {
        await app.register(devicesRoutes);
        const res = await app.inject({
            method: 'PUT',
            url: `/devices/${DEVICE_ID}/auto_mode`,
            payload: { auto_mode: 'yes' },
        });

        assert.equal(res.statusCode, 400);
        assert.deepEqual(res.json(), { error: 'auto_mode must be boolean' });
    } finally {
        await app.close();
    }
});

test('PUT /devices/:id/auto_mode rejects missing body field', async () => {
    const app = buildApp();

    try {
        await app.register(devicesRoutes);
        const res = await app.inject({
            method: 'PUT',
            url: `/devices/${DEVICE_ID}/auto_mode`,
            payload: {},
        });

        assert.equal(res.statusCode, 400);
        assert.deepEqual(res.json(), { error: 'auto_mode must be boolean' });
    } finally {
        await app.close();
    }
});

test('PUT /devices/:id/auto_mode returns 403 when user lacks device access', async () => {
    const app = buildApp({ deviceExists: false });

    try {
        await app.register(devicesRoutes);
        const res = await app.inject({
            method: 'PUT',
            url: `/devices/${DEVICE_ID}/auto_mode`,
            payload: { auto_mode: true },
        });

        assert.equal(res.statusCode, 403);
        assert.deepEqual(res.json(), { error: 'Forbidden' });
    } finally {
        await app.close();
    }
});
