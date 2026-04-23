// middleware/auth.js — Autenticación con JWT
require('dotenv').config();
const jwt = require('jsonwebtoken');
const SECRET = process.env.JWT_SECRET || 'dev-secret';

function authenticate(req, res, next) {
  const header = req.headers['authorization'];
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token requerido.' });
  }
  try {
    const payload = jwt.verify(header.slice(7), SECRET);
    req.vetId = payload.vetId ?? null;
    req.role  = payload.role;
    next();
  } catch {
    res.status(401).json({ error: 'Token inválido o expirado.' });
  }
}

function generateDemoToken(vetId, role) {
  return jwt.sign({ vetId, role }, SECRET, { expiresIn: '8h' });
}

function adminOnly(req, res, next) {
  if (req.role !== 'clinica_admin') {
    return res.status(403).json({ error: 'Solo administradores.' });
  }
  next();
}

module.exports = { authenticate, generateDemoToken, adminOnly };