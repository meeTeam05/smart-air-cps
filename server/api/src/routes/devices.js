import { v4 as uuidv4 } from 'uuid';
import { createHash } from 'node:crypto';
import { createDeviceUser } from '../services/emqx.js';
import {
    cleanupDeletedDevice,
    clearDeviceCleanupJob,
    scheduleDeviceCleanupJob,
} from '../services/device-cleanup.js';
import {
    computeOtaArtifactSha256,
    listOtaArtifacts,
    resolveOtaArtifact,
} from '../services/ota.js';
import { normalizeDeviceId } from '../utils/device-id.js';
import { checkDeviceAccess } from '../utils/check-access.js';
import { RATE_LIMIT_DEVICE, MAX_DEVICES_PER_HOME } from '../constants.js';
import { cleanRequiredString, parsePositiveInt, parseUuid } from '../utils/parse.js';
import { advisoryLockId } from '../utils/advisory-lock.js';

const DEVICE_PROVISION_CLEANUP_DELAY_SECONDS = 60;
const DEVICE_PROVISION_ROLES = ['owner', 'admin'];

function hashDeviceSecret(secret) {
    return createHash('sha256').update(secret).digest('hex');
}

async function lockQuota(client, key) {
    await client.query('SELECT pg_advisory_xact_lock($1::bigint)', [advisoryLockId(key)]);
}

async function requireDeviceProvisionRole(client, homeId, userId) {
    const { rows } = await client.query(
        `SELECT hm.role
         FROM home_members hm
         JOIN users u ON u.id = hm.user_id
         WHERE hm.home_id = $1 AND hm.user_id = $2 AND u.is_active = TRUE
         FOR UPDATE OF hm`,
        [homeId, userId]
    );
    if (rows.length === 0 || !DEVICE_PROVISION_ROLES.includes(rows[0].role)) {
        const err = new Error('Forbidden');
        err.statusCode = 403;
        throw err;
    }
}

async function prepareDeviceRegistration(client, normalizedDeviceId, homeId, roomId, userId) {
    await requireDeviceProvisionRole(client, homeId, userId);
    await lockQuota(client, `quota:devices:${homeId}`);

    const { rows: existingRows } = await client.query(
        'SELECT 1 FROM devices WHERE id = $1',
        [normalizedDeviceId]
    );
    if (existingRows.length > 0) {
        const err = new Error('Device already registered');
        err.statusCode = 409;
        throw err;
    }

    const { rows: devCountRows } = await client.query(
        'SELECT COUNT(*)::int AS n FROM devices WHERE home_id = $1',
        [homeId]
    );
    if (devCountRows[0].n >= MAX_DEVICES_PER_HOME) {
        const err = new Error('device limit reached for this home');
        err.statusCode = 429;
        throw err;
    }

    if (roomId) {
        const { rows: roomRows } = await client.query(
            'SELECT 1 FROM rooms WHERE id = $1 AND home_id = $2',
            [roomId, homeId]
        );
        if (roomRows.length === 0) {
            const err = new Error('room_id does not belong to home');
            err.statusCode = 400;
            throw err;
        }
    }

    const { rows: typeRows } = await client.query(
        "SELECT id FROM device_types WHERE name = 'smart_air_v1' LIMIT 1"
    );
    return typeRows[0]?.id || null;
}

async function getDeviceOtaState(fastify, deviceId) {
    const { rows } = await fastify.db.query(
        'SELECT id, firmware_ver, online FROM devices WHERE id = $1',
        [deviceId]
    );
    return rows[0] ?? null;
}

