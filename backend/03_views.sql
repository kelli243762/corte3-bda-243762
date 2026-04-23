-- =============================================
-- 03_views.sql
-- Vistas del sistema
-- =============================================

-- Vista principal: mascotas con vacunación pendiente
-- Usa CTE para calcular la última vacuna por mascota.
-- LEFT JOIN para incluir mascotas que nunca fueron vacunadas.
CREATE OR REPLACE VIEW v_mascotas_vacunacion_pendiente AS
WITH ultima_vacuna AS (
    SELECT   mascota_id,
             MAX(fecha_aplicacion) AS fecha_ultima
    FROM     vacunas_aplicadas
    GROUP BY mascota_id
)
SELECT
    m.nombre                                AS nombre,
    m.especie                               AS especie,
    d.nombre                                AS nombre_dueno,
    d.telefono                              AS telefono_dueno,
    uv.fecha_ultima                         AS fecha_ultima_vacuna,
    CASE
        WHEN uv.fecha_ultima IS NULL THEN NULL
        ELSE (CURRENT_DATE - uv.fecha_ultima)
    END                                     AS dias_desde_ultima_vacuna,
    CASE
        WHEN uv.fecha_ultima IS NULL THEN 'NUNCA_VACUNADA'
        ELSE 'VENCIDA'
    END                                     AS prioridad
FROM     mascotas m
JOIN     duenos d          ON m.dueno_id   = d.id
LEFT JOIN ultima_vacuna uv ON m.id         = uv.mascota_id
WHERE    uv.fecha_ultima IS NULL
      OR uv.fecha_ultima < CURRENT_DATE - INTERVAL '365 days'
ORDER BY prioridad, dias_desde_ultima_vacuna NULLS FIRST;


-- Vista de agenda de veterinarios
CREATE OR REPLACE VIEW v_agenda_veterinarios AS
SELECT
    v.nombre    AS veterinario,
    m.nombre    AS mascota,
    m.especie,
    d.nombre    AS dueno,
    d.telefono  AS telefono_dueno,
    c.fecha_hora,
    c.motivo,
    c.estado
FROM   citas c
JOIN   veterinarios v ON c.veterinario_id = v.id
JOIN   mascotas m     ON c.mascota_id     = m.id
JOIN   duenos d       ON m.dueno_id       = d.id
WHERE  c.fecha_hora >= NOW()
  AND  c.estado     = 'AGENDADA'
ORDER BY c.fecha_hora;


-- Vista de ingresos por veterinario (solo admin)
CREATE OR REPLACE VIEW v_ingresos_por_veterinario AS
SELECT
    v.nombre                                                              AS veterinario,
    COUNT(DISTINCT c.id)                                                  AS total_citas,
    COALESCE(SUM(c.costo) FILTER (WHERE c.estado = 'COMPLETADA'), 0)      AS ingresos_citas,
    COUNT(DISTINCT va.id)                                                 AS vacunas_aplicadas,
    COALESCE(SUM(va.costo_cobrado), 0)                                    AS ingresos_vacunas,
    COALESCE(SUM(c.costo) FILTER (WHERE c.estado = 'COMPLETADA'), 0)
        + COALESCE(SUM(va.costo_cobrado), 0)                              AS ingreso_total
FROM     veterinarios v
LEFT JOIN citas c              ON v.id = c.veterinario_id
LEFT JOIN vacunas_aplicadas va ON v.id = va.veterinario_id
GROUP BY v.id, v.nombre
ORDER BY ingreso_total DESC;