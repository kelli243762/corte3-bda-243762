-- =============================================
-- 04_roles_y_permisos.sql
-- Roles y permisos del sistema
-- =============================================

-- Limpiar roles previos (idempotente)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user')         THEN DROP USER admin_user;         END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vet_user')           THEN DROP USER vet_user;           END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'recepcionista_user') THEN DROP USER recepcionista_user; END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinica_admin')         THEN DROP ROLE clinica_admin;         END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinica_vet')           THEN DROP ROLE clinica_vet;           END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinica_recepcionista') THEN DROP ROLE clinica_recepcionista; END IF;
END $$;

-- Roles grupo
CREATE ROLE clinica_admin         NOLOGIN;
CREATE ROLE clinica_vet           NOLOGIN;
CREATE ROLE clinica_recepcionista NOLOGIN;

-- Usuarios concretos
CREATE USER admin_user         PASSWORD 'Admin#Clinica2026!'  IN ROLE clinica_admin;
CREATE USER vet_user           PASSWORD 'Vet#Clinica2026!'    IN ROLE clinica_vet;
CREATE USER recepcionista_user PASSWORD 'Recep#Clinica2026!'  IN ROLE clinica_recepcionista;

-- =============================================
-- clinica_admin: acceso total + BYPASSRLS
-- =============================================
GRANT USAGE ON SCHEMA public TO clinica_admin;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO clinica_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO clinica_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO clinica_admin;
ALTER ROLE clinica_admin BYPASSRLS;

-- =============================================
-- clinica_vet: sus mascotas, citas, vacunas
-- =============================================
GRANT USAGE ON SCHEMA public TO clinica_vet;

GRANT SELECT ON duenos              TO clinica_vet;
GRANT SELECT ON mascotas            TO clinica_vet;
GRANT SELECT ON veterinarios        TO clinica_vet;
GRANT SELECT ON vet_atiende_mascota TO clinica_vet;
GRANT SELECT ON citas               TO clinica_vet;
GRANT SELECT ON vacunas_aplicadas   TO clinica_vet;
GRANT SELECT ON inventario_vacunas  TO clinica_vet;

GRANT INSERT, UPDATE ON citas                TO clinica_vet;
GRANT INSERT         ON vacunas_aplicadas    TO clinica_vet;
GRANT INSERT         ON historial_movimientos TO clinica_vet;

GRANT USAGE, SELECT ON SEQUENCE citas_id_seq                 TO clinica_vet;
GRANT USAGE, SELECT ON SEQUENCE vacunas_aplicadas_id_seq     TO clinica_vet;
GRANT USAGE, SELECT ON SEQUENCE historial_movimientos_id_seq TO clinica_vet;

-- REVOKE explícito de operaciones peligrosas
REVOKE DELETE                  ON citas              FROM clinica_vet;
REVOKE INSERT, UPDATE, DELETE  ON mascotas           FROM clinica_vet;
REVOKE INSERT, UPDATE, DELETE  ON duenos             FROM clinica_vet;
REVOKE INSERT, UPDATE, DELETE  ON inventario_vacunas FROM clinica_vet;
REVOKE INSERT, UPDATE, DELETE  ON veterinarios       FROM clinica_vet;
REVOKE ALL                     ON alertas            FROM clinica_vet;

-- =============================================
-- clinica_recepcionista: agenda, sin médico
-- =============================================
GRANT USAGE ON SCHEMA public TO clinica_recepcionista;

GRANT SELECT ON duenos              TO clinica_recepcionista;
GRANT SELECT ON mascotas            TO clinica_recepcionista;
GRANT SELECT ON veterinarios        TO clinica_recepcionista;
GRANT SELECT ON vet_atiende_mascota TO clinica_recepcionista;

-- Citas sin columna costo
GRANT SELECT (id, mascota_id, veterinario_id, fecha_hora, motivo, estado)
    ON citas TO clinica_recepcionista;
GRANT INSERT          ON citas                       TO clinica_recepcionista;
GRANT UPDATE (estado) ON citas                       TO clinica_recepcionista;
GRANT USAGE, SELECT   ON SEQUENCE citas_id_seq       TO clinica_recepcionista;

GRANT INSERT        ON duenos                        TO clinica_recepcionista;
GRANT INSERT        ON mascotas                      TO clinica_recepcionista;
GRANT USAGE, SELECT ON SEQUENCE duenos_id_seq        TO clinica_recepcionista;
GRANT USAGE, SELECT ON SEQUENCE mascotas_id_seq      TO clinica_recepcionista;

-- REVOKE de lo médico y financiero
REVOKE ALL ON vacunas_aplicadas     FROM clinica_recepcionista;
REVOKE ALL ON inventario_vacunas    FROM clinica_recepcionista;
REVOKE ALL ON historial_movimientos FROM clinica_recepcionista;
REVOKE ALL ON alertas               FROM clinica_recepcionista;

-- Permisos sobre vistas
GRANT SELECT ON v_mascotas_vacunacion_pendiente TO clinica_admin, clinica_vet;
GRANT SELECT ON v_agenda_veterinarios           TO clinica_admin, clinica_vet, clinica_recepcionista;
GRANT SELECT ON v_ingresos_por_veterinario      TO clinica_admin;

GRANT EXECUTE ON FUNCTION fn_total_facturado(INT, INT) TO clinica_admin, clinica_vet;