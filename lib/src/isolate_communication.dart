import 'dart:async';
import 'dart:isolate';
import 'dart:convert';

import 'isolate_models.dart';

/// Isolate communication protocol handler
class IsolateCommunication {
  /// Send port for sending messages to isolate
  final SendPort sendPort;

  /// Receive port for receiving messages from isolate
  final ReceivePort receivePort;

  /// Stream controller for incoming messages
  final StreamController<IsolateMessage> _messageController;

  /// Pending requests waiting for responses
  final Map<String, Completer<IsolateMessage>> _pendingRequests = {};

  /// Debug mode flag
  final bool debugMode;

  /// Communication timeout duration
  final Duration timeout;

  /// Message sequence counter
  int _messageSequence = 0;

  /// Communication active flag
  bool _isActive = true;

  /// Create isolate communication handler
  IsolateCommunication({
    required this.sendPort,
    required this.receivePort,
    this.debugMode = false,
    this.timeout = const Duration(minutes: 5),
  }) : _messageController = StreamController<IsolateMessage>.broadcast() {
    _setupMessageListener();
  }

  /// Stream of incoming messages
  Stream<IsolateMessage> get messageStream => _messageController.stream;

  /// Check if communication is active
  bool get isActive => _isActive;

  /// Send message and wait for response
  Future<IsolateMessage> sendRequest(
    MessageType type,
    Map<String, dynamic> data, {
    Duration? customTimeout,
  }) async {
    if (!_isActive) {
      throw StateError('Communication is not active');
    }

    final messageId = _generateMessageId();
    final message = IsolateMessage(
      id: messageId,
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    final completer = Completer<IsolateMessage>();
    _pendingRequests[messageId] = completer;

    if (debugMode) {
      print('[DEBUG] Sending request: ${message.type} (ID: ${message.id})');
    }

    try {
      // Send message
      sendPort.send(message.toJson());

      // Wait for response with timeout
      final effectiveTimeout = customTimeout ?? timeout;
      final response = await completer.future.timeout(
        effectiveTimeout,
        onTimeout: () {
          _pendingRequests.remove(messageId);
          throw TimeoutException(
            'Request timeout after ${effectiveTimeout.inSeconds}s',
            effectiveTimeout,
          );
        },
      );

      if (debugMode) {
        print(
            '[DEBUG] Received response: ${response.type} (ID: ${response.id})');
      }

      return response;
    } catch (e) {
      _pendingRequests.remove(messageId);
      if (debugMode) {
        print('[ERROR] Request failed: $e');
      }
      rethrow;
    }
  }

  /// Send message without waiting for response
  void sendMessage(
    MessageType type,
    Map<String, dynamic> data,
  ) {
    if (!_isActive) {
      if (debugMode) {
        print('[WARNING] Attempted to send message on inactive communication');
      }
      return;
    }

    final message = IsolateMessage(
      id: _generateMessageId(),
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    if (debugMode) {
      print('[DEBUG] Sending message: ${message.type} (ID: ${message.id})');
    }

    try {
      sendPort.send(message.toJson());
    } catch (e) {
      if (debugMode) {
        print('[ERROR] Failed to send message: $e');
      }
    }
  }

  /// Send response to a request
  void sendResponse(
    String requestId,
    MessageType type,
    Map<String, dynamic> data,
  ) {
    final message = IsolateMessage(
      id: requestId, // Use same ID as request for correlation
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    if (debugMode) {
      print('[DEBUG] Sending response: ${message.type} (ID: ${message.id})');
    }

    try {
      sendPort.send(message.toJson());
    } catch (e) {
      if (debugMode) {
        print('[ERROR] Failed to send response: $e');
      }
    }
  }

  /// Send error response
  void sendError(
    String requestId,
    String error,
    String? stackTrace,
  ) {
    sendResponse(
      requestId,
      MessageType.error,
      {
        'error': error,
        'stackTrace': stackTrace,
      },
    );
  }

  /// Close communication
  Future<void> close() async {
    if (!_isActive) return;

    _isActive = false;

    if (debugMode) {
      print('[DEBUG] Closing isolate communication');
    }

    // Complete all pending requests with error
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Communication closed'),
        );
      }
    }
    _pendingRequests.clear();

    // Close streams
    await _messageController.close();
    receivePort.close();
  }

  /// Setup message listener
  void _setupMessageListener() {
    receivePort.listen(
      (dynamic rawMessage) {
        try {
          _handleIncomingMessage(rawMessage);
        } catch (e, stackTrace) {
          if (debugMode) {
            print('[ERROR] Failed to handle incoming message: $e');
            print('[ERROR] Stack trace: $stackTrace');
          }
        }
      },
      onError: (error) {
        if (debugMode) {
          print('[ERROR] Receive port error: $error');
        }
      },
      onDone: () {
        if (debugMode) {
          print('[DEBUG] Receive port closed');
        }
        _isActive = false;
      },
    );
  }

