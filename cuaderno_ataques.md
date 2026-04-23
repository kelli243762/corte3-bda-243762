# Cuaderno de Ataques — SQL Injection
## Clínica Veterinaria · Corte 3 BDA · UP Chiapas

## Sección 1: Tres ataques de SQL Injection que fallan

### Ataque 1 — Quote-escape clásico: ' OR '1'='1

Input exacto probado: ' OR '1'='1

Pantalla donde se probó: Buscar Mascotas, campo de texto, se escribe el payload y se hace clic en Buscar.

Qué haría en código vulnerable: en un código que concatene strings directamente, el SQL quedaría SELECT * FROM mascotas WHERE nombre LIKE '%' OR '1'='1%' y devolvería todas las mascotas sin importar el usuario autenticado.

Por qué falla en nuestro sistema:

Archivo api/routes/mascotas.js línea 33:

    const busqueda = '%' + String(req.query.q || '').slice(0, 100) + '%';

El input ' OR '1'='1 se convierte en el string % OR 1=1% y se pasa como parámetro $1 al driver pg. PostgreSQL lo recibe como dato de texto para el ILIKE, no como código SQL. Ninguna mascota tiene ese nombre exacto, devuelve 0 resultados.

Resultado: HTTP 200 con data vacío y total 0.

### Ataque 2 — Stacked query: '; DROP TABLE mascotas; --

Input exacto probado: '; DROP TABLE mascotas; --

Pantalla donde se probó: Buscar Mascotas, campo de texto, se escribe el payload y se hace clic en Buscar.

Qué haría en código vulnerable: el SQL quedaría SELECT * FROM mascotas WHERE nombre LIKE '%'; DROP TABLE mascotas; --%' y destruiría la tabla mascotas.

Por qué falla en nuestro sistema:

El driver pg de Node.js no permite stacked queries. Solo ejecuta una statement por llamada a client.query(). Aunque el string llegara al SQL, el driver rechazaría el punto y coma como separador de sentencias. Además la línea de hardening en api/routes/mascotas.js línea 33 convierte el payload en dato de búsqueda que PostgreSQL trata como texto literal. La tabla mascotas no se ve afectada.

Resultado: HTTP 200 con data vacío y total 0.

### Ataque 3 — UNION para exfiltrar cédulas

Input exacto probado: ' UNION SELECT 1,cedula,cedula,NOW(),'x' FROM veterinarios--

Pantalla donde se probó: Buscar Mascotas, campo de texto, se escribe el payload y se hace clic en Buscar.

Qué haría en código vulnerable: el SQL resultante incluiría un UNION que devolvería las cédulas de todos los veterinarios disfrazadas como nombres de mascotas.

Por qué falla en nuestro sistema:

El payload se pasa como parámetro $1 al driver pg. PostgreSQL lo interpreta como texto de búsqueda para el ILIKE, no como código SQL. No hay ningún UNION que se ejecute. Además la política RLS pol_mascotas_vet filtraría los resultados según el vet activo aunque hipotéticamente llegara algún dato.

Resultado: HTTP 200 con data vacío y total 0.

## Sección 2: Demostración de RLS en acción

Setup: dos veterinarios con mascotas distintas en vet_atiende_mascota. El Dr. López con vet_id 1 atiende a Firulais, Toby y Max. La Dra. García con vet_id 2 atiende a Misifú, Luna y Dante.

Procedimiento:
1. Login, seleccionar Dr. López vet_id 1, Iniciar Sesión
2. Buscar Mascotas, clic en Ver todas
3. Resultado: solo aparecen Firulais, Toby, Max
4. Login, seleccionar Dra. García vet_id 2, Iniciar Sesión
5. Buscar Mascotas, clic en Ver todas
6. Resultado: solo aparecen Misifú, Luna, Dante

Resultado Dr. López: ID 1 Firulais perro, ID 5 Toby perro, ID 7 Max perro. Total 3 mascotas.

Resultado Dra. García: ID 2 Misifú gato, ID 4 Luna gato, ID 9 Dante perro. Total 3 mascotas.

Política RLS que produce este comportamiento:

    CREATE POLICY pol_mascotas_vet ON mascotas
        FOR SELECT TO clinica_vet
        USING (
            id IN (
                SELECT mascota_id FROM vet_atiende_mascota
                WHERE vet_id = current_setting('app.current_vet_id', TRUE)::INT
                  AND activa = TRUE
            )
        );

El backend establece SET LOCAL app.current_vet_id = 1 al inicio de la transacción. PostgreSQL evalúa la condición fila por fila y solo muestra las mascotas asignadas a ese vet. Las mascotas de otros vets son invisibles.

## Sección 3: Demostración de caché Redis funcionando

Key usada: vacunacion_pendiente
TTL elegido: 300 segundos que son 5 minutos
Por qué: la consulta tarda entre 100 y 300ms y los datos solo cambian cuando se aplica una vacuna. Con 5 minutos de TTL se reduce la carga en PostgreSQL sin sacrificar frescura de datos.

Procedimiento:
1. Login con cualquier rol
2. Vacunación Pendiente, clic en Consultar, primera consulta MISS
3. Clic en Consultar de nuevo, segunda consulta HIT
4. Clic en Aplicar Vacuna, llenar datos, Aplicar, invalida caché
5. Clic en Consultar de nuevo, tercera consulta MISS de nuevo

Logs del servidor:

    [CACHE MISS] vacunacion_pendiente — 2026-04-22T03:35:00.000Z
    [DB QUERY]   vacunacion_pendiente — 187ms
    [CACHE SET]  vacunacion_pendiente TTL=300s — 2026-04-22T03:35:00.190Z
    [CACHE HIT]  vacunacion_pendiente — 2026-04-22T03:35:05.000Z
    [CACHE DEL]  vacunacion_pendiente — 2026-04-22T03:36:00.000Z
    [CACHE MISS] vacunacion_pendiente — 2026-04-22T03:36:10.000Z
    [DB QUERY]   vacunacion_pendiente — 201ms
    [CACHE SET]  vacunacion_pendiente TTL=300s — 2026-04-22T03:36:10.200Z

Código que invalida el caché en archivo api/routes/vacunas.js:

    await cacheDel('vacunacion_pendiente', vetKey, 'mascotas:all');

Esta línea corre inmediatamente después de que la vacuna se aplica con éxito. La invalidación es explícita, no esperamos que el TTL expire. La siguiente consulta siempre ve datos frescos.