export default async function devicesRoutes(fastify) {
    const auth = { preHandler: fastify.authenticate };

    // POST /api/devices — called after BLE provisioning
    fastify.post('/devices', { preHandler: fastify.authenticate, config: { rateLimit: RATE_LIMIT_DEVICE } }, async (request, reply) => {
        const userId = request.user.sub;
        const { device_id, name, home_id, room_id } = request.body || {};
        const normalizedDeviceId = normalizeDeviceId(device_id);
        const homeId = parseUuid(home_id);
        const roomId = room_id == null ? null : parseUuid(room_id);
        const cleanName = cleanRequiredString(name);
        if (!normalizedDeviceId || !cleanName || !homeId) {
            return reply.code(400).send({ error: 'device_id, name, home_id required' });
        }
        if (room_id != null && !roomId) {
            return reply.code(400).send({ error: 'room_id must be a valid UUID' });
        }

        const secretKey = uuidv4();
        const secretKeyHash = hashDeviceSecret(secretKey);
        let emqxUserCreated = false;
        let cleanupJobArmed = false;

        let device;
        try {
            await fastify.withTransaction(async (client) => {
                await prepareDeviceRegistration(client, normalizedDeviceId, homeId, roomId, userId);
            });

            await scheduleDeviceCleanupJob(
                fastify,
                normalizedDeviceId,
                DEVICE_PROVISION_CLEANUP_DELAY_SECONDS
            );
            cleanupJobArmed = true;

            let emqxResult;
            try {
                emqxResult = await createDeviceUser(normalizedDeviceId, secretKey, fastify.log, request.id);
            } catch (err) {
                fastify.log.warn({ err }, 'EMQX user creation failed — device not saved');
                err.statusCode = 502;
                err.clientMessage = 'Device provisioning failed';
                throw err;
            }

            emqxUserCreated = !!emqxResult?.userCreated;
            if (!emqxUserCreated) {
                const err = new Error('Device provisioning conflict');
                err.statusCode = 409;
                throw err;
            }

            device = await fastify.withTransaction(async (client) => {
                const typeId = await prepareDeviceRegistration(client, normalizedDeviceId, homeId, roomId, userId);
                const { rows } = await client.query(
                    `INSERT INTO devices (id, home_id, room_id, type_id, owner_id, name, secret_key_hash)
                     VALUES ($1, $2, $3, $4, $5, $6, $7)
                     RETURNING id, home_id, room_id, type_id, owner_id, name, firmware_ver, online, last_seen, created_at`,
                    [normalizedDeviceId, homeId, roomId, typeId, userId, cleanName, secretKeyHash]
                );
                return rows[0];
            });
            await clearDeviceCleanupJob(fastify, normalizedDeviceId);
            cleanupJobArmed = false;
        } catch (err) {
            if (cleanupJobArmed) {
                try {
                    await cleanupDeletedDevice(fastify, normalizedDeviceId);
                } catch (cleanupErr) {
                    fastify.log.warn({ err: cleanupErr }, 'EMQX compensation delete failed after DB error');
                }
            }
            if (err.code === '23505') return reply.code(409).send({ error: 'Device already registered' });
            if (err.statusCode) return reply.code(err.statusCode).send({ error: err.clientMessage || err.message });
            throw err;
        }

        return reply.code(201).send({ ...device, secret_key: secretKey });
    });

    // GET /api/devices/announce/:mac — provisioning poll: has device announced itself online?
    // Returns {announced: true} when MQTT bridge saw the device come online.
    // The record disappears after 5 minutes so stale announcements don't linger.
    fastify.get('/devices/announce/:mac', auth, async (request, reply) => {
        const userId = request.user.sub;
        const deviceId = normalizeDeviceId(request.params.mac);
        if (!deviceId) return reply.code(400).send({ error: 'Invalid mac' });
        const allowed = await checkDeviceAccess(fastify, deviceId, userId);
        if (!allowed) return reply.code(403).send({ error: 'Forbidden' });
        const announced = await fastify.redis.get(`announce:${deviceId}`);
        return { announced: !!announced };
    });

    // GET /api/devices
    fastify.get('/devices', auth, async (request, reply) => {
        const userId = request.user.sub;
        const limit = parsePositiveInt(request.query.limit, 100, 500);
        const offset = parsePositiveInt(request.query.offset, 0);
        if (limit === null || offset === null) {
            return reply.code(400).send({ error: 'limit and offset must be non-negative integers' });
        }
        const { rows } = await fastify.db.query(
            `SELECT d.id, d.name, d.home_id, d.room_id, d.online, d.last_seen, d.firmware_ver, d.created_at, d.auto_mode,
                    s.reported->>'mode' AS mode,
                    CASE
                        WHEN lower(s.reported->>'relay_1') IN ('true', 'false')
                            THEN lower(s.reported->>'relay_1') = 'true'
                        ELSE NULL
                    END AS relay_1,
                    CASE
                        WHEN lower(s.reported->>'relay_2') IN ('true', 'false')
                            THEN lower(s.reported->>'relay_2') = 'true'
                        ELSE NULL
                    END AS relay_2,
                    CASE
                        WHEN lower(s.reported->>'relay_3') IN ('true', 'false')
                            THEN lower(s.reported->>'relay_3') = 'true'
                        ELSE NULL
                    END AS relay_3
             FROM devices d
             JOIN home_members hm ON hm.home_id = d.home_id
             LEFT JOIN device_shadows s ON s.device_id = d.id
             WHERE hm.user_id = $1
             ORDER BY d.created_at, d.id LIMIT $2 OFFSET $3`,
            [userId, limit, offset]
        );
        return rows;
    });

    fastify.get('/devices/:id/ota/versions', auth, async (request, reply) => {
        const userId = request.user.sub;
        const deviceId = normalizeDeviceId(request.params.id);
        if (!deviceId) return reply.code(400).send({ error: 'Invalid device ID' });

        const allowed = await checkDeviceAccess(fastify, deviceId, userId);
        if (!allowed) return reply.code(403).send({ error: 'Forbidden' });

        const device = await getDeviceOtaState(fastify, deviceId);
        if (!device) return reply.code(404).send({ error: 'Not found' });

        const versions = await listOtaArtifacts();
        return {
            device_id: device.id,
            current_version: device.firmware_ver,
            device_online: device.online,
            versions,
        };
    });

    fastify.post('/devices/:id/ota', {
        preHandler: fastify.authenticate,
        config: { rateLimit: RATE_LIMIT_DEVICE },
    }, async (request, reply) => {
        const userId = request.user.sub;
        const deviceId = normalizeDeviceId(request.params.id);
        if (!deviceId) return reply.code(400).send({ error: 'Invalid device ID' });

        const version = cleanRequiredString(request.body?.version);
        if (!version) return reply.code(400).send({ error: 'version required' });

        const allowed = await checkDeviceAccess(fastify, deviceId, userId);
        if (!allowed) return reply.code(403).send({ error: 'Forbidden' });

        const device = await getDeviceOtaState(fastify, deviceId);
        if (!device) return reply.code(404).send({ error: 'Not found' });
        if (!device.online) return reply.code(409).send({ error: 'device offline' });

        const artifact = await resolveOtaArtifact(version);
        if (!artifact) return reply.code(404).send({ error: 'OTA version not found' });

        const sha256 = await computeOtaArtifactSha256(artifact.filePath);
        await fastify.mqttPublish(
            `device/${deviceId}/ota/update`,
            JSON.stringify({
                url: artifact.url,
                sha256,
            }),
            { qos: 1, retain: false }
        );

        return reply.code(202).send({
            device_id: device.id,
            version: artifact.version,
            filename: artifact.filename,
            status: 'accepted',
        });
    });

    // PUT /api/devices/:id
    fastify.put('/devices/:id', auth, async (request, reply) => {
        const userId = request.user.sub;
        const deviceId = normalizeDeviceId(request.params.id);
        if (!deviceId) return reply.code(400).send({ error: 'Invalid device ID' });
        const allowed = await checkDeviceAccess(fastify, deviceId, userId);
        if (!allowed) return reply.code(403).send({ error: 'Forbidden' });

        const { name, room_id } = request.body || {};
        const cleanName = name === undefined ? undefined : cleanRequiredString(name);
        if (name !== undefined && !cleanName) return reply.code(400).send({ error: 'name must be non-empty' });
        const roomProvided = room_id !== undefined;
        const roomId = room_id === null || room_id === undefined ? null : parseUuid(room_id);
        if (roomProvided && room_id !== null && !roomId) {
            return reply.code(400).send({ error: 'room_id must be a valid UUID or null' });
        }
        if (roomId) {
            const { rows: roomRows } = await fastify.db.query(
                `SELECT 1 FROM rooms r
                 JOIN devices d ON d.home_id = r.home_id
                 WHERE r.id = $1 AND d.id = $2`,
                [roomId, deviceId]
            );
            if (roomRows.length === 0) return reply.code(400).send({ error: 'room_id does not belong to device home' });
        }
        const { rows } = await fastify.db.query(
            `UPDATE devices SET
               name = CASE WHEN $1 THEN $2 ELSE name END,
               room_id = CASE WHEN $3 THEN $4 ELSE room_id END
             WHERE id = $5 RETURNING id, name, home_id, room_id, online, last_seen, firmware_ver, created_at`,
            [name !== undefined, cleanName ?? null, roomProvided, roomId, deviceId]
        );
        if (rows.length === 0) return reply.code(404).send({ error: 'Not found' });
        return rows[0];
    });

    // PUT /api/devices/:id/auto_mode
    fastify.put('/devices/:id/auto_mode', auth, async (request, reply) => {
        const userId = request.user.sub;
        const deviceId = normalizeDeviceId(request.params.id);
        if (!deviceId) return reply.code(400).send({ error: 'Invalid device ID' });

        const allowed = await checkDeviceAccess(fastify, deviceId, userId);
        if (!allowed) return reply.code(403).send({ error: 'Forbidden' });

        const { auto_mode } = request.body ?? {};
        if (typeof auto_mode !== 'boolean') {
            return reply.code(400).send({ error: 'auto_mode must be boolean' });
        }

        const { rows } = await fastify.db.query(
            'UPDATE devices SET auto_mode = $1 WHERE id = $2 RETURNING id, auto_mode',
            [auto_mode, deviceId]
        );
        if (rows.length === 0) return reply.code(404).send({ error: 'Not found' });
        return rows[0];
    });

    // DELETE /api/devices/:id
    fastify.delete('/devices/:id', auth, async (request, reply) => {
        const userId = request.user.sub;
        const deviceId = normalizeDeviceId(request.params.id);
        if (!deviceId) return reply.code(400).send({ error: 'Invalid device ID' });

        const deletedDeviceId = await fastify.withTransaction(async (client) => {
            const { rows: devRows } = await client.query(
                'SELECT id, home_id FROM devices WHERE id = $1 FOR UPDATE',
                [deviceId]
            );
            if (devRows.length === 0) return null;

            const { rows: roleRows } = await client.query(
                `SELECT hm.role
                 FROM home_members hm
                 JOIN users u ON u.id = hm.user_id
                 WHERE hm.home_id = $1 AND hm.user_id = $2 AND u.is_active = TRUE`,
                [devRows[0].home_id, userId]
            );
            if (roleRows.length === 0 || !['owner', 'admin'].includes(roleRows[0].role)) {
                const err = new Error('Forbidden');
                err.statusCode = 403;
                throw err;
            }

            await client.query('DELETE FROM devices WHERE id = $1', [deviceId]);
            return devRows[0].id;
        });
        if (!deletedDeviceId) return reply.code(404).send({ error: 'Not found' });

        await cleanupDeletedDevice(fastify, deletedDeviceId);

        return reply.code(204).send();
    });
}
