-- =============================================
-- 02_triggers.sql
-- trg_historial_cita y trg_alerta_stock_bajo
-- =============================================

-- Función del trigger de historial
-- AFTER INSERT porque queremos registrar solo lo que
-- realmente ocurrió. Si usáramos BEFORE y el INSERT
-- fallara después, tendríamos un registro falso en historial.
CREATE OR REPLACE FUNCTION fn_historial_cita()
RETURNS TRIGGER AS $$
DECLARE
    v_nombre_mascota  VARCHAR(50);
    v_nombre_vet      VARCHAR(100);
BEGIN
    SELECT nombre INTO v_nombre_mascota FROM mascotas     WHERE id = NEW.mascota_id;
    SELECT nombre INTO v_nombre_vet     FROM veterinarios WHERE id = NEW.veterinario_id;

    INSERT INTO historial_movimientos (tipo, referencia_id, descripcion)
    VALUES (
        'CITA_AGENDADA',
        NEW.id,
        FORMAT('Cita para %s con %s el %s',
               v_nombre_mascota,
               v_nombre_vet,
               TO_CHAR(NEW.fecha_hora, 'DD/MM/YYYY HH24:MI'))
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_historial_cita ON citas;
CREATE TRIGGER trg_historial_cita
    AFTER INSERT ON citas
    FOR EACH ROW
    EXECUTE FUNCTION fn_historial_cita();


-- Trigger de alerta de stock bajo
CREATE OR REPLACE FUNCTION fn_alerta_stock_bajo()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.stock_actual <= NEW.stock_minimo THEN
        INSERT INTO alertas (tipo, descripcion)
        VALUES (
            'STOCK_BAJO',
            FORMAT('Stock bajo en "%s": actual=%s, minimo=%s.',
                   NEW.nombre, NEW.stock_actual, NEW.stock_minimo)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_alerta_stock_bajo ON inventario_vacunas;
CREATE TRIGGER trg_alerta_stock_bajo
    AFTER UPDATE OF stock_actual ON inventario_vacunas
    FOR EACH ROW
    WHEN (NEW.stock_actual <= NEW.stock_minimo)
    EXECUTE FUNCTION fn_alerta_stock_bajo();