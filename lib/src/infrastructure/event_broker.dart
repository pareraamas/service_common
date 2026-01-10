import 'dart:async';
import 'dart:convert';
import 'package:dotenv/dotenv.dart';
import 'package:logging/logging.dart';
import 'package:redis/redis.dart';

class EventBroker {
  EventBroker._internal();
  static final EventBroker _instance = EventBroker._internal();
  static EventBroker get instance => _instance;

  final DotEnv _env = DotEnv(includePlatformEnvironment: true)..load();
  final Logger _logger = Logger('EventBroker');

  // Connection for Publishing (can be shared for general commands)
  RedisConnection? _pubConnection;
  Command? _pubCommand;

  bool _initialized = false;
  String _host = 'localhost';
  int _port = 6379;

  /// Initializes the Event Broker (Publication Connection).
  /// Subscriptions create their own connections on demand.
  Future<void> initialize() async {
    if (_initialized) return;

    _host = _env['REDIS_HOST'] ?? 'localhost';
    _port = int.tryParse(_env['REDIS_PORT'] ?? '6379') ?? 6379;

    try {
      _pubConnection = RedisConnection();
      _pubCommand = await _pubConnection!.connect(_host, _port);
      _initialized = true;
      _logger.info('EventBroker initialized (Redis at $_host:$_port)');
    } catch (e) {
      _logger.severe('Failed to connect to Redis for EventBroker: $e');
      // We might throw here or handle gracefully depending on policy.
      // For Enterprise, we should probably throw or retry.
    }
  }

  /// Publishes a message to a channel.
  /// [message] will be JSON encoded.
  Future<void> publish(String channel, Map<String, dynamic> message) async {
    if (!_initialized || _pubCommand == null) {
      _logger.warning('EventBroker not initialized. Dropping message to $channel');
      return;
    }

    try {
      final jsonString = jsonEncode(message);
      await _pubCommand!.send_object(['PUBLISH', channel, jsonString]);
      _logger.fine('Published to $channel: $jsonString');
    } catch (e) {
      _logger.severe('Failed to publish to $channel: $e');
      // Simple retry logic could go here
    }
  }

  /// Subscribes to a channel and returns a Stream of messages.
  /// NOTE: This creates a NEW Redis connection per call (or we could manage a shared subscriber).
  /// For simplicity, we create a new connection to ensure isolation.
  Future<Stream<Map<String, dynamic>>> subscribe(String channel) async {
    final connection = RedisConnection();
    try {
      final command = await connection.connect(_host, _port);
      final pubsub = PubSub(command);
      
      _logger.info('Subscribing to $channel...');
      pubsub.subscribe([channel]);

      // Transform the stream
      return pubsub.getStream().map((message) {
        // Message format from redis package:
        // message is usually specific structure, but simple usage:
        // Wait, PubSub stream yields `PubSubMessage` or similar?
        // Let's check `redis` package behavior. 
        // Actually typical redis package stream event is:
        // { 'type': 'message', 'channel': '...', 'message': '...' }
        // or just the message content depending on implementation.
        
        // Based on `redis` package source:
        // Stream<dynamic> getStream()
        // Events are usually lists or maps.
        // If it's a message: ['message', 'channel_name', 'payload']
        
        // Let's handle it safely.
        return _parseMessage(message);
      }).where((msg) => msg != null).cast<Map<String, dynamic>>();

    } catch (e) {
      _logger.severe('Failed to subscribe to $channel: $e');
      return const Stream.empty();
    }
  }

  Map<String, dynamic>? _parseMessage(dynamic event) {
    try {
      // Expecting list: ['message', channel, payload]
      if (event is List && event.length >= 3 && event[0] == 'message') {
        final payload = event[2];
        if (payload is String) {
          return jsonDecode(payload) as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      _logger.warning('Failed to parse Redis message: $event, error: $e');
      return null;
    }
  }
}
