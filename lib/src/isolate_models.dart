import 'dart:async';

/// Message types for Isolate communication
enum MessageType {
  /// Initialize worker isolate
  initializeWorker,

  /// Process a batch of files
  processBatch,

  /// Batch processing completed
  batchComplete,

  /// Worker error occurred
  workerError,

  /// Shutdown worker isolate
  shutdown,

  /// Error response
  error,

  /// Success response
  success,
}

/// Message format for Isolate communication
class IsolateMessage {
  /// Unique message identifier
  final String id;

  /// Message type
  final MessageType type;

  /// Message data payload
  final Map<String, dynamic> data;

  /// Optional task identifier
  final String? taskId;

  /// Message timestamp
  final DateTime timestamp;

  /// Create an isolate message
  const IsolateMessage({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    this.taskId,
  });

  /// Convert message to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'data': data,
      'taskId': taskId,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Create message from JSON
  factory IsolateMessage.fromJson(Map<String, dynamic> json) {
    return IsolateMessage(
      id: json['id'] as String,
      type: MessageType.values[json['type'] as int],
      data: json['data'] as Map<String, dynamic>,
      taskId: json['taskId'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}

/// Work task for file processing
class WorkTask {
  /// List of file paths to process
  final List<String> filePaths;

  /// Project root directory
  final String projectRoot;

  /// Enable debug mode
  final bool debugMode;

  /// Enable auto modification
  final bool autoModify;

  /// Task completion completer
  final Completer<List<String>> completer;

  /// Unique task identifier
  final String taskId;

  /// Create a work task
  WorkTask({
    required this.filePaths,
    required this.projectRoot,
    required this.debugMode,
    required this.autoModify,
    required this.taskId,
  }) : completer = Completer<List<String>>();

  /// Convert task to data map for serialization
  Map<String, dynamic> toData() {
    return {
      'filePaths': filePaths,
      'projectRoot': projectRoot,
      'debugMode': debugMode,
      'autoModify': autoModify,
      'taskId': taskId,
    };
  }

  /// Create task from data map
  factory WorkTask.fromData(Map<String, dynamic> data) {
    return WorkTask(
      filePaths: List<String>.from(data['filePaths'] as List),
      projectRoot: data['projectRoot'] as String,
      debugMode: data['debugMode'] as bool,
      autoModify: data['autoModify'] as bool,
      taskId: data['taskId'] as String,
    );
  }
}

/// Worker status enumeration
enum WorkerStatus {
  /// Worker is initializing
  initializing,

  /// Worker is idle and ready for tasks
  idle,

  /// Worker is processing tasks
  busy,

  /// Worker encountered an error
  error,

  /// Worker is shutting down
  shutdown,
}

/// Worker statistics for monitoring
class WorkerStats {
  /// Total tasks processed
  int tasksProcessed = 0;

  /// Total files processed
  int filesProcessed = 0;

  /// Total processing time in milliseconds
  int totalProcessingTime = 0;

  /// Average processing time per file
  double get averageProcessingTime =>
      filesProcessed > 0 ? totalProcessingTime / filesProcessed : 0.0;

  /// Update statistics with new task results
  void updateStats(int fileCount, int processingTime) {
    tasksProcessed++;
    filesProcessed += fileCount;
    totalProcessingTime += processingTime;
  }

  /// Reset statistics
  void reset() {
    tasksProcessed = 0;
    filesProcessed = 0;
    totalProcessingTime = 0;
  }

  @override
  String toString() {
    return 'WorkerStats(tasks: $tasksProcessed, files: $filesProcessed, avgTime: ${averageProcessingTime.toStringAsFixed(2)}ms)';
  }
}
