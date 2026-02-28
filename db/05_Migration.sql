-- =============================================================================
-- MIGRACIÓN: Fix ALTER TABLE days_count bloqueado por vistas dependientes
-- Ejecutar MANUALMENTE en la BD antes de reiniciar el backend
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- PASO 1: Eliminar TODAS las vistas que dependen de streaks_history o daily_checkin
--         (en orden inverso de dependencia)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_dashboard CASCADE;
DROP VIEW IF EXISTS vw_history   CASCADE;
DROP VIEW IF EXISTS vw_user_profile CASCADE;

-- -----------------------------------------------------------------------------
-- PASO 2: Aplicar los cambios bloqueados en streaks_history
--         - days_count: default 0 → default 1  (un streak nuevo = día 1, no día 0)
--         - Asegurar NOT NULL con valor correcto
-- -----------------------------------------------------------------------------
ALTER TABLE streaks_history
    ALTER COLUMN days_count SET DEFAULT 1,
    ALTER COLUMN days_count SET NOT NULL;

-- Reparar filas existentes con days_count = 0 (datos inválidos)
UPDATE streaks_history SET days_count = 1 WHERE days_count = 0;

-- -----------------------------------------------------------------------------
-- PASO 3: Corrección adicional en daily_checkin
--         La columna fatigue en SQL debe coincidir con el campo 'fatiga' en Kotlin
--         Exposed la busca como "fatigue" (nombre real en la tabla)
-- -----------------------------------------------------------------------------
-- Verificar que la columna existe con el nombre correcto (no renombrar, solo confirmar)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'daily_checkin' AND column_name = 'fatigue'
    ) THEN
        ALTER TABLE daily_checkin ADD COLUMN fatigue INTEGER CHECK (fatigue BETWEEN 0 AND 100);
        RAISE NOTICE 'Columna fatigue agregada a daily_checkin';
    ELSE
        RAISE NOTICE 'Columna fatigue ya existe en daily_checkin — OK';
    END IF;
END $$;

-- Verificar que id_game_session existe en message (fix del error 500 en juegos)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'message' AND column_name = 'id_game_session'
    ) THEN
        ALTER TABLE message
            ADD COLUMN id_game_session INTEGER REFERENCES game_sessions(id) ON DELETE CASCADE;
        RAISE NOTICE 'Columna id_game_session agregada a message';
    ELSE
        RAISE NOTICE 'Columna id_game_session ya existe en message — OK';
    END IF;
END $$;

-- Ampliar VARCHAR de password si aún es 100 (bcrypt necesita 255)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users'
          AND column_name = 'password'
          AND character_maximum_length < 255
    ) THEN
        ALTER TABLE users ALTER COLUMN password TYPE VARCHAR(255);
        RAISE NOTICE 'Columna password ampliada a VARCHAR(255)';
    ELSE
        RAISE NOTICE 'Columna password ya es VARCHAR(255) — OK';
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- PASO 4: Recrear las vistas con las correcciones acumuladas
-- -----------------------------------------------------------------------------

-- vw_dashboard: usa user_id (columna correcta de streaks_history)
CREATE OR REPLACE VIEW vw_dashboard AS
SELECT
    dc.id_user                          AS user_id,
    dc.date_time::DATE                  AS fecha,
    COALESCE(sh.days_count, 0)          AS dias_racha,
    s.color                             AS semaforo_riesgo,
    dc.battery_cog                      AS bateria_cognitiva,
    dc.sleep_debt                       AS deuda_sueno,
    dc.hours_sleep                      AS horas_dormidas
FROM daily_checkin dc
LEFT JOIN semaphore s
       ON dc.id_semaphore = s.id
LEFT JOIN streaks_history sh
       ON dc.id_user = sh.user_id
      AND dc.date_time::DATE BETWEEN sh.start_date AND COALESCE(sh.end_date, CURRENT_DATE);

-- vw_history: usa fatigue (nombre real de la columna en la tabla)
CREATE OR REPLACE VIEW vw_history AS
SELECT
    dc.id                               AS checkin_id,
    dc.id_user                          AS user_id,
    dc.date_time                        AS fecha_hora_completa,
    dc.date_time::DATE                  AS fecha,
    dc.battery_cog                      AS nivel_bateria,
    s.color                             AS semaforo_color,
    m.mood                              AS estado_animo,
    dc.hours_sleep                      AS horas_dormidas,
    dc.fatigue                          AS fatiga_general
FROM daily_checkin dc
LEFT JOIN semaphore s ON dc.id_semaphore = s.id
LEFT JOIN mood      m ON dc.id_mood      = m.id;

-- vw_user_profile: sin cambios, se recrea por el CASCADE del DROP
CREATE OR REPLACE VIEW vw_user_profile AS
SELECT
    id                                  AS user_id,
    email                               AS correo,
    name                                AS nombre,
    last_name                           AS apellido,
    CONCAT(name, ' ', last_name)        AS nombre_completo,
    date_of_birth                       AS fecha_nacimiento
FROM users;

-- -----------------------------------------------------------------------------
-- PASO 5: Índice faltante en streaks_history (el 03_indexes.sql usaba user_id
--         pero el índice apuntaba a un campo inexistente)
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_streaks_user;
CREATE INDEX idx_streaks_user ON streaks_history(user_id);

COMMIT;

-- =============================================================================
-- VERIFICACIÓN POST-MIGRACIÓN
-- Ejecutar estas queries para confirmar que todo quedó bien:
-- =============================================================================
/*
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name IN ('streaks_history','daily_checkin','message','users')
  AND column_name IN ('days_count','fatigue','id_game_session','password')
ORDER BY table_name, column_name;

SELECT viewname FROM pg_views WHERE schemaname = 'public';

SELECT * FROM vw_dashboard  LIMIT 3;
SELECT * FROM vw_history     LIMIT 3;
SELECT * FROM vw_user_profile LIMIT 3;
*/