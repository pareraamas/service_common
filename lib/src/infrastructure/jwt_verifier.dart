import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' hide RSAPublicKey;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:service_common/src/infrastructure/cache_service.dart';

class JwtVerifier {
  JwtVerifier._internal();
  static final JwtVerifier _instance = JwtVerifier._internal();
  static JwtVerifier get instance => _instance;

  final Logger _logger = Logger('JwtVerifier');
  final DotEnv _env = DotEnv(includePlatformEnvironment: true)..load();

  String? _masterAuthUrl;

  // Cache keys in memory to reduce HTTP calls
  Map<String, String> _publicKeys = {};
  DateTime? _lastFetch;

  void initialize() {
    _masterAuthUrl = _env['MASTER_AUTH_URL'] ?? 'http://localhost:8080';
  }

  /// Verifies a JWT Token using Public Keys from Master Auth (JWKS)
  Future<JWT?> verify(String token) async {
    try {
      // 1. Decode header to get Key ID (kid)
      final unverified = JWT.decode(token);
      final kid = unverified.header?['kid'] as String?;

      if (kid == null) {
        _logger.warning('Token missing kid in header');
        return null;
      }

      // 2. Get Public Key
      String? publicKeyPem = await _getPublicKey(kid);

      if (publicKeyPem == null) {
        // Try fetching fresh keys
        await _fetchJwks();
        publicKeyPem = await _getPublicKey(kid);
      }

      if (publicKeyPem == null) {
        _logger.warning('Public key not found for kid: $kid');
        return null;
      }

      // 3. Verify Signature
      final jwt = JWT.verify(token, RSAPublicKey(publicKeyPem));
      return jwt;
    } on JWTExpiredException {
      _logger.info('Token expired');
      return null;
    } on JWTException catch (e) {
      _logger.warning('Invalid token: ${e.message}');
      return null;
    } catch (e) {
      _logger.severe('Token verification error', e);
      return null;
    }
  }

  Future<String?> _getPublicKey(String kid) async {
    // Check memory cache first
    if (_publicKeys.containsKey(kid)) {
      return _publicKeys[kid];
    }

    // Check shared cache (Redis)
    final cacheKey = 'jwks:key:$kid';
    final cachedKey = await CacheService.instance.get(cacheKey);
    if (cachedKey != null) {
      _publicKeys[kid] = cachedKey;
      return cachedKey;
    }

    return null;
  }

  Future<void> _fetchJwks() async {
    // Rate limit fetching (max once per minute)
    if (_lastFetch != null && DateTime.now().difference(_lastFetch!) < const Duration(minutes: 1)) {
      return;
    }

    try {
      final url = Uri.parse('$_masterAuthUrl/.well-known/jwks.json');
      _logger.info('Fetching JWKS from $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final keys = body['keys'] as List<dynamic>;

        for (final k in keys) {
          final keyData = k as Map<String, dynamic>;
          final kid = keyData['kid'] as String;
          // Reconstruct PEM or use parameters directly?
          // dart_jsonwebtoken expects PEM for RSAPublicKey usually,
          // or we can construct it if we had n and e.
          // However, our Master Auth JWKS implementation returns n and e.
          // We need to convert JWK (n, e) to PEM.

          final n = keyData['n'] as String;
          final e = keyData['e'] as String;

          final pem = _jwkToPem(n, e);

          _publicKeys[kid] = pem;

          // Cache in Redis for other services
          await CacheService.instance.set(
            'jwks:key:$kid',
            pem,
            expiration: const Duration(hours: 24),
          );
        }
        _lastFetch = DateTime.now();
        _logger.info('JWKS fetched and cached (${keys.length} keys)');
      } else {
        _logger.warning('Failed to fetch JWKS: ${response.statusCode}');
      }
    } catch (e) {
      _logger.severe('Error fetching JWKS', e);
    }
  }

  String _jwkToPem(String n, String e) {
    // n and e are Base64Url encoded
    final modulus = BigInt.parse(
      _base64UrlDecode(n).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    final exponent = BigInt.parse(
      _base64UrlDecode(e).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );

    // Use PointyCastle directly to create key, then BasicUtils to encode to PEM
    final rsaPublicKey = pc.RSAPublicKey(modulus, exponent);
    return CryptoUtils.encodeRSAPublicKeyToPem(rsaPublicKey);
  }

  Uint8List _base64UrlDecode(String input) {
    var output = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (output.length % 4) {
      case 0:
        break;
      case 2:
        output += '==';
        break;
      case 3:
        output += '=';
        break;
      default:
        throw Exception('Illegal base64url string!');
    }
    return base64Decode(output);
  }
}
