import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'isolate_models.dart';
import 'isolate_worker.dart';
import 'file_grouping_strategy.dart';

/// Isolate worker pool for managing concurrent file processing
class IsolateWorkerPool {
  /// Number of worker isolates
  final int workerCount;

  /// List of worker isolates
  final List<IsolateWorker> _workers = [];

  /// Task queue for pending work
  final Queue<WorkTask> _taskQueue = Queue<WorkTask>();

  /// Debug mode flag
  final bool debugMode;

  /// Pool initialization status
  bool _isInitialized = false;

  /// Pool shutdown status
  bool _isShutdown = false;

  /// Task processing active flag
  bool _isProcessing = false;

  /// Create isolate worker pool
  ///
  /// [workerCount] defaults to CPU core count if not specified
  IsolateWorkerPool({
    int? workerCount,
    this.debugMode = false,
  }) : workerCount = workerCount ?? Platform.numberOfProcessors;

  /// Check if pool is initialized
  bool get isInitialized => _isInitialized;

  /// Check if pool is shutdown
  bool get isShutdown => _isShutdown;

  /// Get pool statistics
  Map<String, dynamic> get statistics {
    final totalStats = WorkerStats();
    for (final worker in _workers) {
      totalStats.tasksProcessed += worker.stats.tasksProcessed;
      totalStats.filesProcessed += worker.stats.filesProcessed;
      totalStats.totalProcessingTime += worker.stats.totalProcessingTime;
    }

    return {
      'workerCount': workerCount,
      'totalTasksProcessed': totalStats.tasksProcessed,
      'totalFilesProcessed': totalStats.filesProcessed,
      'totalProcessingTime': totalStats.totalProcessingTime,
      'averageProcessingTime': totalStats.averageProcessingTime,
      'queuedTasks': _taskQueue.length,
      'availableWorkers': _workers.where((w) => w.isAvailable).length,
    };
  }

  /// Initialize the worker pool
  Future<void> initialize() async {
    if (_isInitialized) {
      throw StateError('Worker pool is already initialized');
    }

    if (_isShutdown) {
      throw StateError('Worker pool has been shutdown');
    }

    final startTime = DateTime.now();
    if (debugMode) {
      print('[DEBUG] Initializing worker pool with $workerCount workers');
    }

    try {
      // Create and start workers
      final workerFutures = <Future<void>>[];
      for (int i = 0; i < workerCount; i++) {
        final worker = IsolateWorker(
          workerId: 'worker_$i',
          debugMode: debugMode,
        );
        _workers.add(worker);
        workerFutures.add(worker.start());
      }

      // Wait for all workers to start
      await Future.wait(workerFutures);

      _isInitialized = true;

      final initTime = DateTime.now().difference(startTime).inMilliseconds;
      if (debugMode) {
        print('[DEBUG] Worker pool initialized in ${initTime}ms');
      }

      // Perform warmup if enabled
      await _warmupWorkers();
    } catch (e) {
      if (debugMode) {
        print('[ERROR] Failed to initialize worker pool: $e');
      }
      // Cleanup any partially created workers
      await _cleanupWorkers();
      rethrow;
    }
  }

  /// Submit tasks for processing
  ///
  /// Returns list of generated file paths
  Future<List<String>> submitTasks(
    List<String> filePaths,
    String projectRoot, {
    bool autoModify = false,
  }) async {
    if (!_isInitialized) {
      throw StateError('Worker pool is not initialized');
    }

    if (_isShutdown) {
      throw StateError('Worker pool has been shutdown');
    }

    if (filePaths.isEmpty) {
      return [];
    }

    final startTime = DateTime.now();
    if (debugMode) {
      print('[DEBUG] Submitting ${filePaths.length} files for processing');
    }

    try {
      // Group files using optimal strategy
      final fileGroups = await _groupFilesOptimally(filePaths);
      if (debugMode) {
        print(
            '[DEBUG] Files grouped into ${fileGroups.length} batches using adaptive strategy');
      }

      // Create work tasks
      final tasks = <WorkTask>[];
      for (int i = 0; i < fileGroups.length; i++) {
        final taskId = 'batch_${DateTime.now().millisecondsSinceEpoch}_$i';
        final task = WorkTask(
          filePaths: fileGroups[i],
          projectRoot: projectRoot,
          debugMode: debugMode,
          autoModify: autoModify,
          taskId: taskId,
        );
        tasks.add(task);
      }

      // Process tasks and collect results
      final results = await _processTasks(tasks);

      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;
      if (debugMode) {
        print('[DEBUG] Task processing completed in ${processingTime}ms');
        print('[DEBUG] Generated ${results.length} files');
      }

      return results;
    } catch (e) {
      if (debugMode) {
        print('[ERROR] Task submission failed: $e');
      }
      rethrow;
    }
  }

