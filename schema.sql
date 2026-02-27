CREATE TABLE rol (
    id SERIAL PRIMARY KEY,
    rol VARCHAR(100) NOT NULL
);

CREATE TABLE mood (
    id SERIAL PRIMARY KEY,
    mood VARCHAR(100) NOT NULL
);

CREATE TABLE semaforo (
    id SERIAL PRIMARY KEY,
    color VARCHAR(100) NOT NULL,
    description VARCHAR(100)
);

CREATE TABLE juego (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE streaks_history (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    start_date DATE NOT NULL,
    end_date DATE,
    days_count INT DEFAULT 0
);

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(100),
    id_rol INTEGER REFERENCES rol(id),
    ideal_sleep_hours FLOAT DEFAULT 8.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE streaks_history ADD CONSTRAINT fk_user_streaks 
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

CREATE TABLE daily_checkin (
    id SERIAL PRIMARY KEY,
    id_user INTEGER REFERENCES users(id) ON DELETE CASCADE,
    sleep_start TIME,
    sleep_end TIME,
    hours_sleep FLOAT,
    id_mood INTEGER REFERENCES mood(id),
    id_status INTEGER REFERENCES semaforo(id),
    date_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sleep_debt FLOAT,
    battery_cog INTEGER CHECK (battery_cog BETWEEN 0 AND 100),
    fatiga INTEGER CHECK (fatiga BETWEEN 0 AND 100)
);

CREATE TABLE game_sessions (
    id SERIAL PRIMARY KEY,
    id_daily_checkin INTEGER REFERENCES daily_checkin(id) ON DELETE CASCADE,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    id_juego INTEGER REFERENCES juego(id),
    score_value FLOAT,
    battery INTEGER,
    metadata JSONB
);

CREATE TABLE message (
    id SERIAL PRIMARY KEY,
    id_daily_checkin INTEGER REFERENCES daily_checkin(id) ON DELETE CASCADE,
    message VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);