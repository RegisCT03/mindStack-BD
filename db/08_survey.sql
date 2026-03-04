-- =============================================================================
-- MIGRACIÓN 08: Tabla de encuestas por hito de racha
-- Se dispara automáticamente cada 10 días consecutivos (10, 20, 30, 40...)
-- Las respuestas se guardan en JSONB para flexibilidad total de preguntas
-- =============================================================================

BEGIN;

CREATE TABLE survey_response (
    id                  SERIAL PRIMARY KEY,
    id_user             INTEGER REFERENCES users(id) ON DELETE CASCADE,
    streak_milestone    INTEGER NOT NULL,       -- 10, 20, 30, 40...
    answers             JSONB NOT NULL,         -- respuestas del usuario
    avg_sleep_last10    FLOAT,                  -- calculado por el backend al guardar
    avg_battery_last10  FLOAT,                  -- calculado por el backend al guardar
    answered_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Un usuario solo puede responder UNA VEZ por hito
    CONSTRAINT uq_user_milestone UNIQUE (id_user, streak_milestone)
);

-- Búsqueda por usuario (historial de encuestas)
CREATE INDEX idx_survey_user      ON survey_response(id_user);

-- Búsqueda por hito (análisis de todos los usuarios en día 10, 20, etc.)
CREATE INDEX idx_survey_milestone ON survey_response(streak_milestone);

-- Búsqueda dentro del JSON (queries de análisis de hipótesis)
CREATE INDEX idx_survey_answers   ON survey_response USING GIN(answers);

COMMIT;

-- =============================================================================
-- ESTRUCTURA ESPERADA DEL CAMPO answers (el front manda este JSON):
-- =============================================================================
/*
{
  "q1_sleep_quality":    4,     -- 1-5: ¿Cómo calificarías tu calidad de sueño?
  "q2_mood_improvement": 5,     -- 1-5: ¿Notas mejoría en tu estado de ánimo?
  "q3_energy_level":     3,     -- 1-5: ¿Cómo está tu nivel de energía diaria?
  "q4_habit_feels":      4,     -- 1-5: ¿Qué tan fácil se siente el hábito ahora?
  "q5_open_text": "Me siento más descansado que antes de empezar"
}
*/

-- =============================================================================
-- QUERIES DE ANÁLISIS PARA VALIDAR LA HIPÓTESIS
-- (ejecutar directamente en Postgres)
-- =============================================================================
/*

-- 1. Promedio de cada métrica por hito (evolución general)
SELECT
    streak_milestone,
    COUNT(*)                                        AS total_respuestas,
    ROUND(AVG((answers->>'q1_sleep_quality')::int)::numeric,    2) AS avg_calidad_sueno,
    ROUND(AVG((answers->>'q2_mood_improvement')::int)::numeric, 2) AS avg_mejoria_animo,
    ROUND(AVG((answers->>'q3_energy_level')::int)::numeric,     2) AS avg_energia,
    ROUND(AVG((answers->>'q4_habit_feels')::int)::numeric,      2) AS avg_facilidad_habito,
    ROUND(AVG(avg_sleep_last10)::numeric,  2)       AS avg_horas_reales,
    ROUND(AVG(avg_battery_last10)::numeric,2)       AS avg_bateria_real
FROM survey_response
GROUP BY streak_milestone
ORDER BY streak_milestone;

-- 2. Usuarios que mejoraron energía del día 10 al día 20 (hipótesis central)
SELECT
    s10.id_user,
    (s10.answers->>'q3_energy_level')::int  AS energia_dia10,
    (s20.answers->>'q3_energy_level')::int  AS energia_dia20,
    s10.avg_sleep_last10                    AS sueno_avg_dia10,
    s20.avg_sleep_last10                    AS sueno_avg_dia20
FROM survey_response s10
JOIN survey_response s20
  ON s10.id_user = s20.id_user
WHERE s10.streak_milestone = 10
  AND s20.streak_milestone = 20
ORDER BY
    ((s20.answers->>'q3_energy_level')::int - (s10.answers->>'q3_energy_level')::int) DESC;

-- 3. Correlación sueño real vs percepción de mejora
SELECT
    streak_milestone,
    ROUND(CORR(avg_sleep_last10, (answers->>'q2_mood_improvement')::int)::numeric, 3)
        AS corr_sueno_animo
FROM survey_response
GROUP BY streak_milestone;

*/