  /// Handle incoming message
  void _handleIncomingMessage(dynamic rawMessage) {
    if (!_isActive) return;

    try {
      // Parse message
      final Map<String, dynamic> messageJson;
      if (rawMessage is String) {
        messageJson = jsonDecode(rawMessage) as Map<String, dynamic>;
      } else if (rawMessage is Map<String, dynamic>) {
        messageJson = rawMessage;
      } else {
        throw const FormatException('Invalid message format');
      }

      final message = IsolateMessage.fromJson(messageJson);

      if (debugMode) {
        print('[DEBUG] Received message: ${message.type} (ID: ${message.id})');
      }

      // Check if this is a response to a pending request
      final pendingCompleter = _pendingRequests.remove(message.id);
      if (pendingCompleter != null) {
        if (!pendingCompleter.isCompleted) {
          if (message.type == MessageType.error) {
            final error = message.data['error'] as String? ?? 'Unknown error';
            final stackTrace = message.data['stackTrace'] as String?;
            pendingCompleter.completeError(
              IsolateException(error, stackTrace),
            );
          } else {
            pendingCompleter.complete(message);
          }
        }
      } else {
        // This is a new message, add to stream
        if (!_messageController.isClosed) {
          _messageController.add(message);
        }
      }
    } catch (e, stackTrace) {
      if (debugMode) {
        print('[ERROR] Failed to parse incoming message: $e');
        print('[ERROR] Raw message: $rawMessage');
        print('[ERROR] Stack trace: $stackTrace');
      }
    }
  }

  /// Generate unique message ID
  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sequence = ++_messageSequence;
    return '${timestamp}_$sequence';
  }
}

/// Exception thrown by isolate operations
class IsolateException implements Exception {
  final String message;
  final String? stackTrace;

  const IsolateException(this.message, [this.stackTrace]);

  @override
  String toString() {
    if (stackTrace != null) {
      return 'IsolateException: $message\nStack trace: $stackTrace';
    }
    return 'IsolateException: $message';
  }
}

/// Isolate communication utilities
class IsolateCommunicationUtils {
  /// Create bidirectional communication between main isolate and worker
  static Future<IsolateCommunicationPair> createCommunicationPair({
    bool debugMode = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // Create receive ports
    final mainReceivePort = ReceivePort();
    final workerReceivePort = ReceivePort();

    // Create communication objects
    final mainCommunication = IsolateCommunication(
      sendPort: workerReceivePort.sendPort,
      receivePort: mainReceivePort,
      debugMode: debugMode,
      timeout: timeout,
    );

    final workerCommunication = IsolateCommunication(
      sendPort: mainReceivePort.sendPort,
      receivePort: workerReceivePort,
      debugMode: debugMode,
      timeout: timeout,
    );

    return IsolateCommunicationPair(
      main: mainCommunication,
      worker: workerCommunication,
    );
  }

  /// Serialize data for isolate communication
  static Map<String, dynamic> serializeData(Map<String, dynamic> data) {
    final serialized = <String, dynamic>{};

    for (final entry in data.entries) {
      serialized[entry.key] = _serializeValue(entry.value);
    }

    return serialized;
  }

  /// Deserialize data from isolate communication
  static Map<String, dynamic> deserializeData(Map<String, dynamic> data) {
    final deserialized = <String, dynamic>{};

    for (final entry in data.entries) {
      deserialized[entry.key] = _deserializeValue(entry.value);
    }

    return deserialized;
  }

  /// Serialize individual value
  static dynamic _serializeValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }

    if (value is List) {
      return value.map(_serializeValue).toList();
    }

    if (value is Map) {
      final serialized = <String, dynamic>{};
      for (final entry in value.entries) {
        serialized[entry.key.toString()] = _serializeValue(entry.value);
      }
      return serialized;
    }

    if (value is DateTime) {
      return {
        '_type': 'DateTime',
        'value': value.millisecondsSinceEpoch,
      };
    }

    // For other types, convert to string
    return {
      '_type': 'String',
      'value': value.toString(),
    };
  }

  /// Deserialize individual value
  static dynamic _deserializeValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }

    if (value is List) {
      return value.map(_deserializeValue).toList();
    }

    if (value is Map<String, dynamic>) {
      final type = value['_type'] as String?;
      if (type != null) {
        switch (type) {
          case 'DateTime':
            return DateTime.fromMillisecondsSinceEpoch(value['value'] as int);
          case 'String':
            return value['value'] as String;
        }
      }

      // Regular map
      final deserialized = <String, dynamic>{};
      for (final entry in value.entries) {
        deserialized[entry.key] = _deserializeValue(entry.value);
      }
      return deserialized;
    }

    return value;
  }
}

/// Pair of communication objects for main and worker isolates
class IsolateCommunicationPair {
  final IsolateCommunication main;
  final IsolateCommunication worker;

  const IsolateCommunicationPair({
    required this.main,
    required this.worker,
  });

  /// Close both communication channels
  Future<void> close() async {
    await Future.wait([
      main.close(),
      worker.close(),
    ]);
  }
}
