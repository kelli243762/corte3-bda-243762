# Clínica Veterinaria · Corte 3 BDA
**UP Chiapas · Base de Datos Avanzadas · Abril 2026**
**Alumna:** Kelly Anahí · Matrícula: 243762

## Stack
- PostgreSQL 15
- Redis 7
- Node.js 18
- Express 4

## Estructura

corte3-bda-243762/
├── README.md
├── cuaderno_ataques.md
├── schema_corte3.sql
├── backend/
│   ├── 01_procedures.sql
│   ├── 02_triggers.sql
│   ├── 03_views.sql
│   ├── 04_roles_y_permisos.sql
│   └── 05_rls.sql
├── api/
│   ├── index.js
│   ├── db.js
│   ├── redis.js
│   ├── middleware/auth.js
│   └── routes/
│       ├── mascotas.js
│       ├── citas.js
│       └── vacunas.js
└── frontend/
└── index.html

## Cómo ejecutar

1. Cargar el schema en PostgreSQL:
psql -d clinica_vet -f schema_corte3.sql
psql -d clinica_vet -f backend/01_procedures.sql
psql -d clinica_vet -f backend/02_triggers.sql
psql -d clinica_vet -f backend/03_views.sql
psql -d clinica_vet -f backend/04_roles_y_permisos.sql
psql -d clinica_vet -f backend/05_rls.sql

2. Iniciar Redis con Docker:
docker run -d -p 6379:6379 --name redis redis:7-alpine

3. Iniciar el API:
cd api
npm install
node index.js

4. Abrir el navegador en http://localhost:3001

---

## Preguntas de diseño

### Pregunta 1
**¿Qué política RLS aplicaste a la tabla mascotas? Pega la cláusula exacta y explica con tus palabras qué hace.**

```sql
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
```

Esta política hace que cuando un veterinario hace SELECT en mascotas, solo ve las filas cuyo id aparece en vet_atiende_mascota ligado a su propio vet_id. El vet_id lo lee de la variable de sesión app.current_vet_id que el backend establece al inicio de cada transacción con SET LOCAL. Si el vet es el Dr. López con id 1, solo verá Firulais, Toby y Max. Un admin con BYPASSRLS ignora esta política y ve las 10 mascotas.

---

### Pregunta 2
**La estrategia de identificar al veterinario tiene un vector de ataque posible. ¿Cuál es? ¿Tu sistema lo previene? ¿Cómo?**

El vector: si alguien tiene las credenciales de vet_user y se conecta directamente a PostgreSQL saltándose el API, puede ejecutar SET LOCAL app.current_vet_id = 2 y ver las mascotas de otro veterinario.

Cómo lo previene el sistema: el API es el único cliente que conecta a PostgreSQL. El puerto 5432 no se expone públicamente. El vet_id que llega al queryWithRLS viene de un JWT firmado con JWT_SECRET que solo el backend conoce. Para explotar el vector, el atacante necesitaría las credenciales de vet_user y acceso directo al puerto 5432, lo que implica que el servidor ya fue comprometido.

---

### Pregunta 3
**Si usas SECURITY DEFINER, ¿qué medida tomaste para prevenir la escalada de privilegios?**

Uso SECURITY DEFINER en sp_agendar_cita y sp_aplicar_vacuna. El vector de escalada es que una función SECURITY DEFINER se ejecuta con los permisos de quien la creó. Si el search_path no está fijo, un atacante podría crear un schema con objetos del mismo nombre antes de public y la función usaría los objetos maliciosos.

La medida tomada fue agregar SET search_path = public en la definición de ambas funciones:

```sql
CREATE OR REPLACE PROCEDURE sp_agendar_cita(...)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ ... $$;
```

Con esto la función siempre busca objetos en public sin importar qué tenga el search_path del llamador.

---

### Pregunta 4
**¿Qué TTL le pusiste al caché Redis y por qué? ¿Qué pasaría si fuera demasiado bajo o demasiado alto?**

TTL elegido: 300 segundos que son 5 minutos.

Justificación: la vista v_mascotas_vacunacion_pendiente recorre todas las mascotas y sus vacunas tardando entre 100 y 300ms. Si se consulta unas 50 veces por hora, sin caché serían 50 queries costosas. Con TTL de 5 minutos solo hay 12 misses por hora máximo.

Si el TTL fuera demasiado bajo como 5 segundos, el caché expiraría antes de la siguiente consulta y no habría beneficio real, el sistema iría a PostgreSQL en casi todas las peticiones.

Si el TTL fuera demasiado alto como 24 horas, si se aplica una vacuna y hay un bug en la invalidación, los vets verían mascotas como pendientes durante horas. En este sistema la invalidación es explícita con cacheDel al aplicar vacuna, por lo que el TTL es solo una red de seguridad.

---

### Pregunta 5
**Elige un endpoint crítico y pega la línea exacta donde el backend maneja el input antes de enviarlo a la BD. Explica qué protege esa línea y de qué. Indica archivo y número de línea.**

Endpoint: GET /api/mascotas/buscar?q=texto

Archivo: api/routes/mascotas.js — línea 33:

```javascript
const busqueda = '%' + String(req.query.q || '').slice(0, 100) + '%';
```

Y la query que usa ese valor:

```javascript
const result = await queryWithRLS(
  `SELECT ... WHERE m.nombre ILIKE $1 OR m.especie ILIKE $1`,
  [busqueda],
  req.vetId
);
```

Esta línea convierte el input del usuario a string, lo limita a 100 caracteres, y lo pasa como parámetro $1. El driver pg lo envía a PostgreSQL como dato separado del SQL, nunca como código SQL. Si el usuario mete la cadena OR 1=1, el valor de $1 sería ese texto literal que como dato no coincide con ningún nombre de mascota y devuelve 0 resultados. No hay inyección posible porque el string del usuario nunca se concatena al SQL.

---

### Pregunta 6
**Si revocas todos los permisos del rol de veterinario excepto SELECT en mascotas, ¿qué deja de funcionar? Lista tres operaciones.**

1. Registrar citas: sp_agendar_cita hace INSERT INTO citas. Sin INSERT ON citas el procedure falla con error de permisos y el veterinario no puede agendar ninguna cita.

2. Aplicar vacunas: sp_aplicar_vacuna hace INSERT INTO vacunas_aplicadas y UPDATE en inventario_vacunas. Sin esos permisos el veterinario no puede registrar ninguna vacunación.

3. Registrar en historial: el trigger trg_historial_cita hace INSERT INTO historial_movimientos. Sin ese permiso cualquier acción que requiera logging fallaría, rompiendo la trazabilidad completa del sistema.
