import 'package:dart_frog/dart_frog.dart';

class ServiceResponse {
  static Response success({
    String message = 'Success',
    dynamic data,
    int statusCode = 200,
  }) {
    return Response.json(
      statusCode: statusCode,
      body: {
        'success': true,
        'message': message,
        if (data != null) 'data': data,
      },
    );
  }

  static Response error({
    String message = 'Error',
    String? error,
    int statusCode = 400,
  }) {
    return Response.json(
      statusCode: statusCode,
      body: {
        'success': false,
        'message': message,
        if (error != null) 'error': error,
      },
    );
  }
}
