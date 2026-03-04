-- =============================================================================
-- MIGRACIÓN 06: Fix columna metadata JSONB → TEXT en game_sessions
--               Causa raíz del 500 en POST /games/neuro-reflex y /games/memory
-- =============================================================================
-- SÍNTOMA:  500 "Error interno del servidor" al jugar Taptap o Memorama
-- CAUSA:    Exposed usa text() para 'metadata' pero la columna en BD es JSONB.
--           Postgres rechaza el INSERT porque el driver JDBC envía el valor
--           como tipo TEXT sin hacer el cast implícito a JSONB.
--           Error real en los logs del backend:
--           "ERROR: column "metadata" is of type jsonb but expression is of type text"
-- SOLUCIÓN: Convertir la columna a TEXT (Exposed text() = SQL TEXT).
--           Los datos JSON siguen siendo válidos como strings TEXT.
-- =============================================================================

BEGIN;

-- Paso 1: Droppear vistas que puedan depender de game_sessions (por si acaso)
DROP VIEW IF EXISTS vw_dashboard    CASCADE;
DROP VIEW IF EXISTS vw_history      CASCADE;
DROP VIEW IF EXISTS vw_user_profile CASCADE;

-- Paso 2: Convertir metadata de JSONB a TEXT
--         USING metadata::TEXT hace el cast de los datos existentes
ALTER TABLE game_sessions
    ALTER COLUMN metadata TYPE TEXT USING metadata::TEXT;

-- Paso 3: Hacer start_time y end_time nullable para que coincidan con Exposed
--         (Exposed los declara como .nullable(), Postgres los tenía NOT NULL)
ALTER TABLE game_sessions
    ALTER COLUMN start_time DROP NOT NULL,
    ALTER COLUMN end_time   DROP NOT NULL;

-- Paso 4: Recrear vistas
CREATE OR REPLACE VIEW vw_dashboard AS
SELECT
    dc.id_user                      AS user_id,
    dc.date_time::DATE              AS fecha,
    COALESCE(sh.days_count, 0)      AS dias_racha,
    s.color                         AS semaforo_riesgo,
    dc.battery_cog                  AS bateria_cognitiva,
    dc.sleep_debt                   AS deuda_sueno,
    dc.hours_sleep                  AS horas_dormidas
FROM daily_checkin dc
LEFT JOIN semaphore s
       ON dc.id_semaphore = s.id
LEFT JOIN streaks_history sh
       ON dc.id_user = sh.user_id
      AND dc.date_time::DATE
          BETWEEN sh.start_date AND COALESCE(sh.end_date, CURRENT_DATE);

CREATE OR REPLACE VIEW vw_history AS
SELECT
    dc.id                           AS checkin_id,
    dc.id_user                      AS user_id,
    dc.date_time                    AS fecha_hora_completa,
    dc.date_time::DATE              AS fecha,
    dc.battery_cog                  AS nivel_bateria,
    s.color                         AS semaforo_color,
    m.mood                          AS estado_animo,
    dc.hours_sleep                  AS horas_dormidas,
    dc.fatigue                      AS fatiga_general
FROM daily_checkin dc
LEFT JOIN semaphore s ON dc.id_semaphore = s.id
LEFT JOIN mood      m ON dc.id_mood      = m.id;

CREATE OR REPLACE VIEW vw_user_profile AS
SELECT
    id                              AS user_id,
    email                           AS correo,
    name                            AS nombre,
    last_name                       AS apellido,
    CONCAT(name, ' ', last_name)    AS nombre_completo,
    date_of_birth                   AS fecha_nacimiento
FROM users;

COMMIT;

-- Verificación:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'game_sessions'
-- ORDER BY ordinal_position;
--
-- Debe mostrar:
--   metadata  | text      | YES
--   start_time| timestamp | YES
--   end_time  | timestamp | YES