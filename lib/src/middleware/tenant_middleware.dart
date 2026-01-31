import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class TenantContext {
  const TenantContext(this.tenantId);
  final String tenantId;
}

Middleware tenantMiddleware() {
  return (handler) {
    return (context) async {
      final claims = context.read<JWT>();
      final payload = claims.payload;
      if (payload is! Map<String, dynamic>) {
        return Response.json(
          statusCode: 401,
          body: {'success': false, 'message': 'Invalid token payload'},
        );
      }

      final tenantId = payload['tenant_id'] as String?;
      if (tenantId == null || tenantId.isEmpty) {
        return Response.json(
          statusCode: 403,
          body: {'success': false, 'message': 'Missing tenant_id'},
        );
      }

      final headerTenantId = context.request.headers['X-Tenant-ID'];
      if (headerTenantId != null && headerTenantId.isNotEmpty) {
        if (headerTenantId != tenantId) {
          return Response.json(
            statusCode: 403,
            body: {'success': false, 'message': 'Tenant mismatch'},
          );
        }
      }

      return handler(context.provide<TenantContext>(() => TenantContext(tenantId)));
    };
  };
}

