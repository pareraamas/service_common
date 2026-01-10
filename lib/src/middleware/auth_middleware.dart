import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:service_common/src/infrastructure/jwt_verifier.dart';

Handler authMiddleware(Handler handler) {
  return (context) async {
    final headers = context.request.headers;
    
    // 1. Check Client ID (Basic Auth for Service-to-Service tracking)
    // Note: We might want to make this optional for public endpoints, 
    // but usually in microservices mesh we want to know who is calling.
    // For now, let's keep it simple: Authorization Bearer token is the main thing.

    final authHeader = headers['Authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.json(
        statusCode: 401,
        body: {
          'success': false,
          'message': 'Missing or invalid Authorization header',
        },
      );
    }

    final token = authHeader.substring(7); // Remove 'Bearer '

    // 2. Verify Token
    // This will fetch JWKS if needed
    final jwt = await JwtVerifier.instance.verify(token);

    if (jwt == null) {
      return Response.json(
        statusCode: 401,
        body: {
          'success': false,
          'message': 'Invalid or expired token',
        },
      );
    }

    // 3. Check Device ID Binding
    final payload = jwt.payload as Map<String, dynamic>;
    final tokenDeviceId = payload['device_id'] as String?;
    final headerDeviceId = headers['X-Device-ID'];

    if (tokenDeviceId != null) {
      if (headerDeviceId == null) {
        return Response.json(
          statusCode: 400,
          body: {'success': false, 'message': 'Missing X-Device-ID header'},
        );
      }
      if (tokenDeviceId != headerDeviceId) {
        return Response.json(
          statusCode: 401,
          body: {'success': false, 'message': 'Device ID mismatch'},
        );
      }
    }

    // 4. Inject User Context
    // We can provide the whole JWT object or just claims
    return handler(context.provide<JWT>(() => jwt));
  };
}
