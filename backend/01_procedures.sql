-- =============================================
-- 01_procedures.sql
-- sp_agendar_cita y fn_total_facturado
-- =============================================

CREATE OR REPLACE PROCEDURE sp_agendar_cita(
    p_mascota_id      INT,
    p_veterinario_id  INT,
    p_fecha_hora      TIMESTAMP,
    p_motivo          TEXT,
    OUT p_cita_id     INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_activo        BOOLEAN;
    v_dias_descanso VARCHAR(50);
    v_dia_semana    TEXT;
BEGIN
    -- 1. Validar que la mascota existe
    IF NOT EXISTS (SELECT 1 FROM mascotas WHERE id = p_mascota_id) THEN
        RAISE EXCEPTION 'La mascota con id=% no existe.', p_mascota_id;
    END IF;

    -- 2. Validar veterinario
    SELECT activo, dias_descanso
    INTO   v_activo, v_dias_descanso
    FROM   veterinarios
    WHERE  id = p_veterinario_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El veterinario con id=% no existe.', p_veterinario_id;
    END IF;

    IF v_activo IS NOT TRUE THEN
        RAISE EXCEPTION 'El veterinario con id=% está inactivo.', p_veterinario_id;
    END IF;

    -- 3. Validar día de descanso
    --    EXTRACT(DOW) devuelve 0=domingo, 1=lunes... en cualquier idioma
    v_dia_semana := CASE EXTRACT(DOW FROM p_fecha_hora)
        WHEN 0 THEN 'domingo'
        WHEN 1 THEN 'lunes'
        WHEN 2 THEN 'martes'
        WHEN 3 THEN 'miércoles'
        WHEN 4 THEN 'jueves'
        WHEN 5 THEN 'viernes'
        WHEN 6 THEN 'sábado'
    END;

    IF v_dias_descanso <> '' AND
       v_dia_semana = ANY(STRING_TO_ARRAY(v_dias_descanso, ','))
    THEN
        RAISE EXCEPTION 'El veterinario descansa los %. Elige otro día.', v_dia_semana;
    END IF;

    -- 4. Validar colisión de horario
    PERFORM 1
    FROM citas
    WHERE veterinario_id = p_veterinario_id
      AND fecha_hora     = p_fecha_hora
      AND estado        <> 'CANCELADA'
    FOR UPDATE;

    IF FOUND THEN
        RAISE EXCEPTION 'El veterinario ya tiene una cita a las %.', p_fecha_hora;
    END IF;

    -- 5. Insertar cita
    INSERT INTO citas (mascota_id, veterinario_id, fecha_hora, motivo, estado)
    VALUES (p_mascota_id, p_veterinario_id, p_fecha_hora, p_motivo, 'AGENDADA')
    RETURNING id INTO p_cita_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- =============================================
-- fn_total_facturado
-- =============================================
CREATE OR REPLACE FUNCTION fn_total_facturado(
    p_mascota_id  INT,
    p_anio        INT
) RETURNS NUMERIC AS $$
DECLARE
    v_total_citas   NUMERIC;
    v_total_vacunas NUMERIC;
BEGIN
    SELECT COALESCE(SUM(costo), 0)
    INTO   v_total_citas
    FROM   citas
    WHERE  mascota_id = p_mascota_id
      AND  estado     = 'COMPLETADA'
      AND  EXTRACT(YEAR FROM fecha_hora) = p_anio;

    SELECT COALESCE(SUM(costo_cobrado), 0)
    INTO   v_total_vacunas
    FROM   vacunas_aplicadas
    WHERE  mascota_id = p_mascota_id
      AND  EXTRACT(YEAR FROM fecha_aplicacion) = p_anio;

    RETURN v_total_citas + v_total_vacunas;
END;
$$ LANGUAGE plpgsql;