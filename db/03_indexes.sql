CREATE INDEX idx_checkin_user_date ON daily_checkin(id_user, date_time);

CREATE INDEX idx_streaks_user ON streaks_history(user_id);

CREATE INDEX idx_game_sessions_checkin ON game_sessions(id_daily_checkin);

CREATE INDEX idx_game_metadata ON game_sessions USING GIN (metadata);

CREATE INDEX idx_users_email ON users(email);