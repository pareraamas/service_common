import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:service_common/src/middleware/request_id_middleware.dart';

bool _loggerInitialized = false;

void _setupLogger() {
  if (_loggerInitialized) return;

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('[${record.level.name}] ${record.time}: ${record.message}');
    if (record.error != null) {
      // ignore: avoid_print
      print('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      // ignore: avoid_print
      print('Stack Trace:\n${record.stackTrace}');
    }
  });
  _loggerInitialized = true;
}

Middleware requestLoggerMiddleware() {
  _setupLogger();
  final logger = Logger('RequestLogger');

  return (handler) {
    return (context) async {
      final stopwatch = Stopwatch()..start();
      final request = context.request;
      
      // Try to get Request ID
      String requestId = '';
      try {
        final rid = context.read<RequestId>();
        requestId = '[${rid.value}] ';
      } catch (_) {
        // Ignored if not provided
      }

      // Log Request
      logger.info('$requestId--> ${request.method.value} ${request.uri.path}');

      Response response;
      try {
        response = await handler(context);
      } catch (e) {
        stopwatch.stop();
        logger.severe(
          '$requestId<-- ${request.method.value} ${request.uri.path} - Error: $e (${stopwatch.elapsedMilliseconds}ms)',
        );
        rethrow;
      }

      stopwatch.stop();
      logger.info(
        '$requestId<-- ${request.method.value} ${request.uri.path} - ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)',
      );

      return response;
    };
  };
}
