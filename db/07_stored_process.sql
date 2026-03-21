CREATE OR REPLACE PROCEDURE sp_registrar_checkin(
    p_user_id INTEGER,
    p_sleep_start VARCHAR(100),
    p_sleep_end VARCHAR(100),
    p_hours_sleep FLOAT,
    p_mood_id INTEGER,
    p_fatigue INTEGER,
    p_sleep_debt FLOAT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_checkin_id INTEGER;
    v_semaphore_color VARCHAR(100);
    v_semaphore_id INTEGER;
    v_mensaje VARCHAR(500);
    v_racha_actual INTEGER;
    v_racha_id INTEGER;
    v_hoy DATE := CURRENT_DATE;
    v_ayer DATE := CURRENT_DATE - INTERVAL '1 day';
    v_ya_existe BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM daily_checkin
        WHERE id_user = p_user_id
          AND date_time::DATE = v_hoy
    ) INTO v_ya_existe;

    IF v_ya_existe THEN
        RAISE EXCEPTION 'El usuario % ya registró su check-in hoy.', p_user_id;
    END IF;

    BEGIN

        INSERT INTO daily_checkin (
            id_user, sleep_start, sleep_end, hours_sleep,
            id_mood, fatigue, sleep_debt
        )
        VALUES (
            p_user_id, p_sleep_start, p_sleep_end, p_hours_sleep,
            p_mood_id, p_fatigue, p_sleep_debt
        )
        RETURNING id, id_semaphore INTO v_checkin_id, v_semaphore_id;

        SELECT color INTO v_semaphore_color
        FROM semaphore WHERE id = v_semaphore_id;

        v_mensaje := CASE v_semaphore_color
            WHEN 'Verde' THEN 'Tu energía está en niveles óptimos. ¡Es un buen momento para enfrentar tareas cognitivamente demandantes!'
            WHEN 'Amarillo' THEN 'Tienes fatiga moderada acumulada. Alterna períodos de estudio de 25 min con descansos de 5 min (Pomodoro).'
            WHEN 'Rojo' THEN 'Tu nivel de agotamiento es alto. Prioriza descanso antes de intentar tareas complejas. Tu cerebro lo necesita.'
            ELSE 'Completa tu check-in para recibir una recomendación personalizada.'
        END;

        INSERT INTO message (id_daily_checkin, message)
        VALUES (v_checkin_id, v_mensaje);

        SELECT id, days_count INTO v_racha_id, v_racha_actual
        FROM streaks_history
        WHERE user_id = p_user_id
          AND end_date IS NULL
        ORDER BY start_date DESC
        LIMIT 1;

        IF v_racha_id IS NOT NULL THEN
            UPDATE streaks_history
            SET days_count = days_count + 1,
                end_date = v_hoy
            WHERE id = v_racha_id;
            v_racha_actual := v_racha_actual + 1;
        ELSE
            INSERT INTO streaks_history (user_id, start_date, end_date, days_count)
            VALUES (p_user_id, v_hoy, v_hoy, 1)
            RETURNING days_count INTO v_racha_actual;
        END IF;

        IF v_racha_actual % 10 = 0 THEN
            INSERT INTO message (id_daily_checkin, message)
            VALUES (v_checkin_id,
                    FORMAT('¡Llevas %s días consecutivos! Es momento de responder la encuesta de seguimiento.', v_racha_actual));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE;
    END;

END;
$$;

CREATE OR REPLACE PROCEDURE sp_registrar_sesion_juego(
    p_checkin_id INTEGER,
    p_game_id INTEGER,
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    p_reaction_ms FLOAT,
    p_memory_pct FLOAT,
    p_metadata JSONB DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_session_id INTEGER;
    v_bateria_nueva INTEGER;
    v_bateria_promedio FLOAT;
    v_user_id INTEGER;
    v_score FLOAT;
BEGIN
    BEGIN 

        v_bateria_nueva := fn_calcular_bateria(p_reaction_ms, p_memory_pct);

        v_score := CASE p_game_id
            WHEN 1 THEN p_reaction_ms
            WHEN 2 THEN p_memory_pct
            ELSE NULL
        END;

        INSERT INTO game_sessions (
            id_daily_checkin, id_game,
            start_time, end_time,
            score_value, battery,
            metadata
        )
        VALUES (
            p_checkin_id, p_game_id,
            p_start_time, p_end_time,
            v_score, v_bateria_nueva,
            COALESCE(p_metadata, '{}'::JSONB) ||
                jsonb_build_object(
                    'avg_reaction_ms', p_reaction_ms,
                    'memory_pct', p_memory_pct
                )
        )
        RETURNING id INTO v_session_id;

        SELECT AVG(battery) INTO v_bateria_promedio
        FROM game_sessions
        WHERE id_daily_checkin = p_checkin_id
          AND battery IS NOT NULL;

        UPDATE daily_checkin
        SET battery_cog = ROUND(v_bateria_promedio)::INTEGER
        WHERE id = p_checkin_id;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Error al registrar sesión de juego: %', SQLERRM;
    END;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_consolidar_estadisticas_mensuales()
LANGUAGE plpgsql AS $$
DECLARE
    cur_usuarios CURSOR FOR
        SELECT DISTINCT u.id AS user_id,
               CONCAT(u.name, ' ', u.last_name) AS nombre
        FROM users u
        JOIN daily_checkin dc ON u.id = dc.id_user
        WHERE dc.date_time >= DATE_TRUNC('month', CURRENT_DATE)
        ORDER BY u.id;

    v_user_id INTEGER;
    v_nombre VARCHAR(200);
    v_dias_rojo INTEGER;
    v_total_dias INTEGER;
    v_avg_bateria FLOAT;
    v_avg_sueno FLOAT;
    v_checkin_hoy INTEGER;
    v_pct_rojo FLOAT;
BEGIN
    OPEN cur_usuarios;
    LOOP
        FETCH cur_usuarios INTO v_user_id, v_nombre;
        EXIT WHEN NOT FOUND;

        SELECT
            COUNT(*) AS total,
            COUNT(CASE WHEN s.color = 'Rojo' THEN 1 END) AS dias_rojos,
            AVG(dc.battery_cog) AS avg_bat,
            AVG(dc.hours_sleep) AS avg_sleep
        INTO v_total_dias, v_dias_rojo, v_avg_bateria, v_avg_sueno
        FROM daily_checkin dc
        LEFT JOIN semaphore s ON dc.id_semaphore = s.id
        WHERE dc.id_user = v_user_id
          AND dc.date_time >= DATE_TRUNC('month', CURRENT_DATE);

        v_pct_rojo := CASE WHEN v_total_dias > 0 THEN (v_dias_rojo::FLOAT / v_total_dias) * 100 ELSE 0 END;

        IF v_pct_rojo >= 50 THEN
            SELECT id INTO v_checkin_hoy
            FROM daily_checkin
            WHERE id_user = v_user_id
            ORDER BY date_time DESC
            LIMIT 1;

            IF v_checkin_hoy IS NOT NULL THEN
                INSERT INTO message (id_daily_checkin, message)
                VALUES (
                    v_checkin_hoy,
                    FORMAT(
                        'Alerta mensual: el %.0f%% de tus días este mes estuvieron en Semáforo Rojo. '
                        'Tu promedio de sueño fue %.1f h y batería cognitiva %.0f/100. '
                        'Considera ajustar tu rutina de descanso.',
                        v_pct_rojo, COALESCE(v_avg_sueno, 0), COALESCE(v_avg_bateria, 0)
                    )
                );
            END IF;
        END IF;

    END LOOP;
    CLOSE cur_usuarios;

END;
$$;