import 'dart:async';
import 'dart:isolate';

import 'isolate_models.dart';
import 'parser.dart';
import 'writer.dart';
import 'performance_logger.dart';

/// Single Isolate worker for processing file batches
class IsolateWorker {
  /// Worker identifier
  final String workerId;

  /// Isolate instance
  Isolate? _isolate;

  /// Send port to communicate with isolate
  SendPort? _sendPort;

  /// Receive port for receiving messages from isolate
  late ReceivePort _receivePort;

  /// Current worker status
  WorkerStatus _status = WorkerStatus.initializing;

  /// Worker statistics
  final WorkerStats stats = WorkerStats();

  /// Pending tasks map
  final Map<String, Completer<List<String>>> _pendingTasks = {};
  Completer<void>? _initCompleter;

  /// Debug mode flag
  final bool debugMode;

  /// Create an isolate worker
  IsolateWorker({
    required this.workerId,
    this.debugMode = false,
  });

  /// Get current worker status
  WorkerStatus get status => _status;

  /// Check if worker is available for new tasks
  bool get isAvailable => _status == WorkerStatus.idle;

  /// Start the isolate worker
  Future<void> start() async {
    if (_status != WorkerStatus.initializing) {
      throw StateError(
          'Worker $workerId is already started or in invalid state');
    }

    try {
      _receivePort = ReceivePort();

      if (debugMode) {
        print('[DEBUG] Starting isolate worker $workerId');
      }

      // Spawn isolate with entry point
      _isolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort.sendPort,
        debugName: 'DataForgeWorker-$workerId',
      );

      // Listen for messages from isolate
      _receivePort.listen(_handleMessage);

      // Wait for initialization complete message
      _initCompleter = Completer<void>();

      // Wait for send port to be available (isolate will send it)
      await _initCompleter!.future.timeout(
        Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
            'Worker initialization timeout', Duration(seconds: 5)),
      );

      // Send initialization message to isolate with workerId and debugMode
      if (_sendPort != null) {
        final initMessage = IsolateMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: MessageType.initializeWorker,
          data: {
            'workerId': workerId,
            'debugMode': debugMode,
          },
          taskId: 'init_$workerId',
          timestamp: DateTime.now(),
        );
        _sendPort!.send(initMessage.toJson());

