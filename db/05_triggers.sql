CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_streaks_updated_at
BEFORE UPDATE ON streaks_history
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_checkin_updated_at
BEFORE UPDATE ON daily_checkin
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_game_sessions_updated_at
BEFORE UPDATE ON game_sessions
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_message_updated_at
BEFORE UPDATE ON message
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_survey_updated_at
BEFORE UPDATE ON survey_response
 FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE OR REPLACE FUNCTION fn_calculate_semaphore()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_ideal_sleep     FLOAT;
    v_sleep_ratio     FLOAT;
    v_semaphore_id    INTEGER;
BEGIN
    IF NEW.hours_sleep IS NULL OR NEW.id_mood IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT ideal_sleep_hours INTO v_ideal_sleep
    FROM users
    WHERE id = NEW.id_user;

    v_sleep_ratio := NEW.hours_sleep / NULLIF(v_ideal_sleep, 0);

    IF v_sleep_ratio >= 0.9 AND NEW.id_mood >= 4 THEN
        SELECT id INTO v_semaphore_id FROM semaphore WHERE color = 'Verde';

    ELSIF v_sleep_ratio < 0.6 OR NEW.id_mood <= 2 THEN
        SELECT id INTO v_semaphore_id FROM semaphore WHERE color = 'Rojo';

    ELSE
        SELECT id INTO v_semaphore_id FROM semaphore WHERE color = 'Amarillo';
    END IF;

    IF NEW.sleep_debt IS NULL THEN
        NEW.sleep_debt := GREATEST(0, v_ideal_sleep - NEW.hours_sleep);
    END IF;

    NEW.id_semaphore := v_semaphore_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_calculate_semaphore
BEFORE INSERT OR UPDATE OF hours_sleep, id_mood ON daily_checkin
FOR EACH ROW EXECUTE FUNCTION fn_calculate_semaphore();