import 'dart:io';
import 'package:path/path.dart' as p;

/// Performance logger for dataforge generation process
/// Handles separate logging of performance metrics to dedicated log files
class PerformanceLogger {
  static PerformanceLogger? _instance;
  File? _logFile;
  bool _isEnabled = false;
  final StringBuffer _buffer = StringBuffer();

  PerformanceLogger._();

  /// Get singleton instance of PerformanceLogger
  static PerformanceLogger get instance {
    _instance ??= PerformanceLogger._();
    return _instance!;
  }

  /// Initialize performance logging with output file path
  /// [outputPath] - Directory or file path where performance log should be written
  /// [enabled] - Whether performance logging is enabled
  Future<void> initialize(String outputPath, {bool enabled = true}) async {
    _isEnabled = enabled;

    if (!_isEnabled) {
      return;
    }

    try {
      // Determine log file path
      String logFilePath;
      if (FileSystemEntity.typeSync(outputPath) ==
          FileSystemEntityType.directory) {
        // If outputPath is directory, create log file in that directory
        logFilePath = p.join(outputPath, 'dataforge_performance.log');
      } else {
        // If outputPath is file, create log file in same directory
        final dir = p.dirname(outputPath);
        logFilePath = p.join(dir, 'dataforge_performance.log');
      }

      _logFile = File(logFilePath);

      // Create directory if it doesn't exist
      await _logFile!.parent.create(recursive: true);

      // Initialize log file with header
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!.writeAsString(
        '# Dataforge Performance Log\n'
        '# Generated at: $timestamp\n'
        '# Format: [PERF] <timestamp>: <message>\n'
        '\n',
      );

      print('📊 Performance logging enabled: ${_logFile!.path}');
    } catch (e) {
      print('⚠️  Failed to initialize performance logging: $e');
      _isEnabled = false;
    }
  }

  /// Log performance message
  /// [message] - Performance message to log
  void log(String message) {
    if (!_isEnabled || _logFile == null) {
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[PERF] $timestamp: $message\n';

    // Add to buffer for batch writing
    _buffer.write(logEntry);
  }

  /// Log performance message with timing
  /// [message] - Base message
  /// [duration] - Duration in milliseconds
  /// [details] - Optional additional details
  void logTiming(String message, int durationMs, {String? details}) {
    final baseMsg = '$message: ${durationMs}ms';
    final fullMsg = details != null ? '$baseMsg ($details)' : baseMsg;
    log(fullMsg);
  }

  /// Log performance message with emoji and timing
  /// [emoji] - Emoji prefix
  /// [message] - Base message
  /// [duration] - Duration in milliseconds
  /// [details] - Optional additional details
  void logTimingWithEmoji(String emoji, String message, int durationMs,
      {String? details}) {
    final baseMsg = '$emoji $message: ${durationMs}ms';
    final fullMsg = details != null ? '$baseMsg ($details)' : baseMsg;
    log(fullMsg);
  }

  /// Log performance breakdown with tree structure
  /// [title] - Main title
  /// [totalTime] - Total time in milliseconds
  /// [breakdown] - Map of stage name to time in milliseconds
  void logBreakdown(String title, int totalTimeMs, Map<String, int> breakdown) {
    log('🏁 $title: ${totalTimeMs}ms');

    final entries = breakdown.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isLast = i == entries.length - 1;
      final prefix = isLast ? '  └─' : '  ├─';
      final percentage = totalTimeMs > 0
          ? (entry.value / totalTimeMs * 100).toStringAsFixed(1)
          : '0.0';
      log('$prefix ${entry.key}: ${entry.value}ms ($percentage%)');
    }
  }

  /// Flush buffered log entries to file
  Future<void> flush() async {
    if (!_isEnabled || _logFile == null || _buffer.isEmpty) {
      return;
    }

    try {
      await _logFile!.writeAsString(_buffer.toString(), mode: FileMode.append);
      _buffer.clear();
    } catch (e) {
      print('⚠️  Failed to write performance log: $e');
    }
  }

  /// Close performance logger and flush remaining data
  Future<void> close() async {
    if (_isEnabled && _logFile != null) {
      await flush();

      // Add footer
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!.writeAsString(
        '\n# Log completed at: $timestamp\n',
        mode: FileMode.append,
      );

      print('📊 Performance log saved: ${_logFile!.path}');
    }

    _logFile = null;
    _isEnabled = false;
    _buffer.clear();
  }

  /// Check if performance logging is enabled
  bool get isEnabled => _isEnabled;

  /// Get current log file path
  String? get logFilePath => _logFile?.path;
}

/// Helper function to log performance with automatic flushing
/// [message] - Performance message to log
void logPerf(String message) {
  PerformanceLogger.instance.log(message);
}

/// Helper function to log performance timing with automatic flushing
/// [message] - Base message
/// [duration] - Duration in milliseconds
/// [details] - Optional additional details
void logPerfTiming(String message, int durationMs, {String? details}) {
  PerformanceLogger.instance.logTiming(message, durationMs, details: details);
}
