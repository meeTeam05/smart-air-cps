CREATE TABLE IF NOT EXISTS ai_actions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id   TEXT NOT NULL,
    relay       INTEGER NOT NULL,
    state       BOOLEAN NOT NULL,
    class_id    INTEGER NOT NULL,
    reason      TEXT NOT NULL,
    temperature NUMERIC(6,2),
    humidity    NUMERIC(6,2),
    co_ppm      NUMERIC(8,2),
    no2_ppm     NUMERIC(8,2),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_actions_device_id_created_at
    ON ai_actions (device_id, created_at DESC);
