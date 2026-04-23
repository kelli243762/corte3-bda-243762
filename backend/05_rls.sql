-- =============================================
-- 05_rls.sql
-- Row-Level Security
-- =============================================
-- Mecanismo: SET LOCAL app.current_vet_id = <id>
-- El backend establece esta variable al inicio de
-- cada transacción. SET LOCAL garantiza que solo
-- vive dentro de esa transacción y no contamina
-- otras conexiones del pool.
-- =============================================

-- Limpiar políticas previas
DO $$
DECLARE pol RECORD;
BEGIN
    FOR pol IN SELECT policyname, tablename FROM pg_policies
               WHERE tablename IN ('mascotas','citas','vacunas_aplicadas')
    LOOP
        EXECUTE FORMAT('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- Habilitar RLS en las tres tablas sensibles
ALTER TABLE mascotas          ENABLE ROW LEVEL SECURITY;
ALTER TABLE citas             ENABLE ROW LEVEL SECURITY;
ALTER TABLE vacunas_aplicadas ENABLE ROW LEVEL SECURITY;

ALTER TABLE mascotas          FORCE ROW LEVEL SECURITY;
ALTER TABLE citas             FORCE ROW LEVEL SECURITY;
ALTER TABLE vacunas_aplicadas FORCE ROW LEVEL SECURITY;

-- =============================================
-- Políticas: mascotas
-- =============================================
CREATE POLICY pol_mascotas_admin ON mascotas
    FOR ALL TO clinica_admin
    USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_mascotas_vet ON mascotas
    FOR SELECT TO clinica_vet
    USING (
        id IN (
            SELECT mascota_id
            FROM   vet_atiende_mascota
            WHERE  vet_id = current_setting('app.current_vet_id', TRUE)::INT
              AND  activa = TRUE
        )
    );

CREATE POLICY pol_mascotas_recep_sel ON mascotas
    FOR SELECT TO clinica_recepcionista USING (TRUE);

CREATE POLICY pol_mascotas_recep_ins ON mascotas
    FOR INSERT TO clinica_recepcionista WITH CHECK (TRUE);

-- =============================================
-- Políticas: citas
-- =============================================
CREATE POLICY pol_citas_admin ON citas
    FOR ALL TO clinica_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_citas_vet_sel ON citas
    FOR SELECT TO clinica_vet
    USING (veterinario_id = current_setting('app.current_vet_id', TRUE)::INT);

CREATE POLICY pol_citas_vet_ins ON citas
    FOR INSERT TO clinica_vet
    WITH CHECK (veterinario_id = current_setting('app.current_vet_id', TRUE)::INT);

CREATE POLICY pol_citas_vet_upd ON citas
    FOR UPDATE TO clinica_vet
    USING (veterinario_id = current_setting('app.current_vet_id', TRUE)::INT);

CREATE POLICY pol_citas_recep_sel ON citas
    FOR SELECT TO clinica_recepcionista USING (TRUE);

CREATE POLICY pol_citas_recep_ins ON citas
    FOR INSERT TO clinica_recepcionista WITH CHECK (TRUE);

CREATE POLICY pol_citas_recep_upd ON citas
    FOR UPDATE TO clinica_recepcionista USING (TRUE);

-- =============================================
-- Políticas: vacunas_aplicadas
-- =============================================
CREATE POLICY pol_vacunas_admin ON vacunas_aplicadas
    FOR ALL TO clinica_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_vacunas_vet_sel ON vacunas_aplicadas
    FOR SELECT TO clinica_vet
    USING (
        mascota_id IN (
            SELECT mascota_id FROM vet_atiende_mascota
            WHERE vet_id = current_setting('app.current_vet_id', TRUE)::INT
              AND activa = TRUE
        )
    );

CREATE POLICY pol_vacunas_vet_ins ON vacunas_aplicadas
    FOR INSERT TO clinica_vet
    WITH CHECK (veterinario_id = current_setting('app.current_vet_id', TRUE)::INT);

-- Verificación
DO $$
DECLARE r RECORD;
BEGIN
    RAISE NOTICE '=== Estado RLS ===';
    FOR r IN SELECT relname, relrowsecurity, relforcerowsecurity
             FROM pg_class
             WHERE relname IN ('mascotas','citas','vacunas_aplicadas')
    LOOP
        RAISE NOTICE '  % → RLS=% FORCE=%', r.relname, r.relrowsecurity, r.relforcerowsecurity;
    END LOOP;
END $$;