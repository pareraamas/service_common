# Service Common

Shared Library (Shared Kernel) untuk ekosistem Microservices Parera. Paket ini berisi logika infrastruktur, middleware, dan utilitas yang digunakan berulang kali di berbagai service.

## 📦 Fitur

### 1. Infrastructure
*   **DatabaseProvider:** Wrapper singleton untuk koneksi MySQL dengan pooling (`mysql_client_plus`).
*   **CacheService:** Abstraksi caching (Redis dengan fallback In-Memory).
*   **EventBroker:** Pub/Sub client sederhana menggunakan Redis untuk Event-Driven Architecture.
*   **CircuitBreaker:** Pola Resilience untuk mencegah kegagalan beruntun saat dependensi down.
*   **JwtVerifier:** Verifikasi token JWT terpusat.

### 2. Middleware
*   **AuthMiddleware:** Memvalidasi header Authorization dan menyuntikkan objek User ke context.
*   **RequestLogger:** Logging HTTP request/response yang rapi dengan durasi eksekusi.
*   **RequestId:** Menghasilkan dan mempropagasikan `X-Request-ID` untuk Distributed Tracing.
*   **SecurityHeaders:** Menambahkan header keamanan standar (HSTS, X-Frame-Options, dll).

### 3. Utils
*   **ServiceResponse:** Standarisasi format respon API JSON (`success`, `message`, `data`).

## 🚀 Cara Penggunaan

Tambahkan ke `pubspec.yaml` di service Anda:

```yaml
dependencies:
  service_common:
    path: ../packages/service_common
```

### Inisialisasi (di `_middleware.dart`)

```dart
Handler middleware(Handler handler) {
  return (context) async {
    // Init Infra
    await DatabaseProvider.instance.initialize();
    await CacheService.instance.initialize();
    await EventBroker.instance.initialize(); // Jika butuh Pub/Sub
    
    // Pipeline
    final pipeline = const Pipeline()
      .addMiddleware(requestLoggerMiddleware())
      .addMiddleware(requestIdMiddleware()) // Wajib untuk tracing
      .addMiddleware(authMiddleware);

    return pipeline.addHandler(handler)(context);
  };
}
```

### Menggunakan Circuit Breaker

```dart
final cb = CircuitBreaker(name: 'InventoryClient');

try {
  await cb.execute(() async {
    // Panggil external service
    final response = await http.get(...);
    if (response.statusCode >= 500) throw Exception('Server Error');
    return response;
  });
} catch (e) {
  // Handle jika Circuit Open atau Request Gagal
}
```

### Pub/Sub Event

```dart
// Publish
await EventBroker.instance.publish('ORDER_CREATED', {'id': '123'});

// Subscribe
final stream = await EventBroker.instance.subscribe('ORDER_CREATED');
stream.listen((event) {
  print('Event received: $event');
});
```
