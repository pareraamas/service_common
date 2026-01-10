import 'dart:async';
import 'package:dotenv/dotenv.dart';
import 'package:logging/logging.dart';
import 'package:redis/redis.dart';

class CacheEntry {
  const CacheEntry({required this.value, this.expiresAt});

  final String value;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

class CacheService {
  CacheService._internal();
  static final CacheService _instance = CacheService._internal();
  static CacheService get instance => _instance;

  final DotEnv _env = DotEnv(includePlatformEnvironment: true)..load();
  final Logger _logger = Logger('CacheService');

  // Redis components
  RedisConnection? _redisConnection;
  Command? _redisCommand;
  bool _useRedis = false;

  // In-memory fallback
  final Map<String, CacheEntry> _memoryCache = {};

  bool get isRedisConnected =>
      _redisConnection != null && _redisCommand != null;

  /// Initializes the cache service.
  /// Tries to connect to Redis. If fails, falls back to in-memory cache.
  Future<void> initialize() async {
    if (isRedisConnected) return;

    final host = _env['REDIS_HOST'] ?? 'localhost';
    final port = int.tryParse(_env['REDIS_PORT'] ?? '6379') ?? 6379;

    try {
      _redisConnection = RedisConnection();
      _redisCommand = await _redisConnection!.connect(host, port);
      _useRedis = true;
      _logger.info('Connected to Redis at $host:$port');
    } catch (e) {
      _useRedis = false;
      _logger
          .info('Redis not available ($e). Falling back to in-memory cache.');
    }
  }

  /// Sets a value in the cache with optional expiration.
  Future<void> set(String key, String value, {Duration? expiration}) async {
    if (_useRedis && isRedisConnected) {
      try {
        await _redisCommand!.set(key, value);
        if (expiration != null) {
          await _redisCommand!
              .send_object(['EXPIRE', key, expiration.inSeconds]);
        }
        return;
      } catch (e) {
        _logger.warning(
          'Redis set failed: $e. Switching to memory fallback temporarily.',
        );
        _useRedis = false; // Fallback on error
      }
    }

    // In-memory fallback
    final expiresAt =
        expiration != null ? DateTime.now().add(expiration) : null;
    _memoryCache[key] = CacheEntry(value: value, expiresAt: expiresAt);

    // Cleanup if setting memory cache
    _cleanupMemory();
  }

  /// Gets a value from the cache.
  Future<String?> get(String key) async {
    if (_useRedis && isRedisConnected) {
      try {
        final result = await _redisCommand!.get(key);
        return result?.toString();
      } catch (e) {
        _logger.warning(
          'Redis get failed: $e. Switching to memory fallback temporarily.',
        );
        _useRedis = false;
      }
    }

    // In-memory fallback
    final entry = _memoryCache[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _memoryCache.remove(key);
      return null;
    }

    return entry.value;
  }

  /// Deletes a value from the cache.
  Future<void> delete(String key) async {
    if (_useRedis && isRedisConnected) {
      try {
        await _redisCommand!.send_object(['DEL', key]);
        return;
      } catch (e) {
        _logger.warning('Redis delete failed: $e.');
        _useRedis = false;
      }
    }

    _memoryCache.remove(key);
  }

  /// Increment a key's value by 1. Returns the new value.
  /// If key doesn't exist, it is set to 1.
  /// Useful for rate limiting.
  Future<int> increment(String key, {Duration? expiration}) async {
    if (_useRedis && isRedisConnected) {
      try {
        // INCR returns the new value
        final val = await _redisCommand!.send_object(['INCR', key]);

        // Set expiration if it's a new key (val == 1) and expiration provided
        if (val == 1 && expiration != null) {
          await _redisCommand!
              .send_object(['EXPIRE', key, expiration.inSeconds]);
        }
        return val is int ? val : int.parse(val.toString());
      } catch (e) {
        _logger.warning('Redis incr failed: $e. Switching to memory fallback.');
        _useRedis = false;
      }
    }

    // Memory Fallback
    final entry = _memoryCache[key];
    int currentVal = 0;

    if (entry != null && !entry.isExpired) {
      currentVal = int.tryParse(entry.value) ?? 0;
    }

    final newVal = currentVal + 1;
    final expiresAt = (entry != null && !entry.isExpired)
        ? entry.expiresAt // Keep existing expiration
        : (expiration != null
            ? DateTime.now().add(expiration)
            : null); // New expiration

    _memoryCache[key] =
        CacheEntry(value: newVal.toString(), expiresAt: expiresAt);
    _cleanupMemory();

    return newVal;
  }

  /// Checks if a key exists in the cache.
  Future<bool> exists(String key) async {
    if (_useRedis && isRedisConnected) {
      try {
        final result = await _redisCommand!.send_object(['EXISTS', key]);
        return result == 1;
      } catch (e) {
        _logger.warning('Redis exists failed: $e.');
        _useRedis = false;
      }
    }

    final entry = _memoryCache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _memoryCache.remove(key);
      return false;
    }
    return true;
  }

  // Simple cleanup for memory cache to avoid overflow in long-running process
  void _cleanupMemory() {
    if (_memoryCache.length > 10000) {
      _memoryCache.removeWhere((_, entry) => entry.isExpired);
      // If still too big, remove oldest (simple strategy)
      if (_memoryCache.length > 10000) {
        final keysToRemove = _memoryCache.keys.take(1000).toList();
        for (final key in keysToRemove) {
          _memoryCache.remove(key);
        }
      }
    }
  }
}
