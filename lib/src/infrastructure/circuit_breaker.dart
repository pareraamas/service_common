import 'dart:async';
import 'package:logging/logging.dart';

enum CircuitState { closed, open, halfOpen }

class CircuitBreaker {
  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
    String name = 'CircuitBreaker',
  }) : _logger = Logger(name);

  final int failureThreshold;
  final Duration resetTimeout;
  final Logger _logger;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;

  CircuitState get state => _state;

  /// Executes an async action with circuit breaker protection.
  Future<T> execute<T>(Future<T> Function() action) async {
    if (_state == CircuitState.open) {
      if (_lastFailureTime != null &&
          DateTime.now().difference(_lastFailureTime!) > resetTimeout) {
        _transitionToHalfOpen();
      } else {
        _logger.warning('Circuit is OPEN. Fast failing.');
        throw CircuitBreakerOpenException();
      }
    }

    try {
      final result = await action();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure(e);
      rethrow;
    }
  }

  void _onSuccess() {
    if (_state == CircuitState.halfOpen) {
      _transitionToClosed();
    } else if (_state == CircuitState.closed) {
      _failureCount = 0;
    }
  }

  void _onFailure(Object error) {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    _logger.warning('Failure detected. Count: $_failureCount. Error: $error');

    if (_state == CircuitState.halfOpen || _failureCount >= failureThreshold) {
      _transitionToOpen();
    }
  }

  void _transitionToOpen() {
    _state = CircuitState.open;
    _logger.severe('Circuit state changed to OPEN. All requests will fail fast for ${resetTimeout.inSeconds}s.');
  }

  void _transitionToHalfOpen() {
    _state = CircuitState.halfOpen;
    _logger.info('Circuit state changed to HALF-OPEN. Testing next request.');
  }

  void _transitionToClosed() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _lastFailureTime = null;
    _logger.info('Circuit state changed to CLOSED. Service recovered.');
  }
}

class CircuitBreakerOpenException implements Exception {
  @override
  String toString() => 'CircuitBreakerOpenException: Service is temporarily unavailable due to high failure rate.';
}
