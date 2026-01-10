import 'package:dart_frog/dart_frog.dart';

Middleware securityHeadersMiddleware() {
  return (handler) {
    return (context) async {
      final response = await handler(context);

      return response.copyWith(
        headers: {
          ...response.headers,
          // Prevent sniffing content type
          'X-Content-Type-Options': 'nosniff',
          // Prevent clickjacking
          'X-Frame-Options': 'DENY',
          // Enable XSS protection filter in browser
          'X-XSS-Protection': '1; mode=block',
          // HSTS: Enforce HTTPS for 1 year (include subdomains)
          'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
          // CSP: Restrict sources (Basic API config)
          'Content-Security-Policy':
              "default-src 'self'; frame-ancestors 'none';",
          // Referrer Policy
          'Referrer-Policy': 'no-referrer',
          // Cache Control for sensitive data (defaulting to no-store for Auth API)
          'Cache-Control': 'no-store, no-cache, must-revalidate',
          'Pragma': 'no-cache',
        },
      );
    };
  };
}
