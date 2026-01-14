import 'dart:async';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:logging/logging.dart';
import 'package:mysql_client_plus/mysql_client_plus.dart';

class DatabaseProvider {
  DatabaseProvider._internal();
  static final DatabaseProvider _instance = DatabaseProvider._internal();
  static DatabaseProvider get instance => _instance;

  MySQLConnectionPool? _pool;
  final Logger _logger = Logger('DatabaseProvider');
  final DotEnv _env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

  Future<void> initialize() async {
    if (_pool != null) {
      return;
    }

    final host = _env['DB_HOST'] ?? 'localhost';
    final port = int.tryParse(_env['DB_PORT'] ?? '3306') ?? 3306;
    final user = _env['DB_USER'] ?? 'root';
    final password = _env['DB_PASSWORD'] ?? '';
    final dbName = _env['DB_NAME'] ?? 'master_service';
    final poolSize = int.tryParse(_env['DB_POOL_SIZE'] ?? '10') ?? 10;
    final autoMigrate = (_env['DB_AUTO_MIGRATE'] ?? 'true').toLowerCase() == 'true';
    final secure = (_env['DB_SECURE'] ?? 'true').toLowerCase() == 'true';

    _logger.info('Initializing Database Pool ($host:$port/$dbName)...');

    try {
      _pool = MySQLConnectionPool(
        host: host,
        port: port,
        userName: user,
        password: password,
        databaseName: dbName,
        maxConnections: poolSize,
        secure: secure,
      );

      if (autoMigrate) {
        await _runMigration();
      }

      _logger.info('Database Pool initialized.');
    } catch (e) {
      _logger.severe('Failed to initialize database pool', e);
      rethrow;
    }
  }

  Future<void> _runMigration() async {
    _logger.info('Checking for migrations in scripts/ directory...');
    final dir = Directory('scripts');

    if (!dir.existsSync()) {
      _logger.warning(
        'Scripts directory not found at ${dir.path}. Skipping migration.',
      );
      return;
    }

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      final List<File> migrationFiles = entities.whereType<File>().where((f) => f.path.endsWith('.sql')).toList();

      // Sort files alphabetically to ensure execution order (e.g. v1 before v2)
      migrationFiles.sort((a, b) => a.path.compareTo(b.path));

      if (migrationFiles.isEmpty) {
        _logger.info('No .sql migration files found.');
        return;
      }

      _logger.info(
        'Found ${migrationFiles.length} migration files. Starting execution...',
      );

      for (final file in migrationFiles) {
        _logger.info('Applying migration file: ${file.path}');
        final sqlContent = await file.readAsString();
        final statements = sqlContent.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

        if (statements.isEmpty) {
          _logger.info('File ${file.path} is empty or has no statements.');
          continue;
        }

        for (final sql in statements) {
          if (sql.startsWith('--') && !sql.contains('\n')) {
            continue;
          }
          await _pool!.execute(sql);
        }
        _logger.info('Applied ${file.path} successfully.');
      }
      _logger.info('All migrations applied successfully.');
    } catch (e) {
      _logger.severe('Error applying migration', e);
      throw Exception('Migration failed: $e');
    }
  }

  MySQLConnectionPool get pool {
    if (_pool == null) {
      throw StateError(
        'DatabaseProvider not initialized. Call initialize() first.',
      );
    }
    return _pool!;
  }

  Future<IResultSet> execute(
    String query, [
    Map<String, dynamic>? params,
  ]) async {
    return pool.execute(query, params);
  }

  Future<void> close() async {
    await _pool?.close();
    _pool = null;
  }
}
