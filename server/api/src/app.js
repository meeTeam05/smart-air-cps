import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import cookie from '@fastify/cookie';

import { ALLOWED_ORIGINS } from './constants.js';
import { config, getMissingRequiredEnvVars, REQUIRED_RUNTIME_ENV_VARS } from './config.js';
import dbPlugin from './plugins/db.js';
import redisPlugin from './plugins/redis.js';
import authPlugin from './plugins/auth.js';
import mqttPlugin from './plugins/mqtt.js';
import realtimePlugin from './plugins/realtime.js';
import { sanitizeLoggedError } from './utils/log-sanitize.js';

import healthRoutes from './routes/health.js';
import authRoutes from './routes/auth.js';
import homesRoutes from './routes/homes.js';
import devicesRoutes from './routes/devices.js';
import shadowRoutes from './routes/shadow.js';
import commandsRoutes from './routes/commands.js';
import telemetryRoutes from './routes/telemetry.js';
import notificationsRoutes from './routes/notifications.js';
import realtimeRoutes from './routes/realtime.js';
import { registerCommandTimeoutJob } from './jobs/command-timeout.js';
import { registerStaleDeviceJob } from './jobs/stale-device.js';
import { registerDataRetentionJob } from './jobs/data-retention.js';
import { registerEmqxCleanupRetryJob } from './jobs/emqx-cleanup-retry.js';
import { registerRefreshTokenMarkerCleanupJob } from './jobs/refresh-token-marker-cleanup.js';
import { registerRealtimeEventRetentionJob } from './jobs/realtime-event-retention.js';

function getSafeClientErrorMessage(error, statusCode) {
    if (error.validation) return 'Invalid request payload';
    if (statusCode === 400) return 'Bad request';
    if (statusCode === 401) return 'Unauthorized';
    if (statusCode === 403) return 'Forbidden';
    if (statusCode === 404) return 'Not found';
    if (statusCode === 405) return 'Method not allowed';
    if (statusCode === 409) return 'Conflict';
    if (statusCode === 429) return 'Too many requests';
    return 'Internal server error';
}

const missingRequiredEnvVars = getMissingRequiredEnvVars(REQUIRED_RUNTIME_ENV_VARS);
if (missingRequiredEnvVars.length > 0) {
    console.error('FATAL: Missing required environment variables for server/api startup:');
    for (const name of missingRequiredEnvVars) {
        console.error(`- ${name}`);
    }
    process.exit(1);
}

const fastify = Fastify({
    bodyLimit: config.bodyLimitBytes,
    logger: {
        level: config.logLevel,
        redact: [
            'req.headers.authorization',
            'req.headers.cookie',
            'req.body.password',
            'req.body.refreshToken',
            'req.body.secret_key',
            'res.body.refreshToken',
            'res.body.secret_key',
            'res.headers["set-cookie"]',
        ],
        serializers: {
            err: sanitizeLoggedError,
        },
    },
});

// ── Core plugins ────────────────────────────────────────────────
await fastify.register(cors, { origin: ALLOWED_ORIGINS, credentials: true });
await fastify.register(cookie);
await fastify.register(dbPlugin);
await fastify.register(redisPlugin);
await fastify.register(authPlugin);
await fastify.register(mqttPlugin);
await fastify.register(realtimePlugin);

registerCommandTimeoutJob(fastify);
registerStaleDeviceJob(fastify);
registerDataRetentionJob(fastify);
registerEmqxCleanupRetryJob(fastify);
registerRefreshTokenMarkerCleanupJob(fastify);
registerRealtimeEventRetentionJob(fastify);

// ── Rate limiting — applied globally, tighter on auth routes ────
await fastify.register(rateLimit, {
    global: false,
});

// ── Routes — all under /api prefix ──────────────────────────────
await fastify.register(healthRoutes, { prefix: '/api' });
await fastify.register(authRoutes, { prefix: '/api' });
await fastify.register(homesRoutes, { prefix: '/api' });
await fastify.register(devicesRoutes, { prefix: '/api' });
await fastify.register(shadowRoutes, { prefix: '/api' });
await fastify.register(commandsRoutes, { prefix: '/api' });
await fastify.register(telemetryRoutes, { prefix: '/api' });
await fastify.register(notificationsRoutes, { prefix: '/api' });
await fastify.register(realtimeRoutes, { prefix: '/api' });

// ── Global Error Handler ─────────────────────────────────────────
fastify.setErrorHandler((error, request, reply) => {
    const rawStatusCode = Number(error?.statusCode);
    const statusCode = Number.isInteger(rawStatusCode) && rawStatusCode >= 400 && rawStatusCode < 600
        ? rawStatusCode
        : 500;

    // Server-side: structured log with request context
    fastify.log.error(
        {
            err: error,
            requestId: request.id,
            method: request.method,
            url: request.url,
            ip: request.ip,
            userAgent: request.headers['user-agent'],
            statusCode,
        },
        'Request failed'
    );

    if (reply.sent) return;

    // Client-side: sanitized payload
    if (statusCode >= 500) {
        return reply.code(500).send({ error: 'Internal server error' });
    }

    // Respect explicit statusCode for known operational errors (4xx)
    const safeMessage = getSafeClientErrorMessage(error, statusCode);
    reply.code(statusCode).send({
        error: safeMessage,
        ...(config.isDevelopment ? { originalError: error.message } : {})
    });
});

// ── Start ────────────────────────────────────────────────────────
try {
    await fastify.listen({ port: config.port, host: '0.0.0.0' });
} catch (err) {
    fastify.log.error(err);
    process.exit(1);
}

// ── Graceful shutdown ────────────────────────────────────────────
for (const signal of ['SIGTERM', 'SIGINT']) {
    process.on(signal, async () => {
        fastify.log.info({ signal }, 'Shutting down gracefully');
        await fastify.close();
        process.exit(0);
    });
}
