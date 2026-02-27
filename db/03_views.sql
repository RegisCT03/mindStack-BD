-- semaforo de riesgo y batería actual
CREATE OR REPLACE VIEW view_user_status AS
SELECT 
    u.id AS user_id,
    u.name,
    dc.date_time::DATE AS fecha,
    s.color AS riesgo_color,
    m.mood AS estado_animo,
    dc.hours_sleep,
    dc.sleep_debt,
    dc.battery_cog AS bateria_actual
FROM users u
JOIN daily_checkin dc ON u.id = dc.id_user
JOIN semaforo s ON dc.id_status = s.id
JOIN mood m ON dc.id_mood = m.id
WHERE dc.date_time >= CURRENT_DATE - INTERVAL '7 days';

-- rendimiento por juego
CREATE OR REPLACE VIEW view_game_performance AS
SELECT 
    j.name AS juego,
    AVG(gs.score_value) AS promedio_puntuacion,
    AVG(gs.battery) AS impacto_bateria_promedio,
    COUNT(gs.id) AS veces_jugado
FROM juego j
JOIN game_sessions gs ON j.id = gs.id_juego
GROUP BY j.name;