  /// Shutdown the worker pool
  Future<void> shutdown() async {
    if (_isShutdown) {
      return;
    }

    _isShutdown = true;

    if (debugMode) {
      print('[DEBUG] Shutting down worker pool');
    }

    // Wait for current processing to complete
    while (_isProcessing) {
      await Future.delayed(Duration(milliseconds: 50));
    }

    // Clear task queue
    while (_taskQueue.isNotEmpty) {
      final task = _taskQueue.removeFirst();
      if (!task.completer.isCompleted) {
        task.completer.complete([]);
      }
    }

    // Shutdown all workers
    await _cleanupWorkers();

    if (debugMode) {
      print('[DEBUG] Worker pool shutdown completed');
    }
  }

  /// Group files using adaptive strategy for optimal distribution
  Future<List<List<String>>> _groupFilesOptimally(List<String> files) async {
    if (files.isEmpty) return [];

    // Use adaptive grouping strategy for optimal performance
    return await FileGroupingStrategy.groupFiles(
      files,
      GroupingStrategy.adaptive,
      workerCount: workerCount,
      debugMode: debugMode,
    );
  }

  /// Process tasks using available workers
  Future<List<String>> _processTasks(List<WorkTask> tasks) async {
    if (tasks.isEmpty) return [];

    _isProcessing = true;
    final results = <String>[];

    try {
      // Add tasks to queue
      _taskQueue.addAll(tasks);

      // Process tasks concurrently
      final futures = <Future<List<String>>>[];
      for (final task in tasks) {
        futures.add(task.completer.future);
      }

      // Start task processing
      await _processTaskQueue();

      // Wait for all tasks to complete
      final taskResults = await Future.wait(futures);

      // Flatten results
      for (final taskResult in taskResults) {
        results.addAll(taskResult);
      }

      return results;
    } finally {
      _isProcessing = false;
    }
  }

  /// Process task queue using available workers
  Future<void> _processTaskQueue() async {
    // Process all tasks concurrently without polling
    final processingFutures = <Future<void>>[];

    for (int i = 0; i < _taskQueue.length && i < _workers.length; i++) {
      if (_taskQueue.isNotEmpty) {
        final task = _taskQueue.removeFirst();
        final worker = _workers[i];
        processingFutures.add(_assignTaskToWorker(task, worker));
      }
    }

    // Wait for initial batch to complete, then process remaining tasks
    if (processingFutures.isNotEmpty) {
      await Future.wait(processingFutures);

      // Process remaining tasks if any
      if (_taskQueue.isNotEmpty && !_isShutdown) {
        await _processTaskQueue();
      }
    }
  }

  /// Assign task to specific worker
  Future<void> _assignTaskToWorker(WorkTask task, IsolateWorker worker) async {
    final startTime = DateTime.now();

    if (debugMode) {
      print(
          '[DEBUG] Assigning task with ${task.filePaths.length} files to worker ${worker.workerId}');
    }

    try {
      final result = await worker.processBatch(
        task.filePaths,
        task.projectRoot,
        task.autoModify,
      );

      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;

      if (debugMode) {
        print(
            '[DEBUG] Worker ${worker.workerId} completed task in ${processingTime}ms, generated ${result.length} files');
      }

      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }
    } catch (error) {
      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds;

      if (debugMode) {
        print(
            '[ERROR] Worker ${worker.workerId} failed task after ${processingTime}ms: $error');
      }

      if (!task.completer.isCompleted) {
        task.completer.completeError(error);
      }
    }
  }

  /// Warmup workers to avoid cold start overhead
  Future<void> _warmupWorkers() async {
    if (debugMode) {
      print('[DEBUG] Warming up workers');
    }

    try {
      final warmupFutures = <Future<List<String>>>[];
      for (final worker in _workers) {
        // Send empty batch for warmup
        warmupFutures.add(worker.processBatch([], '', false));
      }

      await Future.wait(warmupFutures);

      if (debugMode) {
        print('[DEBUG] Worker warmup completed');
      }
    } catch (e) {
      if (debugMode) {
        print('[WARNING] Worker warmup failed: $e');
      }
      // Warmup failure is not critical, continue
    }
  }

  /// Cleanup all workers
  Future<void> _cleanupWorkers() async {
    final shutdownFutures = <Future<void>>[];
    for (final worker in _workers) {
      shutdownFutures.add(worker.stop());
    }

    try {
      await Future.wait(shutdownFutures, eagerError: false);
    } catch (e) {
      if (debugMode) {
        print('[WARNING] Some workers failed to shutdown cleanly: $e');
      }
    }

    _workers.clear();
  }
}
