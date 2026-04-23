// routes/vacunas.js
const express = require('express');
const router  = express.Router();
const { queryWithRLS }             = require('../db');
const { cacheGet, cacheSet, cacheDel } = require('../redis');
const { authenticate }             = require('../middleware/auth');

router.use(authenticate);

// POST /api/vacunas/aplicar — aplica vacuna e invalida caché
router.post('/aplicar', async (req, res) => {
  const { mascota_id, vacuna_id, veterinario_id, costo_cobrado } = req.body;

  const pM  = parseInt(mascota_id,     10);
  const pV  = parseInt(vacuna_id,      10);
  const pVt = parseInt(veterinario_id, 10);
  const pC  = parseFloat(costo_cobrado) || 0;

  if ([pM, pV, pVt].some(v => isNaN(v) || v <= 0)) {
    return res.status(400).json({ error: 'IDs inválidos.' });
  }

  try {
    const result = await queryWithRLS(
      `INSERT INTO vacunas_aplicadas (mascota_id, vacuna_id, veterinario_id, costo_cobrado)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [pM, pV, pVt, pC], req.vetId
    );

    // Invalidar caché después de aplicar vacuna
    const vetKey = req.vetId ? `mascotas:vet:${req.vetId}` : null;
    await cacheDel('vacunacion_pendiente', vetKey, 'mascotas:all');

    res.status(201).json({
      message:       'Vacuna aplicada.',
      aplicacion_id: result.rows[0].id
    });
  } catch (err) {
    console.error('[POST /vacunas/aplicar]', err.message);
    res.status(400).json({ error: err.message });
  }
});

// GET /api/vacunas/inventario
router.get('/inventario', async (req, res) => {
  try {
    const result = await queryWithRLS(
      `SELECT id, nombre, stock_actual, stock_minimo, costo_unitario,
              CASE WHEN stock_actual = 0             THEN 'AGOTADO'
                   WHEN stock_actual <= stock_minimo THEN 'BAJO'
                   ELSE 'OK' END AS estado_stock
       FROM inventario_vacunas ORDER BY estado_stock, nombre`,
      [], req.vetId
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Error al obtener inventario.' });
  }
});

module.exports = router;