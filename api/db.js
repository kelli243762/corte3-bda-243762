// db.js — Conexión PostgreSQL con soporte RLS
require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME     || 'clinica_vet',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || '',
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => console.error('❌ PG pool error:', err.message));

/**
 * Ejecuta una query con contexto RLS.
 * SET LOCAL app.current_vet_id solo vive dentro de la transacción.
 * Al hacer COMMIT/ROLLBACK desaparece — no contamina otras conexiones.
 */
async function queryWithRLS(sql, params = [], vetId = null) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (vetId !== null) {
      await client.query('SET LOCAL app.current_vet_id = $1', [String(vetId)]);
    }
    const result = await client.query(sql, params);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, queryWithRLS };