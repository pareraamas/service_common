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
    final autoMigrate =
        (_env['DB_AUTO_MIGRATE'] ?? 'true').toLowerCase() == 'true';
    final secure = (_env['DB_SECURE'] ?? 'true').toLowerCase() == 'true';

    _logger.info('Initializing Database Pool ($host:$port/$dbName)...');

    try {
      if (autoMigrate) {
        await _createDatabaseIfNotExists(
          host,
          port,
          user,
          password,
          dbName,
          secure,
        );
      }

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

  Future<void> _createDatabaseIfNotExists(
    String host,
    int port,
    String user,
    String password,
    String dbName,
    bool secure,
  ) async {
    _logger.info('Checking if database "$dbName" exists...');
    final conn = await MySQLConnection.createConnection(
      host: host,
      port: port,
      userName: user,
      password: password,
      databaseName: 'mysql',
      secure: secure,
    );

    try {
      await conn.connect();
      await conn.execute('CREATE DATABASE IF NOT EXISTS $dbName');
      _logger.info('Database "$dbName" checked/created.');
    } catch (e) {
      _logger.warning('Failed to create database automatically: $e');
    } finally {
      await conn.close();
    }
  }

  Future<void> _runMigration() async {
    _logger.info('Checking for migrations...');
    final file = File('scripts/migration.sql');

    if (!file.existsSync()) {
      _logger.warning(
        'Migration file not found at ${file.path}. Skipping migration.',
      );
      return;
    }

    try {
      final sqlContent = await file.readAsString();
      final statements = sqlContent
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (statements.isEmpty) {
        _logger.info('No migration statements found.');
        return;
      }

      _logger.info('Applying ${statements.length} migration statements...');

      for (final sql in statements) {
        if (sql.startsWith('--') && !sql.contains('\n')) {
          continue;
        }
        await _pool!.execute(sql);
      }
      _logger.info('Migration applied successfully.');
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
