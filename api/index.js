// index.js — Servidor principal
require('dotenv').config();
const express = require('express');
const path    = require('path');
const { generateDemoToken } = require('./middleware/auth');

const app = express();
app.use(express.json());

// Servir frontend
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// Rutas API
app.use('/api/mascotas', require('./routes/mascotas').router);
app.use('/api/citas',    require('./routes/citas'));
app.use('/api/vacunas',  require('./routes/vacunas'));

// Health check
app.get('/health', (req, res) => res.json({ status: 'ok', ts: new Date().toISOString() }));

// Generador de tokens de demo
app.post('/api/auth/demo-token', (req, res) => {
  const { vet_id, role } = req.body;
  const rolesValidos = ['clinica_admin', 'clinica_vet', 'clinica_recepcionista'];
  if (!rolesValidos.includes(role)) {
    return res.status(400).json({ error: `Rol inválido. Use: ${rolesValidos.join(', ')}` });
  }
  const vetId = vet_id != null ? parseInt(vet_id, 10) : null;
  res.json({ token: generateDemoToken(vetId, role), vet_id: vetId, role });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`\n🐾 Clínica Veterinaria · http://localhost:${PORT}`);
  console.log('   Frontend: http://localhost:' + PORT + '/');
});