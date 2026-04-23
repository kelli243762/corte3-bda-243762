// routes/mascotas.js
const express = require('express');
const router  = express.Router();
const { queryWithRLS }         = require('../db');
const { cacheGet, cacheSet, cacheDel } = require('../redis');
const { authenticate }         = require('../middleware/auth');

router.use(authenticate);

// GET /api/mascotas — lista todas (RLS filtra según el vet)
router.get('/', async (req, res) => {
  const cacheKey = req.vetId ? `mascotas:vet:${req.vetId}` : 'mascotas:all';
  const cached   = await cacheGet(cacheKey);
  if (cached) return res.json({ source: 'cache', data: cached });

  try {
    const result = await queryWithRLS(
      `SELECT m.id, m.nombre, m.especie, m.fecha_nacimiento,
              d.nombre AS dueno, d.telefono AS dueno_telefono
       FROM mascotas m JOIN duenos d ON m.dueno_id = d.id
       ORDER BY m.nombre`,
      [], req.vetId
    );
    await cacheSet(cacheKey, result.rows);
    res.json({ source: 'db', data: result.rows });
  } catch (err) {
    console.error('[GET /mascotas]', err.message);
    res.status(500).json({ error: 'Error al obtener mascotas.' });
  }
});

// GET /api/mascotas/buscar?q=texto — búsqueda hardened
// LÍNEA CRÍTICA DE HARDENING (archivo: routes/mascotas.js):
// El input del usuario se convierte a string, se limita a 100 chars,
// y se pasa como parámetro $1. Nunca se concatena al SQL.
router.get('/buscar', async (req, res) => {
  const busqueda = '%' + String(req.query.q || '').slice(0, 100) + '%';

  try {
    const result = await queryWithRLS(
      `SELECT m.id, m.nombre, m.especie, m.fecha_nacimiento,
              d.nombre AS dueno, d.telefono
       FROM mascotas m JOIN duenos d ON m.dueno_id = d.id
       WHERE m.nombre ILIKE $1 OR m.especie ILIKE $1
       ORDER BY m.nombre
       LIMIT 50`,
      [busqueda],
      req.vetId
    );
    res.json({ data: result.rows, total: result.rowCount });
  } catch (err) {
    console.error('[GET /mascotas/buscar]', err.message);
    res.status(500).json({ error: 'Error en búsqueda.' });
  }
});

// GET /api/mascotas/vacunacion-pendiente — consulta cacheada
router.get('/vacunacion-pendiente', async (req, res) => {
  const cacheKey = 'vacunacion_pendiente';
  const cached   = await cacheGet(cacheKey);
  if (cached) return res.json({ source: 'cache', data: cached });

  try {
    const t0     = Date.now();
    const result = await queryWithRLS(
      'SELECT * FROM v_mascotas_vacunacion_pendiente',
      [], req.vetId
    );
    const ms = Date.now() - t0;
    console.log(`[DB QUERY]   vacunacion_pendiente — ${ms}ms`);
    await cacheSet(cacheKey, result.rows);
    res.json({ source: 'db', latencia_ms: ms, data: result.rows });
  } catch (err) {
    console.error('[GET /vacunacion-pendiente]', err.message);
    res.status(500).json({ error: 'Error al consultar vacunación pendiente.' });
  }
});

// GET /api/mascotas/:id — detalle de una mascota
router.get('/:id', async (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (isNaN(id) || id <= 0) {
    return res.status(400).json({ error: 'ID debe ser entero positivo.' });
  }
  try {
    const result = await queryWithRLS(
      `SELECT m.*, d.nombre AS dueno, d.telefono, d.email
       FROM mascotas m JOIN duenos d ON m.dueno_id = d.id
       WHERE m.id = $1`,
      [id], req.vetId
    );
    if (!result.rows.length) return res.status(404).json({ error: 'No encontrada.' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Error al obtener mascota.' });
  }
});

module.exports = { router, cacheDel };