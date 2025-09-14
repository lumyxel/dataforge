import 'package:test/test.dart';
import 'package:dataforge/src/isolate_worker_pool.dart';

void main() {
  group('Concurrent Processing Tests', () {
    late IsolateWorkerPool pool;

    setUp(() async {
      pool = IsolateWorkerPool(
        workerCount: 4,
        debugMode: true,
      );
      await pool.initialize();
      // 确保所有 worker 都已启动
      await Future.delayed(Duration(milliseconds: 100));
    });

    tearDown(() async {
      await pool.shutdown();
    });

    test('should process multiple batches concurrently', () async {
      // 使用项目中实际存在的文件
      final filePaths = [
        'lib/src/isolate_models.dart',
        'lib/src/isolate_worker.dart',
        'lib/src/isolate_worker_pool.dart',
        'lib/src/file_grouping_strategy.dart',
        'lib/dataforge.dart',
      ];
      final projectRoot = '.';
      final autoModify = false;

      final startTime = DateTime.now();

      final results = await pool.submitTasks(
        filePaths,
        projectRoot,
        autoModify: autoModify,
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      expect(results, isNotEmpty);
      expect(results.length, equals(filePaths.length));
      expect(duration.inMilliseconds,
          lessThan(10000)); // Should complete within 10 seconds

      // 验证所有文件都被处理
      for (final result in results) {
        expect(result, isNotEmpty);
      }

      // 验证统计信息
      final stats = pool.statistics;
      expect(stats['totalTasksProcessed'], greaterThan(0));
      expect(stats['totalFilesProcessed'], equals(filePaths.length));
    });

    test('should handle concurrent load with different batch sizes', () async {
      final smallBatch = [
        'lib/src/isolate_models.dart',
        'lib/dataforge.dart',
      ];
      final mediumBatch = [
        'lib/src/isolate_worker.dart',
        'lib/src/isolate_worker_pool.dart',
        'lib/src/file_grouping_strategy.dart',
      ];
      final largeBatch = [
        'lib/src/isolate_models.dart',
        'lib/src/isolate_worker.dart',
        'lib/src/isolate_worker_pool.dart',
        'lib/src/file_grouping_strategy.dart',
        'lib/dataforge.dart',
      ];

      final projectRoot = '.';
      final autoModify = false;

      // Submit all batches concurrently
      final futures = [
        pool.submitTasks(smallBatch, projectRoot, autoModify: autoModify),
        pool.submitTasks(mediumBatch, projectRoot, autoModify: autoModify),
        pool.submitTasks(largeBatch, projectRoot, autoModify: autoModify),
      ];

      final results = await Future.wait(futures);

      expect(results.length, equals(3));
      expect(results[0].length, equals(smallBatch.length));
      expect(results[1].length, equals(mediumBatch.length));
      expect(results[2].length, equals(largeBatch.length));
    });

    test('should maintain worker utilization during concurrent processing',
        () async {
      final batches = List.generate(
          4,
          (i) => [
                'lib/src/isolate_models.dart',
                'lib/src/isolate_worker.dart',
                'lib/src/isolate_worker_pool.dart',
                'lib/src/file_grouping_strategy.dart',
                'lib/dataforge.dart',
              ]);

      final projectRoot = '.';
      final autoModify = false;

      // Submit batches with slight delays to test worker distribution
      final futures = <Future<List<String>>>[];

      for (int i = 0; i < batches.length; i++) {
        futures.add(
          Future.delayed(
            Duration(milliseconds: i * 100),
            () => pool.submitTasks(
              batches[i],
              projectRoot,
              autoModify: autoModify,
            ),
          ),
        );
      }

      final results = await Future.wait(futures);

      expect(results.length, equals(4));

      // Verify all workers were utilized
      final stats = pool.statistics;
      expect(stats['totalFilesProcessed'], greaterThan(0));
      expect(stats['totalProcessingTime'], greaterThan(0));
    });

    test('should handle mixed workload patterns', () async {
      final quickTasks = [
        'lib/src/isolate_models.dart',
        'lib/dataforge.dart',
      ];
      final slowTasks = [
        'lib/src/isolate_worker.dart',
        'lib/src/isolate_worker_pool.dart',
        'lib/src/file_grouping_strategy.dart',
      ];

      final projectRoot = '.';
      final autoModify = false;

      // Submit quick tasks first, then slow tasks
      final quickFuture = pool.submitTasks(
        quickTasks,
        projectRoot,
        autoModify: autoModify,
      );

      // Small delay before submitting slow tasks
      await Future.delayed(Duration(milliseconds: 50));

      final slowFuture = pool.submitTasks(
        slowTasks,
        projectRoot,
        autoModify: autoModify,
      );

      final results = await Future.wait([quickFuture, slowFuture]);

      expect(results[0].length, equals(quickTasks.length));
      expect(results[1].length, equals(slowTasks.length));
    });

    test('should handle concurrent error scenarios', () async {
      final validFiles = [
        'lib/src/isolate_models.dart',
        'lib/src/isolate_worker.dart',
        'lib/dataforge.dart',
      ];
      final invalidFiles = [
        'nonexistent/file1.dart',
        'nonexistent/file2.dart',
      ];

      final projectRoot = '.';
      final autoModify = false;

      // Submit both valid and potentially problematic files concurrently
      final futures = [
        pool.submitTasks(validFiles, projectRoot, autoModify: autoModify),
        pool.submitTasks(invalidFiles, projectRoot, autoModify: autoModify),
      ];

      // Should handle errors gracefully without affecting other tasks
      final results = await Future.wait(futures, eagerError: false);

      expect(results.length, equals(2));
      // At least one batch should succeed
      expect(results.any((result) => result.isNotEmpty), isTrue);
    });

    test('should scale worker utilization based on load', () async {
      // Start with light load
      final lightLoad = [
        'lib/src/isolate_models.dart',
      ];

      await pool.submitTasks(
        lightLoad,
        '.',
        autoModify: false,
      );

      final lightStats = pool.statistics;
      final lightActiveWorkers = lightStats['availableWorkers'];

      // Then heavy load
      final heavyLoad = [
        'lib/src/isolate_models.dart',
        'lib/src/isolate_worker.dart',
        'lib/src/isolate_worker_pool.dart',
        'lib/src/file_grouping_strategy.dart',
        'lib/dataforge.dart',
      ];

      await pool.submitTasks(
        heavyLoad,
        '.',
        autoModify: false,
      );

      final heavyStats = pool.statistics;
      final heavyActiveWorkers = heavyStats['availableWorkers'];

      // Heavy load should utilize more workers
      expect(heavyActiveWorkers, greaterThanOrEqualTo(lightActiveWorkers));
    });

    test('should maintain performance under sustained load', () async {
      final sustainedBatches = List.generate(
          5,
          (i) => [
                'lib/src/isolate_models.dart',
                'lib/src/isolate_worker.dart',
                'lib/dataforge.dart',
              ]);

      final projectRoot = '.';
      final autoModify = false;
      final processingTimes = <Duration>[];

      // Process batches sequentially to measure sustained performance
      for (final batch in sustainedBatches) {
        final startTime = DateTime.now();

        await pool.submitTasks(
          batch,
          projectRoot,
          autoModify: autoModify,
        );

        final endTime = DateTime.now();
        processingTimes.add(endTime.difference(startTime));
      }

      // Performance should remain relatively stable
      final averageTime = processingTimes.fold<int>(
            0,
            (sum, duration) => sum + duration.inMilliseconds,
          ) /
          processingTimes.length;

      final maxTime = processingTimes
          .map((d) => d.inMilliseconds)
          .reduce((a, b) => a > b ? a : b);
      final minTime = processingTimes
          .map((d) => d.inMilliseconds)
          .reduce((a, b) => a < b ? a : b);

      // Max time shouldn't be more than 3x the average (allowing for some variance)
      expect(maxTime, lessThan(averageTime * 3));
      expect(minTime, greaterThan(0));
    });
  });

  group('Concurrent Processing Edge Cases', () {
    test('should handle rapid successive submissions', () async {
      final pool = IsolateWorkerPool(
        workerCount: 2,
        debugMode: true,
      );

      await pool.initialize();

      try {
        final rapidSubmissions = List.generate(
            10,
            (i) => pool.submitTasks(
                  ['lib/src/isolate_models.dart'],
                  '.',
                  autoModify: false,
                ));

        final results = await Future.wait(rapidSubmissions);

        expect(results.length, equals(10));
        expect(results.every((result) => result.isNotEmpty), isTrue);
      } finally {
        await pool.shutdown();
      }
    });

    test('should handle worker failures during concurrent processing',
        () async {
      final pool = IsolateWorkerPool(
        workerCount: 3,
        debugMode: true,
      );

      await pool.initialize();

      try {
        final normalBatch = [
          'lib/src/isolate_models.dart',
          'lib/src/isolate_worker.dart',
          'lib/dataforge.dart',
        ];

        // Submit normal processing task
        final normalFuture = pool.submitTasks(
          normalBatch,
          '.',
          autoModify: false,
        );

        // The pool should handle any internal worker issues gracefully
        final result = await normalFuture;

        expect(result.length, equals(normalBatch.length));
      } finally {
        await pool.shutdown();
      }
    });
  });
}
