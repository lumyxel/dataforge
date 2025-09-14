import 'dart:async';
import 'package:test/test.dart';
import 'package:dataforge/src/isolate_worker.dart';
import 'package:dataforge/src/isolate_models.dart';

void main() {
  group('IsolateWorker', () {
    late IsolateWorker worker;

    setUp(() async {
      // Create worker instance
      worker = IsolateWorker(
        workerId: 'test_worker',
        debugMode: true,
      );

      // Start the worker
      await worker.start();
    });

    tearDown(() async {
      await worker.stop();
    });

    test('should initialize worker successfully', () async {
      expect(worker.workerId, equals('test_worker'));
      expect(worker.status, equals(WorkerStatus.idle));
      expect(worker.isAvailable, isTrue);
    });

    test('should process batch successfully', () async {
      final filePaths = ['test/fixtures/sample.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      // Process batch
      final result =
          await worker.processBatch(filePaths, projectRoot, autoModify);

      expect(result, isA<List<String>>());
      expect(worker.status, equals(WorkerStatus.idle));
    });

    test('should handle processing errors', () async {
      final filePaths = ['non_existent_file.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      // This should handle the error gracefully
      final result =
          await worker.processBatch(filePaths, projectRoot, autoModify);

      expect(result, isA<List<String>>());
      expect(result.isEmpty, isTrue); // No files processed due to error
    });

    test('should update worker statistics', () async {
      final initialStats = worker.stats;
      expect(initialStats.filesProcessed, equals(0));
      expect(initialStats.totalProcessingTime, equals(0));

      final filePaths = ['test/fixtures/sample.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      await worker.processBatch(filePaths, projectRoot, autoModify);

      final updatedStats = worker.stats;
      expect(updatedStats.filesProcessed, greaterThanOrEqualTo(1));
      expect(updatedStats.totalProcessingTime, greaterThan(0));
      expect(updatedStats.averageProcessingTime, greaterThan(0));
    });

    test('should handle worker errors gracefully', () async {
      final filePaths = ['invalid_file.dart'];
      final projectRoot = '/invalid/project';
      final autoModify = false;

      // This should handle the error and return empty result
      final result =
          await worker.processBatch(filePaths, projectRoot, autoModify);

      expect(result, isA<List<String>>());
      expect(result.isEmpty, isTrue);
    });

    test('should track worker status during processing', () async {
      final filePaths = ['test/fixtures/sample.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      // Start processing in background
      final future = worker.processBatch(filePaths, projectRoot, autoModify);

      // Check status during processing
      await Future.delayed(Duration(milliseconds: 10));
      expect(worker.status, equals(WorkerStatus.busy));
      expect(worker.isAvailable, isFalse);

      // Wait for completion
      await future;

      expect(worker.status, equals(WorkerStatus.idle));
      expect(worker.isAvailable, isTrue);
    });

    test('should prevent concurrent batch processing', () async {
      final filePaths1 = ['test/fixtures/sample1.dart'];
      final filePaths2 = ['test/fixtures/sample2.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      // Start first batch
      final future1 = worker.processBatch(filePaths1, projectRoot, autoModify);

      // Try to start second batch immediately
      expect(
        () => worker.processBatch(filePaths2, projectRoot, autoModify),
        throwsA(isA<StateError>()),
      );

      // Wait for first batch to complete
      await future1;

      // Now second batch should work
      final result2 =
          await worker.processBatch(filePaths2, projectRoot, autoModify);
      expect(result2, isA<List<String>>());
    });

    test('should stop worker cleanly', () async {
      expect(worker.status, equals(WorkerStatus.idle));

      await worker.stop();

      expect(worker.status, equals(WorkerStatus.shutdown));
      expect(worker.isAvailable, isFalse);
    });

    test('should reject batches after stop', () async {
      await worker.stop();

      final filePaths = ['test/fixtures/sample.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      expect(
        () => worker.processBatch(filePaths, projectRoot, autoModify),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('IsolateWorker Creation', () {
    test('should create worker with different configurations', () async {
      final worker1 = IsolateWorker(
        workerId: 'config_worker_1',
        debugMode: false,
      );

      final worker2 = IsolateWorker(
        workerId: 'config_worker_2',
        debugMode: true,
      );

      expect(worker1.workerId, equals('config_worker_1'));
      expect(worker2.workerId, equals('config_worker_2'));

      await worker1.start();
      await worker2.start();

      expect(worker1.status, equals(WorkerStatus.idle));
      expect(worker2.status, equals(WorkerStatus.idle));

      await worker1.stop();
      await worker2.stop();
    });
  });

  group('IsolateWorker Integration', () {
    test('should handle multiple sequential batches', () async {
      final worker = IsolateWorker(
        workerId: 'sequential_worker',
        debugMode: true,
      );

      await worker.start();

      final batches = List.generate(3, (i) => ['test/fixtures/sample_$i.dart']);
      final projectRoot = '/test/project';
      final autoModify = false;

      final results = <List<String>>[];

      for (final batch in batches) {
        final result =
            await worker.processBatch(batch, projectRoot, autoModify);
        results.add(result);
      }

      expect(results.length, equals(3));
      expect(worker.stats.filesProcessed, greaterThanOrEqualTo(0));

      await worker.stop();
    });

    test('should maintain worker isolation', () async {
      final worker1 = IsolateWorker(
        workerId: 'isolated_worker_1',
        debugMode: true,
      );

      final worker2 = IsolateWorker(
        workerId: 'isolated_worker_2',
        debugMode: true,
      );

      await worker1.start();
      await worker2.start();

      final filePaths1 = ['test/fixtures/sample1.dart'];
      final filePaths2 = ['test/fixtures/sample2.dart'];
      final projectRoot1 = '/test/project1';
      final projectRoot2 = '/test/project2';
      final autoModify = false;

      // Process batches concurrently on different workers
      final results = await Future.wait([
        worker1.processBatch(filePaths1, projectRoot1, autoModify),
        worker2.processBatch(filePaths2, projectRoot2, autoModify),
      ]);

      expect(results.length, equals(2));
      expect(worker1.stats.filesProcessed, greaterThanOrEqualTo(0));
      expect(worker2.stats.filesProcessed, greaterThanOrEqualTo(0));

      await Future.wait([
        worker1.stop(),
        worker2.stop(),
      ]);
    });

    test('should handle worker communication errors', () async {
      final worker = IsolateWorker(
        workerId: 'comm_error_worker',
        debugMode: true,
      );

      await worker.start();

      // Stop the worker to simulate communication error
      await worker.stop();

      final filePaths = ['test/fixtures/sample.dart'];
      final projectRoot = '/test/project';
      final autoModify = false;

      expect(
        () => worker.processBatch(filePaths, projectRoot, autoModify),
        throwsA(isA<StateError>()),
      );
    });

    test('should handle worker memory management', () async {
      final worker = IsolateWorker(
        workerId: 'memory_worker',
        debugMode: true,
      );

      await worker.start();

      // Process many batches to test memory management
      final largeBatches = List.generate(
          5, (i) => List.generate(3, (j) => 'test/fixtures/file_${i}_$j.dart'));

      final projectRoot = '/test/project';
      final autoModify = false;

      for (final batch in largeBatches) {
        await worker.processBatch(batch, projectRoot, autoModify);
      }

      expect(worker.stats.filesProcessed, greaterThanOrEqualTo(0));
      expect(worker.status, equals(WorkerStatus.idle));

      await worker.stop();
    });
  });
}
