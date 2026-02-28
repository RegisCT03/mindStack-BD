CREATE TABLE rol (
    id SERIAL PRIMARY KEY,
    rol VARCHAR(100) NOT NULL
);

CREATE TABLE mood (
    id SERIAL PRIMARY KEY,
    mood VARCHAR(100) NOT NULL
);

CREATE TABLE semaphore (
    id SERIAL PRIMARY KEY,
    color VARCHAR(100) NOT NULL,
    description VARCHAR(100)
);

CREATE TABLE game (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(100),
    id_rol INTEGER REFERENCES rol(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ideal_sleep_hours FLOAT DEFAULT 8.0
);

CREATE TABLE streaks_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE,
    days_count INT DEFAULT 1
);

CREATE TABLE daily_checkin (
    id SERIAL PRIMARY KEY,
    id_user INTEGER REFERENCES users(id) ON DELETE CASCADE,
    sleep_start VARCHAR(100),
    sleep_end VARCHAR(100),
    hours_sleep FLOAT,
    id_mood INTEGER REFERENCES mood(id),
    id_semaphore INTEGER REFERENCES semaphore(id),
    date_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sleep_debt FLOAT,
    battery_cog INTEGER CHECK (battery_cog BETWEEN 0 AND 100),
    fatigue INTEGER CHECK (fatigue BETWEEN 0 AND 100)
);

CREATE TABLE game_sessions (
    id SERIAL PRIMARY KEY,
    id_daily_checkin INTEGER REFERENCES daily_checkin(id) ON DELETE CASCADE,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    id_game INTEGER REFERENCES game(id),
    score_value FLOAT,
    battery INTEGER,
    metadata JSONB
);

CREATE TABLE message (
    id SERIAL PRIMARY KEY,
    id_daily_checkin INTEGER REFERENCES daily_checkin(id) ON DELETE CASCADE,
    id_game_session  INTEGER REFERENCES game_sessions(id) ON DELETE CASCADE,
    message VARCHAR(500) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);