-- =============================================================================
-- MIGRACIÓN 07: Revertir metadata de TEXT → JSONB
--
-- La migración 06 convirtió metadata a TEXT pensando que era el problema,
-- pero el error real es que Exposed enviaba VARCHAR al driver JDBC.
-- La columna debe ser JSONB — ahora usamos JsonbColumnType (PGobject)
-- que hace el binding correcto sin importar el tipo SQL de la columna.
-- =============================================================================

BEGIN;

DROP VIEW IF EXISTS vw_dashboard    CASCADE;
DROP VIEW IF EXISTS vw_history      CASCADE;
DROP VIEW IF EXISTS vw_user_profile CASCADE;

-- Revertir metadata a JSONB (su tipo correcto según el schema original)
-- USING convierte los strings TEXT existentes a JSONB válido
ALTER TABLE game_sessions
    ALTER COLUMN metadata TYPE JSONB USING metadata::JSONB;

-- Asegurarse de que start_time y end_time sean nullable
ALTER TABLE game_sessions
    ALTER COLUMN start_time DROP NOT NULL,
    ALTER COLUMN end_time   DROP NOT NULL;

-- Recrear vistas
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
-- metadata debe mostrar: jsonb | YES