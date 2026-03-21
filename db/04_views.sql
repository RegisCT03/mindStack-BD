CREATE OR REPLACE VIEW vw_dashboard AS
SELECT
    dc.id_user AS user_id,
    dc.date_time::DATE AS fecha,
    COALESCE(sh.days_count, 0) AS dias_racha,
    s.color AS semaforo_riesgo,
    dc.battery_cog AS bateria_cognitiva,
    dc.sleep_debt AS deuda_sueno,
    dc.hours_sleep AS horas_dormidas
FROM daily_checkin dc
LEFT JOIN semaphore s
       ON dc.id_semaphore = s.id
LEFT JOIN streaks_history sh
       ON dc.id_user = sh.user_id
      AND dc.date_time::DATE BETWEEN sh.start_date AND COALESCE(sh.end_date, CURRENT_DATE);

CREATE OR REPLACE VIEW vw_history AS
SELECT
    dc.id AS checkin_id,
    dc.id_user AS user_id,
    CONCAT(u.name, ' ', u.last_name) AS nombre_usuario,
    dc.date_time AS fecha_hora_completa,
    dc.date_time::DATE AS fecha,
    dc.battery_cog AS nivel_bateria,
    s.color AS semaforo_color,
    m.mood AS estado_animo,
    dc.hours_sleep AS horas_dormidas,
    dc.fatigue AS fatiga_general
FROM daily_checkin dc
LEFT JOIN semaphore s ON dc.id_semaphore = s.id
LEFT JOIN mood m ON dc.id_mood = m.id
LEFT JOIN users u ON dc.id_user = u.id;

CREATE OR REPLACE VIEW vw_user_profile AS
SELECT
    id AS user_id,
    email AS correo,
    name AS nombre,
    last_name AS apellido,
    CONCAT(name, ' ', last_name) AS nombre_completo,
    date_of_birth AS fecha_nacimiento
FROM users;

CREATE OR REPLACE VIEW vw_user_stats AS
SELECT
    u.id AS user_id,
    CONCAT(u.name, ' ', u.last_name) AS nombre_completo,
    COUNT(DISTINCT dc.id) AS total_checkins,
    ROUND(AVG(dc.hours_sleep)::NUMERIC, 2) AS promedio_horas_sueno,
    ROUND(AVG(dc.battery_cog)::NUMERIC, 2) AS promedio_bateria_cognitiva,
    ROUND(AVG(dc.fatigue)::NUMERIC, 2) AS promedio_fatiga,
    ROUND(AVG(dc.sleep_debt)::NUMERIC, 2) AS promedio_deuda_sueno,
    COUNT(CASE WHEN s.color = 'Verde'    THEN 1 END) AS dias_verde,
    COUNT(CASE WHEN s.color = 'Amarillo' THEN 1 END) AS dias_amarillo,
    COUNT(CASE WHEN s.color = 'Rojo'     THEN 1 END) AS dias_rojo,
    MAX(sh.days_count) AS racha_maxima,
    MIN(dc.date_time::DATE) AS primer_checkin,
    MAX(dc.date_time::DATE) AS ultimo_checkin
FROM users u
LEFT JOIN daily_checkin  dc ON u.id = dc.id_user
LEFT JOIN semaphore s ON dc.id_semaphore = s.id
LEFT JOIN streaks_history sh ON u.id = sh.user_id
GROUP BY u.id, u.name, u.last_name;

CREATE OR REPLACE VIEW vw_hipotesis_correlacion AS
WITH semana1 AS (
    SELECT
        dc.id_user,
        MIN(dc.date_time::DATE) AS fecha_inicio,
        AVG(dc.fatigue) AS fatiga_semana1,
        AVG(dc.battery_cog) AS bateria_semana1,
        COUNT(dc.id) AS checkins_semana1
    FROM daily_checkin dc
    WHERE dc.date_time::DATE <= (
        SELECT MIN(dc2.date_time::DATE) + INTERVAL '6 days'
        FROM daily_checkin dc2
        WHERE dc2.id_user = dc.id_user
    )
    GROUP BY dc.id_user
),
semana_reciente AS (
    SELECT
        dc.id_user,
        MAX(dc.date_time::DATE) AS fecha_ultimo,
        AVG(dc.fatigue) AS fatiga_reciente,
        AVG(dc.battery_cog) AS bateria_reciente,
        COUNT(dc.id) AS checkins_recientes
    FROM daily_checkin dc
    WHERE dc.date_time::DATE >= (
        SELECT MAX(dc2.date_time::DATE) - INTERVAL '6 days'
        FROM daily_checkin dc2
        WHERE dc2.id_user = dc.id_user
    )
    GROUP BY dc.id_user
),
cumplimiento_descanso AS (
    SELECT
        id_user,
        COUNT(*) AS total_encuestas,
        COUNT(CASE WHEN (answers->>'q2')::INTEGER >= 4 THEN 1 END) AS encuestas_con_cumplimiento,
        ROUND(
            COUNT(CASE WHEN (answers->>'q2')::INTEGER >= 4 THEN 1 END)::NUMERIC
            / NULLIF(COUNT(*), 0) * 100
        , 1) AS tasa_cumplimiento_pct
    FROM survey_response
    WHERE answers ? 'q2'
    GROUP BY id_user
)
SELECT
    u.id AS user_id,
    CONCAT(u.name, ' ', u.last_name) AS nombre_usuario,
    ROUND(s1.fatiga_semana1::NUMERIC, 2) AS fatiga_semana1,
    ROUND(sr.fatiga_reciente::NUMERIC, 2) AS fatiga_reciente,
    ROUND(
        ((s1.fatiga_semana1 - sr.fatiga_reciente)
         / NULLIF(s1.fatiga_semana1, 0)) * 100
    , 1) AS reduccion_fatiga_pct,

    ROUND(s1.bateria_semana1::NUMERIC, 2) AS bateria_semana1,
    ROUND(sr.bateria_reciente::NUMERIC, 2) AS bateria_reciente,

    COALESCE(cd.total_encuestas, 0) AS total_encuestas,
    COALESCE(cd.tasa_cumplimiento_pct, 0) AS tasa_cumplimiento_pct,

    CASE WHEN COALESCE(cd.tasa_cumplimiento_pct, 0) > 70
         THEN 'Sí' ELSE 'No'
    END AS cumple_A_cumplimiento,

    CASE WHEN sr.fatiga_reciente <= s1.fatiga_semana1 * 0.75
         THEN 'Sí' ELSE 'No'
    END AS cumple_B_reduccion_fatiga,

    CASE
        WHEN COALESCE(cd.tasa_cumplimiento_pct, 0) > 70
         AND sr.fatiga_reciente <= s1.fatiga_semana1 * 0.75
        THEN 'Hipótesis VALIDADA'
        WHEN COALESCE(cd.tasa_cumplimiento_pct, 0) > 70
        THEN 'Solo cumple condición A (cumplimiento)'
        WHEN sr.fatiga_reciente <= s1.fatiga_semana1 * 0.75
        THEN 'Solo cumple condición B (reducción de fatiga)'
        ELSE 'Hipótesis NO validada'
    END AS resultado_hipotesis

FROM users u
JOIN semana1 s1 ON u.id = s1.id_user
JOIN semana_reciente sr ON u.id = sr.id_user
LEFT JOIN cumplimiento_descanso cd ON u.id = cd.id_user
WHERE s1.fecha_inicio < sr.fecha_ultimo - INTERVAL '7 days';