// routes/citas.js
const express = require('express');
const router  = express.Router();
const { queryWithRLS } = require('../db');
const { authenticate } = require('../middleware/auth');

router.use(authenticate);

// GET /api/citas
router.get('/', async (req, res) => {
  try {
    const result = await queryWithRLS(
      `SELECT c.id, m.nombre AS mascota, v.nombre AS veterinario,
              c.fecha_hora, c.motivo, c.estado, c.costo
       FROM citas c
       JOIN mascotas m     ON c.mascota_id     = m.id
       JOIN veterinarios v ON c.veterinario_id = v.id
       ORDER BY c.fecha_hora DESC LIMIT 100`,
      [], req.vetId
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Error al obtener citas.' });
  }
});

// POST /api/citas — agenda una cita usando sp_agendar_cita
router.post('/', async (req, res) => {
  const { mascota_id, veterinario_id, fecha_hora, motivo } = req.body;

  if (!mascota_id || !veterinario_id || !fecha_hora) {
    return res.status(400).json({ error: 'Campos requeridos: mascota_id, veterinario_id, fecha_hora.' });
  }

  const pMascota = parseInt(mascota_id,     10);
  const pVet     = parseInt(veterinario_id, 10);
  const pFecha   = new Date(fecha_hora);

  if (isNaN(pMascota) || pMascota <= 0) return res.status(400).json({ error: 'mascota_id inválido.' });
  if (isNaN(pVet)     || pVet     <= 0) return res.status(400).json({ error: 'veterinario_id inválido.' });
  if (isNaN(pFecha.getTime()))          return res.status(400).json({ error: 'fecha_hora inválida.' });

  const pMotivo = motivo ? String(motivo).slice(0, 500) : null;

  try {
    const result = await queryWithRLS(
      'CALL sp_agendar_cita($1, $2, $3, $4, NULL)',
      [pMascota, pVet, pFecha, pMotivo],
      req.vetId
    );
    res.status(201).json({
      message: 'Cita agendada.',
      cita_id: result.rows[0]?.p_cita_id
    });
  } catch (err) {
    console.error('[POST /citas]', err.message);
    res.status(400).json({ error: err.message });
  }
});

// PATCH /api/citas/:id/estado
router.patch('/:id/estado', async (req, res) => {
  const id     = parseInt(req.params.id, 10);
  const { estado } = req.body;

  const VALIDOS = ['AGENDADA', 'COMPLETADA', 'CANCELADA'];
  if (isNaN(id) || id <= 0)      return res.status(400).json({ error: 'ID inválido.' });
  if (!VALIDOS.includes(estado)) return res.status(400).json({ error: `Estado inválido. Use: ${VALIDOS.join(', ')}` });

  try {
    const result = await queryWithRLS(
      'UPDATE citas SET estado = $1 WHERE id = $2 RETURNING id, estado',
      [estado, id], req.vetId
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Cita no encontrada.' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Error al actualizar estado.' });
  }
});

module.exports = router;