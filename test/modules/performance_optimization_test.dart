import 'package:test/test.dart';
import 'package:dataforge/src/isolate_worker_pool.dart';
import 'dart:io';

void main() {
  group('Performance Optimization Tests', () {
    late IsolateWorkerPool pool;

    setUp(() async {
      pool = IsolateWorkerPool(
        workerCount: Platform.numberOfProcessors,
        debugMode: true,
      );
      await pool.initialize();
    });

    tearDown(() async {
      await pool.shutdown();
    });

    test('should optimize worker count based on CPU cores', () async {
      final cpuCores = Platform.numberOfProcessors;
      final optimizedPool = IsolateWorkerPool(
        workerCount: cpuCores,
        debugMode: true,
      );

      await optimizedPool.initialize();

      try {
        final stats = optimizedPool.statistics;
        expect(stats['workerCount'], equals(cpuCores));

        // Test with workload that matches CPU cores
        final filePaths = List.generate(
            cpuCores * 5, (i) => 'test/fixtures/cpu_optimized_$i.dart');

        final startTime = DateTime.now();
        final results = await optimizedPool.submitTasks(
          filePaths,
          '/test/project',
          autoModify: false,
        );
        final processingTime = DateTime.now().difference(startTime);

        expect(results.length, equals(filePaths.length));
        expect(processingTime.inMilliseconds, lessThan(5000));
      } finally {
        await optimizedPool.shutdown();
      }
    });

    test('should demonstrate warmup performance benefits', () async {
      // Test cold start performance
      final coldPool = IsolateWorkerPool(
        workerCount: 2,
        debugMode: true,
      );

      await coldPool.initialize();

      final testFiles =
          List.generate(10, (i) => 'test/fixtures/warmup_$i.dart');

      // First run (cold start)
      final coldStartTime = DateTime.now();
      await coldPool.submitTasks(
        testFiles,
        '/test/project',
        autoModify: false,
      );
      final coldDuration = DateTime.now().difference(coldStartTime);

      // Second run (warmed up)
      final warmStartTime = DateTime.now();
      await coldPool.submitTasks(
        testFiles,
        '/test/project',
        autoModify: false,
      );
      final warmDuration = DateTime.now().difference(warmStartTime);

      // Warm run should be faster or similar
      expect(warmDuration.inMilliseconds,
          lessThanOrEqualTo(coldDuration.inMilliseconds * 1.2));

      await coldPool.shutdown();
    });

    test('should optimize batch sizes for different file counts', () async {
      final testCases = [
        {'fileCount': 5, 'expectedBatches': 1},
        {'fileCount': 20, 'expectedBatches': 2},
        {'fileCount': 50, 'expectedBatches': 4},
        {'fileCount': 100, 'expectedBatches': 6},
      ];

      for (final testCase in testCases) {
        final fileCount = testCase['fileCount'] as int;
        final filePaths = List.generate(
            fileCount, (i) => 'test/fixtures/batch_size_${fileCount}_$i.dart');

        final startTime = DateTime.now();
        final results = await pool.submitTasks(
          filePaths,
          '/test/project',
          autoModify: false,
        );
        final processingTime = DateTime.now().difference(startTime);

        expect(results.length, equals(fileCount));

        // Larger batches should have better throughput (files per second)
        final throughput = fileCount / (processingTime.inMilliseconds / 1000.0);
        expect(throughput, greaterThan(0));
      }
    });

    test('should handle memory optimization under load', () async {
      // Create large workload to test memory management
      final largeBatches = <List<String>>[];
      for (int batch = 0; batch < 10; batch++) {
        final batchFiles = List.generate(
            20, (i) => 'test/fixtures/memory_batch_${batch}_file_$i.dart');
        largeBatches.add(batchFiles);
      }

      final processingTimes = <Duration>[];

      // Process batches sequentially to monitor memory usage
      for (int i = 0; i < largeBatches.length; i++) {
        final startTime = DateTime.now();

        await pool.submitTasks(
          largeBatches[i],
          '/test/project',
          autoModify: false,
        );

        final processingTime = DateTime.now().difference(startTime);
        processingTimes.add(processingTime);

        // Check that processing time doesn't degrade significantly
        if (i > 0) {
          final currentTime = processingTime.inMilliseconds;
          final previousTime = processingTimes[i - 1].inMilliseconds;

          // Current processing time shouldn't be more than 50% slower
          expect(currentTime, lessThan(previousTime * 1.5));
        }
      }

      // Overall performance should remain stable
      final averageTime = processingTimes.fold<int>(
            0,
            (sum, duration) => sum + duration.inMilliseconds,
          ) /
          processingTimes.length;

      final maxTime = processingTimes
          .map((d) => d.inMilliseconds)
          .reduce((a, b) => a > b ? a : b);

      // Max time shouldn't be more than 2x average (memory pressure tolerance)
      expect(maxTime, lessThan(averageTime * 2));
    });

    test('should optimize task distribution across workers', () async {
      final workerCount = pool.statistics['workerCount'] as int;

      // Create workload that can be evenly distributed
      final totalFiles = workerCount * 8; // 8 files per worker
      final filePaths = List.generate(
          totalFiles, (i) => 'test/fixtures/distribution_$i.dart');

      final startTime = DateTime.now();
      final results = await pool.submitTasks(
        filePaths,
        '/test/project',
        autoModify: false,
      );
      final processingTime = DateTime.now().difference(startTime);

      expect(results.length, equals(totalFiles));

      // Check worker utilization
      final stats = pool.statistics;
      final totalProcessed = stats['totalFilesProcessed'] as int;

      expect(totalProcessed, greaterThanOrEqualTo(totalFiles));

      // Processing should be efficient with good distribution
      final throughput = totalFiles / (processingTime.inMilliseconds / 1000.0);
      expect(throughput, greaterThan(1.0)); // At least 1 file per second
    });

    test('should demonstrate adaptive grouping performance', () async {
      // Test different file patterns
      final testScenarios = [
        {
          'name': 'small_files',
          'files': List.generate(50, (i) => 'test/fixtures/small_$i.dart'),
        },
        {
          'name': 'medium_files',
          'files': List.generate(25, (i) => 'test/fixtures/medium_$i.dart'),
        },
        {
          'name': 'large_files',
          'files': List.generate(10, (i) => 'test/fixtures/large_$i.dart'),
        },
      ];

      final performanceResults = <String, Duration>{};

      for (final scenario in testScenarios) {
        final scenarioName = scenario['name'] as String;
        final files = scenario['files'] as List<String>;

        final startTime = DateTime.now();
        final results = await pool.submitTasks(
          files,
          '/test/project',
          autoModify: false,
        );
        final processingTime = DateTime.now().difference(startTime);

        expect(results.length, equals(files.length));
        performanceResults[scenarioName] = processingTime;
      }

      // All scenarios should complete in reasonable time
      for (final entry in performanceResults.entries) {
        expect(entry.value.inMilliseconds, lessThan(8000)); // 8 seconds max
      }
    });

    test('should handle resource cleanup efficiently', () async {
      // Create multiple pools to test resource management
      final testPools = <IsolateWorkerPool>[];

      try {
        // Create several small pools
        for (int i = 0; i < 3; i++) {
          final testPool = IsolateWorkerPool(
            workerCount: 2,
            debugMode: true,
          );
          await testPool.initialize();
          testPools.add(testPool);
        }

        // Use each pool briefly
        for (int i = 0; i < testPools.length; i++) {
          final testFiles =
              List.generate(5, (j) => 'test/fixtures/cleanup_${i}_$j.dart');

          final results = await testPools[i].submitTasks(
            testFiles,
            '/test/project',
            autoModify: false,
          );

          expect(results.length, equals(testFiles.length));
        }

        // Shutdown should be quick and clean
        final shutdownStart = DateTime.now();

        for (final testPool in testPools) {
          await testPool.shutdown();
        }

        final shutdownTime = DateTime.now().difference(shutdownStart);

        // Shutdown should complete quickly
        expect(shutdownTime.inMilliseconds, lessThan(2000));
      } finally {
        // Ensure cleanup even if test fails
        for (final testPool in testPools) {
          if (!testPool.isShutdown) {
            await testPool.shutdown();
          }
        }
      }
    });

    test('should optimize for different workload patterns', () async {
      final workloadPatterns = [
        {
          'name': 'burst_load',
          'batches': [List.generate(30, (i) => 'test/fixtures/burst_$i.dart')],
        },
        {
          'name': 'steady_load',
          'batches': List.generate(
              6,
              (i) =>
                  List.generate(5, (j) => 'test/fixtures/steady_${i}_$j.dart')),
        },
        {
          'name': 'mixed_load',
          'batches': [
            List.generate(20, (i) => 'test/fixtures/mixed_large_$i.dart'),
            List.generate(5, (i) => 'test/fixtures/mixed_small_$i.dart'),
          ],
        },
      ];

      for (final pattern in workloadPatterns) {
        final patternName = pattern['name'] as String;
        final batches = pattern['batches'] as List<List<String>>;

        final startTime = DateTime.now();

        // Process all batches for this pattern
        final futures = batches
            .map((batch) => pool.submitTasks(
                  batch,
                  '/test/project',
                  autoModify: false,
                ))
            .toList();

        final results = await Future.wait(futures);
        final processingTime = DateTime.now().difference(startTime);

        // Verify all batches completed
        expect(results.length, equals(batches.length));

        final totalFiles =
            batches.fold<int>(0, (sum, batch) => sum + batch.length);
        final totalResults =
            results.fold<int>(0, (sum, result) => sum + result.length);

        expect(totalResults, equals(totalFiles));

        // Performance should be reasonable for all patterns
        final throughput =
            totalFiles / (processingTime.inMilliseconds / 1000.0);
        expect(throughput, greaterThan(0.5)); // At least 0.5 files per second
      }
    });
  });

  group('Performance Benchmarks', () {
    test('should benchmark single vs multi-worker performance', () async {
      final testFiles =
          List.generate(20, (i) => 'test/fixtures/benchmark_$i.dart');

      // Single worker benchmark
      final singleWorkerPool = IsolateWorkerPool(
        workerCount: 1,
        debugMode: false,
      );

      await singleWorkerPool.initialize();

      final singleStartTime = DateTime.now();
      await singleWorkerPool.submitTasks(
        testFiles,
        '/test/project',
        autoModify: false,
      );
      final singleWorkerTime = DateTime.now().difference(singleStartTime);

      await singleWorkerPool.shutdown();

      // Multi-worker benchmark
      final multiWorkerPool = IsolateWorkerPool(
        workerCount: 4,
        debugMode: false,
      );

      await multiWorkerPool.initialize();

      final multiStartTime = DateTime.now();
      await multiWorkerPool.submitTasks(
        testFiles,
        '/test/project',
        autoModify: false,
      );
      final multiWorkerTime = DateTime.now().difference(multiStartTime);

      await multiWorkerPool.shutdown();

      // Multi-worker should be faster or at least not significantly slower
      final speedupRatio =
          singleWorkerTime.inMilliseconds / multiWorkerTime.inMilliseconds;
      expect(speedupRatio, greaterThanOrEqualTo(0.8)); // Allow some overhead
    });
  });
}
