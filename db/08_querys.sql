SELECT
    u.id AS user_id,
    CONCAT(u.name, ' ', u.last_name) AS nombre,
    COUNT(dc.id) AS total_checkins,
    COUNT(CASE WHEN s.color = 'Verde'    THEN 1 END) AS dias_verde,
    COUNT(CASE WHEN s.color = 'Amarillo' THEN 1 END) AS dias_amarillo,
    COUNT(CASE WHEN s.color = 'Rojo'     THEN 1 END) AS dias_rojo,
    ROUND(AVG(dc.fatigue)::NUMERIC, 2) AS fatiga_promedio,
    ROUND(AVG(dc.battery_cog)::NUMERIC, 2) AS bateria_promedio,
    ROUND(
        (COUNT(CASE WHEN s.color = 'Rojo' THEN 1 END)::NUMERIC
         / NULLIF(COUNT(dc.id), 0)) * 100
    , 1) AS pct_dias_rojo
FROM users u
JOIN daily_checkin dc ON u.id = dc.id_user
LEFT JOIN semaphore s ON dc.id_semaphore = s.id
GROUP BY u.id, u.name, u.last_name
HAVING COUNT(dc.id) >= 5
ORDER BY pct_dias_rojo DESC;

SELECT
    s.color AS semaforo,
    COUNT(DISTINCT dc.id_user) AS usuarios_distintos,
    COUNT(gs.id) AS total_sesiones_juego,
    ROUND(AVG(gs.battery)::NUMERIC, 2) AS bateria_promedio,
    MIN(gs.battery) AS bateria_minima,
    MAX(gs.battery) AS bateria_maxima,
    ROUND(AVG(dc.sleep_debt)::NUMERIC, 2) AS deuda_sueno_promedio,
    ROUND(AVG(gs.battery)::NUMERIC, 2) -
        (SELECT ROUND(AVG(battery)::NUMERIC, 2)
         FROM game_sessions
         WHERE battery IS NOT NULL) AS diferencia_vs_promedio_global
FROM daily_checkin dc
JOIN semaphore s ON dc.id_semaphore = s.id
JOIN game_sessions gs ON gs.id_daily_checkin = dc.id
WHERE gs.battery IS NOT NULL
GROUP BY s.color
ORDER BY
    CASE s.color
        WHEN 'Verde' THEN 1
        WHEN 'Amarillo' THEN 2
        WHEN 'Rojo' THEN 3
    END;

WITH respuestas_normalizadas AS (
    SELECT
        sr.id_user,
        sr.streak_milestone,
        (sr.answers->>'q1')::INTEGER AS semaforo_coincide,
        (sr.answers->>'q2')::INTEGER AS modifico_actividades,
        (sr.answers->>'q3')::INTEGER AS precision_minijuegos,
        (sr.answers->>'q4')::INTEGER AS intento_dormir_mas,
        (sr.answers->>'q5')::INTEGER AS evito_burnout,
        sr.avg_battery_last10,
        sr.avg_sleep_last10
    FROM survey_response sr
    WHERE sr.answers IS NOT NULL
),
satisfaccion_por_hito AS (
    SELECT
        streak_milestone,
        COUNT(*) AS respuestas,
        ROUND(AVG(semaforo_coincide)::NUMERIC, 2) AS avg_q1_semaforo,
        ROUND(AVG(modifico_actividades)::NUMERIC, 2) AS avg_q2_cambio_habitos,
        ROUND(AVG(precision_minijuegos)::NUMERIC, 2) AS avg_q3_precision,
        ROUND(AVG(intento_dormir_mas)::NUMERIC, 2) AS avg_q4_mejora_sueno,
        ROUND(AVG(evito_burnout)::NUMERIC, 2) AS avg_q5_burnout,
        ROUND(AVG(
            (semaforo_coincide + modifico_actividades +
             precision_minijuegos + intento_dormir_mas + evito_burnout) / 5.0
        )::NUMERIC, 2) AS satisfaccion_global,
        ROUND(AVG(avg_battery_last10)::NUMERIC, 2) AS bateria_promedio_periodo,
        ROUND(AVG(avg_sleep_last10)::NUMERIC, 2) AS sueno_promedio_periodo
    FROM respuestas_normalizadas
    GROUP BY streak_milestone
    HAVING COUNT(*) >= 3
)
SELECT
    streak_milestone AS hito_dias,
    respuestas,
    satisfaccion_global,
    avg_q5_burnout AS satisfaccion_burnout,
    bateria_promedio_periodo,
    sueno_promedio_periodo,
    CASE
        WHEN satisfaccion_global >= 3.5 THEN 'Satisfacción Alta ✓'
        WHEN satisfaccion_global >= 2.5 THEN 'Satisfacción Moderada'
        ELSE 'Satisfacción Baja ✗'
    END AS clasificacion
FROM satisfaccion_por_hito
ORDER BY streak_milestone;