        if (debugMode) {
          print(
              '[DEBUG] Sent initialization message to isolate worker $workerId');
        }
      }

      if (debugMode) {
        print('[DEBUG] Worker $workerId started successfully');
      }

      _status = WorkerStatus.idle;
    } catch (e) {
      _status = WorkerStatus.error;
      if (debugMode) {
        print('[ERROR] Failed to start worker $workerId: $e');
      }
      rethrow;
    }
  }

  /// Process a batch of files
  Future<List<String>> processBatch(
      List<String> filePaths, String projectRoot, bool autoModify) async {
    if (_status != WorkerStatus.idle) {
      throw StateError('Worker $workerId is not available (status: $_status)');
    }

    if (_sendPort == null) {
      throw StateError('Worker $workerId send port is not available');
    }

    final taskId =
        'task_${DateTime.now().millisecondsSinceEpoch}_${filePaths.hashCode}';
    final completer = Completer<List<String>>();
    _pendingTasks[taskId] = completer;
    _status = WorkerStatus.busy;

    final startTime = DateTime.now();

    if (debugMode) {
      print(
          '[DEBUG] Worker $workerId processing batch of ${filePaths.length} files');
    }

    try {
      // Send processing task to isolate
      final message = IsolateMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: MessageType.processBatch,
        data: {
          'filePaths': filePaths,
          'projectRoot': projectRoot,
          'debugMode': debugMode,
          'autoModify': autoModify,
        },
        taskId: taskId,
        timestamp: DateTime.now(),
      );

      _sendPort!.send(message.toJson());

      // Wait for completion
      final result = await completer.future;

      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;
      stats.updateStats(filePaths.length, processingTime);

      if (debugMode) {
        print(
            '[DEBUG] Worker $workerId completed batch in ${processingTime}ms');
      }

      _status = WorkerStatus.idle;
      return result;
    } catch (e) {
      _status = WorkerStatus.error;
      _pendingTasks.remove(taskId);
      if (debugMode) {
        print('[ERROR] Worker $workerId failed to process batch: $e');
      }
      rethrow;
    }
  }

  /// Stop the isolate worker
  Future<void> stop() async {
    if (_status == WorkerStatus.shutdown) {
      return;
    }

    _status = WorkerStatus.shutdown;

    if (debugMode) {
      print('[DEBUG] Stopping worker $workerId');
    }

    try {
      // Send shutdown message if send port is available
      if (_sendPort != null) {
        final message = IsolateMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: MessageType.shutdown,
          data: {},
          timestamp: DateTime.now(),
        );
        _sendPort!.send(message.toJson());
      }

      // Wait a bit for graceful shutdown
      await Future.delayed(Duration(milliseconds: 100));

      // Kill isolate if still running
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;

      // Close receive port
      _receivePort.close();

      // Complete any pending tasks with empty results
      for (final completer in _pendingTasks.values) {
        if (!completer.isCompleted) {
          completer.complete([]);
        }
      }
      _pendingTasks.clear();

      if (debugMode) {
        print('[DEBUG] Worker $workerId stopped');
      }
    } catch (e) {
      if (debugMode) {
        print('[ERROR] Error stopping worker $workerId: $e');
      }
    }
  }

  /// Handle messages from isolate
  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> messageData = message as Map<String, dynamic>;
      final isolateMessage = IsolateMessage.fromJson(messageData);

      switch (isolateMessage.type) {
        case MessageType.initializeWorker:
          _sendPort = isolateMessage.data['sendPort'] as SendPort;
          if (debugMode) {
            print('[DEBUG] Worker $workerId initialized');
          }
          // Complete initialization
          if (_initCompleter != null && !_initCompleter!.isCompleted) {
            _initCompleter!.complete();
          }
          break;

        case MessageType.batchComplete:
          final taskId = isolateMessage.taskId;
          if (taskId != null && _pendingTasks.containsKey(taskId)) {
            final result =
                List<String>.from(isolateMessage.data['result'] as List);

            // Extract performance data from isolate
            final perfData = isolateMessage.data['perfData'] as List<dynamic>?;
            final totalProcessingTime =
                isolateMessage.data['totalProcessingTime'] as int?;

            // Log performance data if available
            if (perfData != null && perfData.isNotEmpty) {
              _logIsolatePerformanceData(perfData, totalProcessingTime);
            }

            _pendingTasks[taskId]!.complete(result);
            _pendingTasks.remove(taskId);
          }
          break;

        case MessageType.workerError:
          final taskId = isolateMessage.taskId;
          final error = isolateMessage.data['error'] as String;
          if (taskId != null && _pendingTasks.containsKey(taskId)) {
            _pendingTasks[taskId]!.completeError(Exception(error));
            _pendingTasks.remove(taskId);
          }
          _status = WorkerStatus.error;
          if (debugMode) {
            print('[ERROR] Worker $workerId error: $error');
          }
          break;

        default:
          if (debugMode) {
            print(
                '[DEBUG] Worker $workerId received unknown message type: ${isolateMessage.type}');
          }
      }
    } catch (e) {
      if (debugMode) {
        print('[ERROR] Worker $workerId failed to handle message: $e');
      }
    }
  }

  /// Isolate entry point
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    bool debugMode = false;
    String workerId = 'unknown';

    // Send back the send port for communication
    final initMessage = IsolateMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: MessageType.initializeWorker,
      data: {'sendPort': receivePort.sendPort},
      taskId: 'init',
      timestamp: DateTime.now(),
    );
    mainSendPort.send(initMessage.toJson());

    receivePort.listen((message) async {
      try {
        final Map<String, dynamic> messageData =
            message as Map<String, dynamic>;
        final isolateMessage = IsolateMessage.fromJson(messageData);

        switch (isolateMessage.type) {
          case MessageType.initializeWorker:
            workerId = isolateMessage.data['workerId'] as String;
            debugMode = isolateMessage.data['debugMode'] as bool;
            if (debugMode) {
              print('[DEBUG] Isolate worker $workerId initialized');
            }
            break;

          case MessageType.processBatch:
            await _processBatchInIsolate(
                isolateMessage, mainSendPort, debugMode);
            break;

          case MessageType.shutdown:
            if (debugMode) {
              print('[DEBUG] Isolate worker $workerId shutting down');
            }
            receivePort.close();
            break;

          default:
            if (debugMode) {
              print(
                  '[DEBUG] Isolate worker $workerId received unknown message: ${isolateMessage.type}');
            }
        }
      } catch (e) {
        // Send error back to main isolate
        final errorMessage = IsolateMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: MessageType.workerError,
          data: {'error': e.toString()},
          taskId: null,
          timestamp: DateTime.now(),
        );
        mainSendPort.send(errorMessage.toJson());
      }
    });
  }

  /// Process batch of files in isolate
  static Future<void> _processBatchInIsolate(
    IsolateMessage message,
    SendPort mainSendPort,
    bool debugMode,
  ) async {
    final taskId = message.taskId;
    final filePaths = List<String>.from(message.data['filePaths'] as List);
    final projectRoot = message.data['projectRoot'] as String;
    final autoModify = message.data['autoModify'] as bool;

    final startTime = DateTime.now();

    try {
      final results = <String>[];

      if (debugMode) {
        print(
            '[DEBUG] Isolate $taskId started processing ${filePaths.length} files at ${startTime.toIso8601String()}');
      }

      int processedCount = 0;
      final List<Map<String, dynamic>> perfData = [];

      for (final filePath in filePaths) {
        try {
          if (debugMode && processedCount % 10 == 0) {
            print(
                '[DEBUG] Isolate $taskId processing file ${processedCount + 1}/${filePaths.length}: $filePath');
          }

          final fileStartTime = DateTime.now();

          // Parse the file
          final parseStartTime = DateTime.now();
          final parser = Parser(filePath);
          final parseRes = parser.parseDartFile();
          final parseEndTime = DateTime.now();
          final parseTime =
              parseEndTime.difference(parseStartTime).inMilliseconds;

          if (parseRes != null) {
            // Generate code (write phase)
            final writeStartTime = DateTime.now();
            final writer = Writer(
              parseRes,
              projectRoot: projectRoot,
              debugMode: debugMode,
              autoModify: autoModify,
            );
            final generatedFile = await writer.writeCodeAsync();
            final writeEndTime = DateTime.now();
            final writeTime =
                writeEndTime.difference(writeStartTime).inMilliseconds;

            if (generatedFile.isNotEmpty) {
              results.add(generatedFile);

              // Record performance data for this file
              final totalTime =
                  writeEndTime.difference(fileStartTime).inMilliseconds;
              perfData.add({
                'filePath': filePath,
                'outputPath': generatedFile,
                'parseTime': parseTime,
                'writeTime': writeTime,
                'totalTime': totalTime,
                'parseStartTime': parseStartTime.toIso8601String(),
                'parseEndTime': parseEndTime.toIso8601String(),
                'writeStartTime': writeStartTime.toIso8601String(),
                'writeEndTime': writeEndTime.toIso8601String(),
              });
            }
          }
          processedCount++;
        } catch (e) {
          if (debugMode) {
            print('[ERROR] Failed to process file $filePath: $e');
          }
          processedCount++;
          // Continue processing other files
        }
      }

      final endTime = DateTime.now();
      final processingTime = endTime.difference(startTime).inMilliseconds;

      if (debugMode) {
        print(
            '[DEBUG] Isolate $taskId completed processing ${filePaths.length} files in ${processingTime}ms, generated ${results.length} files');
      }

      // Send results back with performance data
      final resultMessage = IsolateMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: MessageType.batchComplete,
        data: {
          'result': results,
          'perfData': perfData,
          'totalProcessingTime': processingTime,
        },
        taskId: taskId,
        timestamp: DateTime.now(),
      );
      mainSendPort.send(resultMessage.toJson());

      if (debugMode) {
        print('[DEBUG] Isolate $taskId sent results back to main isolate');
      }
    } catch (e) {
      // Send error back
      final errorMessage = IsolateMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: MessageType.workerError,
        data: {'error': e.toString()},
        taskId: taskId,
        timestamp: DateTime.now(),
      );
      mainSendPort.send(errorMessage.toJson());
    }
  }

  /// Log performance data received from isolate worker
  void _logIsolatePerformanceData(
      List<dynamic> perfData, int? totalProcessingTime) {
    final perfLogger = PerformanceLogger.instance;

    for (final data in perfData) {
      final fileData = data as Map<String, dynamic>;
      final filePath = fileData['filePath'] as String;
      final parseTime = fileData['parseTime'] as int;
      final writeTime = fileData['writeTime'] as int;
      final totalTime = fileData['totalTime'] as int;

      // Log detailed timing for each file
      perfLogger.logTiming('Parse phase for $filePath', parseTime);
      perfLogger.logTiming('Write phase for $filePath', writeTime);
      perfLogger.logTiming('Total processing for $filePath', totalTime);
    }

    // Note: Isolate batch processing time is not logged here to avoid duplication
    // The main process already logs overall timing statistics
  }
}
