// redis.js — Cliente Redis con logs de cache hit/miss
require('dotenv').config();
const Redis = require('ioredis');

const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT) || 6379,
  retryStrategy: (times) => Math.min(times * 100, 3000),
  enableOfflineQueue: false,
  lazyConnect: true,
});

redis.on('connect', () => console.log('🔴 Redis conectado'));
redis.on('error',   (err) => console.error('⚠  Redis no disponible:', err.message));

// Evitar que errores de Redis cierren el proceso
process.on('unhandledRejection', (err) => {
  console.error('Error no manejado (no crítico):', err.message);
});

const DEFAULT_TTL = 300;

async function cacheGet(key) {
  try {
    const data = await redis.get(key);
    if (data) {
      console.log(`[CACHE HIT]  ${key} — ${new Date().toISOString()}`);
      return JSON.parse(data);
    } else {
      console.log(`[CACHE MISS] ${key} — ${new Date().toISOString()}`);
      return null;
    }
  } catch {
    console.log(`[CACHE MISS] ${key} (Redis no disponible)`);
    return null;
  }
}

async function cacheSet(key, value, ttl = DEFAULT_TTL) {
  try {
    await redis.setex(key, ttl, JSON.stringify(value));
    console.log(`[CACHE SET]  ${key} TTL=${ttl}s — ${new Date().toISOString()}`);
  } catch (err) {
    console.error('⚠  Cache set falló:', err.message);
  }
}

async function cacheDel(...keys) {
  try {
    const valid = keys.filter(Boolean);
    if (valid.length > 0) {
      await redis.del(...valid);
      console.log(`[CACHE DEL]  ${valid.join(', ')} — ${new Date().toISOString()}`);
    }
  } catch (err) {
    console.error('⚠  Cache del falló:', err.message);
  }
}

module.exports = { redis, cacheGet, cacheSet, cacheDel, DEFAULT_TTL };