SELECT
    CASE
        WHEN (sr.answers->>'q2')::INTEGER >= 4 THEN 'Sigue recomendaciones'
        WHEN (sr.answers->>'q2')::INTEGER <= 2 THEN 'No sigue recomendaciones'
        ELSE 'Respuesta neutral'
    END AS grupo,
    COUNT(DISTINCT sr.id_user) AS usuarios,
    ROUND(AVG(
        (SELECT AVG(dc2.fatigue)
         FROM daily_checkin dc2
         WHERE dc2.id_user = sr.id_user
           AND dc2.date_time >= (sr.answered_at - INTERVAL '10 days')
           AND dc2.date_time <= sr.answered_at)
    )::NUMERIC, 2) AS fatiga_promedio_periodo,
    ROUND(AVG(sr.avg_battery_last10)::NUMERIC, 2) AS bateria_promedio,
    ROUND(AVG(sr.avg_sleep_last10)::NUMERIC, 2) AS sueno_promedio,
    ROUND(
        COUNT(CASE WHEN (sr.answers->>'q5')::INTEGER >= 4 THEN 1 END)::NUMERIC
        / NULLIF(COUNT(*), 0) * 100
    , 1) AS pct_evito_burnout
FROM survey_response sr
WHERE sr.answers ? 'q2'
GROUP BY
    CASE
        WHEN (sr.answers->>'q2')::INTEGER >= 4 THEN 'Sigue recomendaciones'
        WHEN (sr.answers->>'q2')::INTEGER <= 2 THEN 'No sigue recomendaciones'
        ELSE 'Respuesta neutral'
    END
ORDER BY fatiga_promedio_periodo ASC NULLS LAST;

WITH fatiga_inicial AS (
    SELECT
        sr.id_user,
        AVG(dc.fatigue)  AS fatiga_pre_app
    FROM survey_response sr
    JOIN daily_checkin dc
      ON dc.id_user = sr.id_user
     AND dc.date_time < (sr.answered_at - INTERVAL '10 days')
    WHERE sr.streak_milestone = 10
    GROUP BY sr.id_user
),
fatiga_reciente AS (
    SELECT
        sr.id_user,
        AVG(dc.fatigue)  AS fatiga_post_app
    FROM survey_response sr
    JOIN daily_checkin dc
      ON dc.id_user = sr.id_user
     AND dc.date_time >= (sr.answered_at - INTERVAL '10 days')
    WHERE sr.streak_milestone = (
        SELECT MAX(streak_milestone)
        FROM survey_response sr2
        WHERE sr2.id_user = sr.id_user
    )
    GROUP BY sr.id_user
),
satisfaccion_final AS (
    SELECT
        id_user,
        ROUND((
            (answers->>'q1')::NUMERIC +
            (answers->>'q2')::NUMERIC +
            (answers->>'q3')::NUMERIC +
            (answers->>'q4')::NUMERIC +
            (answers->>'q5')::NUMERIC
        ) / 5.0, 2) AS satisfaccion
    FROM survey_response
    WHERE streak_milestone = (
        SELECT MAX(streak_milestone)
        FROM survey_response sr3
        WHERE sr3.id_user = survey_response.id_user
    )
)
SELECT
    COUNT(*) AS total_usuarios_evaluados,
    COUNT(CASE
        WHEN sf.satisfaccion >= 3.5
         AND COALESCE(fr.fatiga_post_app, 100) < COALESCE(fi.fatiga_pre_app, 100)
        THEN 1 END) AS usuarios_hipotesis_validada,
    COUNT(CASE
        WHEN sf.satisfaccion < 3.5
          OR COALESCE(fr.fatiga_post_app, 100) >= COALESCE(fi.fatiga_pre_app, 100)
        THEN 1 END) AS usuarios_hipotesis_no_validada,
    ROUND(
        COUNT(CASE
            WHEN sf.satisfaccion >= 3.5
             AND COALESCE(fr.fatiga_post_app, 100) < COALESCE(fi.fatiga_pre_app, 100)
            THEN 1 END)::NUMERIC
        / NULLIF(COUNT(*), 0) * 100
    , 1) AS pct_validacion,
    ROUND(AVG(sf.satisfaccion)::NUMERIC, 2) AS satisfaccion_promedio_global,
    ROUND(AVG(fi.fatiga_pre_app)::NUMERIC, 2) AS fatiga_promedio_pre_app,
    ROUND(AVG(fr.fatiga_post_app)::NUMERIC, 2) AS fatiga_promedio_post_app,
    ROUND((AVG(fi.fatiga_pre_app) - AVG(fr.fatiga_post_app))::NUMERIC, 2) AS reduccion_fatiga_promedio,
    CASE
        WHEN ROUND(
            COUNT(CASE
                WHEN sf.satisfaccion >= 3.5
                 AND COALESCE(fr.fatiga_post_app, 100) < COALESCE(fi.fatiga_pre_app, 100)
                THEN 1 END)::NUMERIC
            / NULLIF(COUNT(*), 0) * 100
        , 1) >= 50
        THEN ' HIPÓTESIS VALIDADA: Más del 50% de usuarios reportan mayor satisfacción y menor fatiga.'
        ELSE ' HIPÓTESIS NO VALIDADA: Menos del 50% de usuarios reportan los efectos esperados.'
    END AS veredicto_hipotesis
FROM satisfaccion_final sf
LEFT JOIN fatiga_inicial  fi ON sf.id_user = fi.id_user
LEFT JOIN fatiga_reciente fr ON sf.id_user = fr.id_user;