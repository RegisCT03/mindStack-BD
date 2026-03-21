CREATE OR REPLACE FUNCTION fn_calcular_bateria(
p_reaction_ms   FLOAT,
p_memory_pct    FLOAT
)
RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_score_reaccion  FLOAT;
    v_score_memoria   FLOAT;
    v_bateria         FLOAT;
BEGIN
    v_score_reaccion := GREATEST(0, LEAST(100,
        ((600.0 - COALESCE(p_reaction_ms, 600)) / 450.0) * 100
    ));

    v_score_memoria := GREATEST(0, LEAST(100, COALESCE(p_memory_pct, 0)));

    v_bateria := (v_score_reaccion * 0.5) + (v_score_memoria * 0.5);

    RETURN ROUND(v_bateria)::INTEGER;
END;
$$;

CREATE OR REPLACE FUNCTION fn_rendimiento_usuario(
    p_user_id  INTEGER,
    p_desde DATE DEFAULT (CURRENT_DATE - INTERVAL '30 days'),
    p_hasta DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
fecha DATE,
nombre_juego VARCHAR(100),
bateria_calculada INTEGER,
semaforo_color VARCHAR(100),
horas_dormidas FLOAT,
deuda_sueno FLOAT,
score_raw FLOAT
)

LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        dc.date_time::DATE AS fecha,
        g.name AS nombre_juego,
        fn_calcular_bateria(
           (gs.metadata->>'avg_reaction_ms')::FLOAT,
            (gs.metadata->>'memory_pct')::FLOAT
        ) AS bateria_calculada,
        s.color AS semaforo_color,
        dc.hours_sleep AS horas_dormidas,
        dc.sleep_debt AS deuda_sueno,
        gs.score_value AS score_raw

    FROM game_sessions gs
    JOIN daily_checkin dc ON gs.id_daily_checkin = dc.id
    JOIN game g ON gs.id_game = g.id
    LEFT JOIN semaphore s  ON dc.id_semaphore = s.id
    WHERE dc.id_user = p_user_id
      AND dc.date_time::DATE BETWEEN p_desde AND p_hasta
    ORDER BY dc.date_time ASC;
END;
$$;