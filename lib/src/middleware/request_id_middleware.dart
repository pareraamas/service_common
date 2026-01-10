import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';

class RequestId {
  const RequestId(this.value);
  final String value;
  
  @override
  String toString() => value;
}

Middleware requestIdMiddleware() {
  return (handler) {
    return (context) async {
      // Check for existing header (from Gateway or upstream)
      final existingId = context.request.headers['x-request-id'];
      final requestId = existingId ?? const Uuid().v4();

      // Inject into context
      final updatedContext = context.provide<RequestId>(
        () => RequestId(requestId),
      );

      // Add to response headers as well for debugging
      final response = await handler(updatedContext);
      
      return response.copyWith(
        headers: {
          ...response.headers,
          'x-request-id': requestId,
        },
      );
    };
  };
}
