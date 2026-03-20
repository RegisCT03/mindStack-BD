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
WITH checkins_ultimos10 AS (
    SELECT
        sr.id_user,
        sr.streak_milestone,
        sr.answers,
        AVG(dc.battery_cog) AS avg_bateria_real,
        AVG(dc.fatigue) AS avg_fatiga_real,
        COUNT(CASE WHEN s.color = 'Verde'    THEN 1 END) AS dias_verde,
        COUNT(CASE WHEN s.color = 'Amarillo' THEN 1 END) AS dias_amarillo,
        COUNT(CASE WHEN s.color = 'Rojo'     THEN 1 END) AS dias_rojo,
        COUNT(dc.id) AS total_checkins_periodo
    FROM survey_response sr
    JOIN daily_checkin dc
      ON dc.id_user = sr.id_user
     AND dc.date_time >= (sr.answered_at - INTERVAL '10 days')
     AND dc.date_time <= sr.answered_at
    LEFT JOIN semaphore s ON dc.id_semaphore = s.id
    GROUP BY sr.id_user, sr.streak_milestone, sr.answers
)
SELECT
    c.id_user AS user_id,
    CONCAT(u.name, ' ', u.last_name) AS nombre_usuario,
    c.streak_milestone AS hito_dias,
    ROUND(c.avg_bateria_real::NUMERIC, 2) AS bateria_promedio_10d,
    ROUND(c.avg_fatiga_real::NUMERIC, 2) AS fatiga_promedio_10d,
    c.dias_verde,
    c.dias_amarillo,
    c.dias_rojo,
    c.total_checkins_periodo,
    (c.answers->>'q1')::INTEGER  AS semaforo_coincide_cansancio,
    (c.answers->>'q2')::INTEGER AS modifico_actividades,
    (c.answers->>'q3')::INTEGER AS precision_minijuegos,
    (c.answers->>'q4')::INTEGER AS intento_dormir_mas,
    (c.answers->>'q5')::INTEGER AS ayudo_evitar_burnout,

    ROUND(
        ((c.answers->>'q1')::NUMERIC +
         (c.answers->>'q2')::NUMERIC +
         (c.answers->>'q3')::NUMERIC +
         (c.answers->>'q4')::NUMERIC +
         (c.answers->>'q5')::NUMERIC) / 5.0
    , 2) AS satisfaccion_promedio,

    CASE
        WHEN ROUND(((c.answers->>'q1')::NUMERIC + (c.answers->>'q2')::NUMERIC +
                    (c.answers->>'q3')::NUMERIC + (c.answers->>'q4')::NUMERIC +
                    (c.answers->>'q5')::NUMERIC) / 5.0, 2) >= 3.5
             AND c.avg_fatiga_real <= 60
        THEN 'Hipótesis VALIDADA'
        WHEN ROUND(((c.answers->>'q1')::NUMERIC + (c.answers->>'q2')::NUMERIC +
                    (c.answers->>'q3')::NUMERIC + (c.answers->>'q4')::NUMERIC +
                    (c.answers->>'q5')::NUMERIC) / 5.0, 2) >= 3.5
        THEN 'Satisfacción alta, fatiga sin reducción significativa'
        ELSE 'Hipótesis NO validada en este hito'
    END AS resultado_hipotesis

FROM checkins_ultimos10 c
JOIN users u ON c.id_user = u.id;