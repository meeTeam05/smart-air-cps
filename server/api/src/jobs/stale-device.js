import { createRealtimeEvent } from '../services/realtime-events.js';
import { registerNonOverlappingIntervalJob } from './scheduler.js';
import { config } from '../config.js';

export function registerStaleDeviceJob(fastify, options = {}) {
    const thresholdSeconds = options.thresholdSeconds ?? config.devices.staleThresholdSeconds;
    const sweepIntervalMs = options.sweepIntervalMs ?? config.devices.staleSweepIntervalMs;

    const runSweep = async () => {
        let client;

        try {
            client = await fastify.db.connect();
            await client.query('BEGIN');
            const result = await client.query(
                `UPDATE devices
                 SET online = false
                 WHERE online = true
                   AND last_seen < NOW() - ($1 * INTERVAL '1 second')
                 RETURNING id`,
                [thresholdSeconds]
            );

            for (const row of result.rows) {
                await createRealtimeEvent(client, {
                    type: 'device.status',
                    deviceId: row.id,
                    payload: { online: false },
                    idempotencyKey: `device.status:${row.id}:stale`,
                });
            }

            await client.query('COMMIT');

            if (result.rowCount > 0) {
                fastify.log.info(
                    { updated: result.rowCount, thresholdSeconds },
                    'stale device sweep marked devices offline'
                );
            }
        } catch (err) {
            if (client) {
                try {
                    await client.query('ROLLBACK');
                } catch (rollbackErr) {
                    fastify.log.error({ err: rollbackErr }, 'stale device sweep rollback failed');
                }
            }
            fastify.log.error({ err }, 'stale device sweep failed');
        } finally {
            client?.release();
        }
    };

    registerNonOverlappingIntervalJob(fastify, {
        intervalMs: sweepIntervalMs,
        jobName: 'stale device',
        runImmediately: true,
        task: runSweep,
    });
}
