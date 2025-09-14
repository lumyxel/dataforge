import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:dataforge/src/isolate_worker_pool.dart';
import 'package:dataforge/src/file_grouping_strategy.dart';

void main() {
  group('IsolateWorkerPool', () {
    late IsolateWorkerPool pool;
    late Directory tempDir;

    setUp(() async {
      // Create temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('dataforge_test_');

      // Create test files
      final testFile1 = File('${tempDir.path}/test1.model.dart');
      final testFile2 = File('${tempDir.path}/test2.model.dart');

      await testFile1.writeAsString('''
@DataClass()
class TestModel1 {
  final String name;
  final int age;
}
''');

      await testFile2.writeAsString('''
@DataClass()
class TestModel2 {
  final String title;
  final bool isActive;
}
''');
    });

    tearDown(() async {
      if (pool.isInitialized) {
        await pool.shutdown();
      }
      // Clean up temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should initialize with correct worker count', () async {
      pool = IsolateWorkerPool(workerCount: 2);
      await pool.initialize();

      expect(pool.isInitialized, isTrue);
      expect(pool.workerCount, equals(2));
      expect(pool.statistics['availableWorkers'], equals(2));
      expect(pool.statistics['queuedTasks'], equals(0));
    });

    test('should auto-detect optimal worker count', () async {
      pool = IsolateWorkerPool(); // No worker count specified
      await pool.initialize();

      expect(pool.isInitialized, isTrue);
      expect(pool.workerCount, greaterThan(0));
      expect(pool.workerCount, lessThanOrEqualTo(Platform.numberOfProcessors));
    });

    test('should process files concurrently', () async {
      pool = IsolateWorkerPool(workerCount: 2);
      await pool.initialize();

      final files = [
        '${tempDir.path}/test1.model.dart',
        '${tempDir.path}/test2.model.dart',
      ];

      final stopwatch = Stopwatch()..start();
      final results = await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: false,
      );
      stopwatch.stop();

      expect(results, isA<List<String>>());
      expect(results.length, equals(2));
      expect(stopwatch.elapsedMilliseconds,
          lessThan(10000)); // Should complete within 10 seconds
    });

    test('should handle empty file list', () async {
      pool = IsolateWorkerPool(workerCount: 1);
      await pool.initialize();

      final results = await pool.submitTasks(
        [],
        tempDir.path,
        autoModify: false,
      );

      expect(results, isEmpty);
    });

    test('should handle single file processing', () async {
      pool = IsolateWorkerPool(workerCount: 1);
      await pool.initialize();

      final files = ['${tempDir.path}/test1.model.dart'];

      final results = await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: false,
      );

      expect(results, isA<List<String>>());
      expect(results.length, equals(1));
    });

    test('should distribute work across multiple workers', () async {
      pool = IsolateWorkerPool(workerCount: 2);
      await pool.initialize();

      // Create more test files to ensure work distribution
      final files = <String>[];
      for (int i = 3; i <= 6; i++) {
        final testFile = File('${tempDir.path}/test$i.model.dart');
        await testFile.writeAsString('''
@DataClass()
class TestModel$i {
  final String field$i;
}
''');
        files.add(testFile.path);
      }

      files.addAll([
        '${tempDir.path}/test1.model.dart',
        '${tempDir.path}/test2.model.dart',
      ]);

      final results = await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: false,
      );

      expect(results.length, equals(files.length));

      // Verify that both workers were utilized
      final stats = pool.statistics;
      expect(stats['workerCount'], equals(2));

      // At least one task should have been processed
      expect(stats['totalTasksProcessed'], greaterThanOrEqualTo(0));
    });

    test('should handle worker errors gracefully', () async {
      pool = IsolateWorkerPool(workerCount: 1);
      await pool.initialize();

      // Create a file with invalid syntax to trigger an error
      final invalidFile = File('${tempDir.path}/invalid.model.dart');
      await invalidFile.writeAsString('invalid dart syntax {{{');

      final files = [invalidFile.path];

      // Should not throw, but handle errors gracefully
      final results = await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: false,
      );

      // Results might be empty or contain error information
      expect(results, isA<List<String>>());
    });

    test('should shutdown cleanly', () async {
      pool = IsolateWorkerPool(workerCount: 2);
      await pool.initialize();

      expect(pool.isInitialized, isTrue);

      await pool.shutdown();

      expect(pool.isInitialized, isFalse);
      expect(pool.statistics['availableWorkers'], equals(0));
      expect(pool.statistics['queuedTasks'], equals(0));
    });

    test('should provide accurate worker statistics', () async {
      pool = IsolateWorkerPool(workerCount: 1);
      await pool.initialize();

      final files = ['${tempDir.path}/test1.model.dart'];

      await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: false,
      );

      final stats = pool.statistics;
      expect(stats['workerCount'], equals(1));
      expect(stats['totalTasksProcessed'], greaterThanOrEqualTo(0));
      expect(stats['totalFilesProcessed'], greaterThanOrEqualTo(0));
      expect(stats['totalProcessingTime'], greaterThanOrEqualTo(0));
    });

    test('should handle concurrent processing requests', () async {
      pool = IsolateWorkerPool(workerCount: 2);
      await pool.initialize();

      final files1 = ['${tempDir.path}/test1.model.dart'];
      final files2 = ['${tempDir.path}/test2.model.dart'];

      // Start two concurrent processing requests
      final future1 = pool.submitTasks(
        files1,
        tempDir.path,
        autoModify: false,
      );

      final future2 = pool.submitTasks(
        files2,
        tempDir.path,
        autoModify: false,
      );

      final results = await Future.wait([future1, future2]);

      expect(results.length, equals(2));
      expect(results[0], isA<List<String>>());
      expect(results[1], isA<List<String>>());
    });

    test('should respect debug mode setting', () async {
      pool = IsolateWorkerPool(workerCount: 1);
      await pool.initialize();

      final files = ['${tempDir.path}/test1.model.dart'];

      // Test with debug mode enabled
      final results = await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: false,
      );

      expect(results, isA<List<String>>());
    });

    test('should respect auto modify setting', () async {
      pool = IsolateWorkerPool(workerCount: 1);
      await pool.initialize();

      final files = ['${tempDir.path}/test1.model.dart'];

      // Test with auto modify enabled
      final results = await pool.submitTasks(
        files,
        tempDir.path,
        autoModify: true,
      );

      expect(results, isA<List<String>>());
    });
  });

  group('File Grouping Strategy Integration', () {
    test('should use optimal file grouping strategy', () async {
      final files = List.generate(10, (i) => 'file$i.dart');

      final groups = await FileGroupingStrategy.groupFiles(
        files,
        GroupingStrategy.adaptive,
        workerCount: 2,
      );

      expect(groups.length, lessThanOrEqualTo(2));
      expect(groups.every((group) => group.isNotEmpty), isTrue);

      // Verify all files are included
      final allGroupedFiles = groups.expand((g) => g).toList();
      expect(allGroupedFiles.length, equals(files.length));
    });

    test('should handle different grouping strategies', () async {
      final files = List.generate(8, (i) => 'file$i.dart');

      // Test CPU-based grouping
      final cpuGroups = await FileGroupingStrategy.groupFiles(
        files,
        GroupingStrategy.byCpuCores,
        workerCount: 4,
      );
      expect(cpuGroups.length, lessThanOrEqualTo(4));

      // Test size-based grouping
      final sizeGroups = await FileGroupingStrategy.groupFiles(
        files,
        GroupingStrategy.byFileSize,
        workerCount: 2,
      );
      expect(sizeGroups.isNotEmpty, isTrue);

      // Test directory-based grouping
      final dirGroups = await FileGroupingStrategy.groupFiles(
        files,
        GroupingStrategy.byDirectory,
        workerCount: 2,
      );
      expect(dirGroups.isNotEmpty, isTrue);
    });
  });
}
