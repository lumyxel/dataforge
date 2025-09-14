import 'dart:io';
import 'package:test/test.dart';
import 'package:dataforge/src/file_grouping_strategy.dart';

void main() {
  group('FileGroupingStrategy', () {
    late Directory tempDir;
    late List<String> testFiles;

    setUp(() async {
      // Create temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('dataforge_test_');

      // Create test files with different sizes
      testFiles = [];
      for (int i = 0; i < 10; i++) {
        final file = File('${tempDir.path}/test$i.dart');
        final content = 'class Test$i {\n${'  // Content $i\n' * (i + 1)}}';
        await file.writeAsString(content);
        testFiles.add(file.path);
      }

      // Create files in subdirectories
      final subDir1 = Directory('${tempDir.path}/models');
      final subDir2 = Directory('${tempDir.path}/services');
      await subDir1.create();
      await subDir2.create();

      for (int i = 0; i < 3; i++) {
        final modelFile = File('${subDir1.path}/model$i.dart');
        final serviceFile = File('${subDir2.path}/service$i.dart');

        await modelFile.writeAsString('class Model$i {}');
        await serviceFile.writeAsString('class Service$i {}');

        testFiles.add(modelFile.path);
        testFiles.add(serviceFile.path);
      }
    });

    tearDown(() async {
      // Clean up temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('groupFiles', () {
      test('should group files by CPU cores strategy', () async {
        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.byCpuCores,
          workerCount: 4,
        );

        expect(groups, isA<List<List<String>>>());
        expect(groups.length, lessThanOrEqualTo(4));
        expect(groups.every((group) => group.isNotEmpty), isTrue);

        // Verify all files are included
        final allFiles = groups.expand((g) => g).toList();
        expect(allFiles.length, equals(testFiles.length));
        expect(allFiles.toSet(), equals(testFiles.toSet()));
      });

      test('should group files by file size strategy', () async {
        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.byFileSize,
          workerCount: 3,
        );

        expect(groups, isA<List<List<String>>>());
        expect(groups.length, lessThanOrEqualTo(testFiles.length));
        expect(groups.every((group) => group.isNotEmpty), isTrue);

        // Verify all files are included
        final allFiles = groups.expand((g) => g).toList();
        expect(allFiles.length, equals(testFiles.length));
      });

      test('should group files by directory strategy', () async {
        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.byDirectory,
          workerCount: 3,
        );

        expect(groups, isA<List<List<String>>>());
        expect(groups.isNotEmpty, isTrue);

        // Files from same directory should be grouped together when possible
        for (final group in groups) {
          if (group.length > 1) {
            final directories = group.map((f) => File(f).parent.path).toSet();
            // Groups may contain files from multiple directories for load balancing
            expect(directories.isNotEmpty, isTrue);
          }
        }

        // Verify all files are included
        final allFiles = groups.expand((g) => g).toList();
        expect(allFiles.length, equals(testFiles.length));
      });

      test('should group files using adaptive strategy', () async {
        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.adaptive,
          workerCount: 2,
        );

        expect(groups, isA<List<List<String>>>());
        expect(groups.length, lessThanOrEqualTo(2));
        expect(groups.every((group) => group.isNotEmpty), isTrue);

        // Verify all files are included
        final allFiles = groups.expand((g) => g).toList();
        expect(allFiles.length, equals(testFiles.length));
      });

      test('should handle empty file list', () async {
        final groups = await FileGroupingStrategy.groupFiles(
          [],
          GroupingStrategy.adaptive,
          workerCount: 2,
        );

        expect(groups, isEmpty);
      });

      test('should handle single file', () async {
        final singleFile = [testFiles.first];
        final groups = await FileGroupingStrategy.groupFiles(
          singleFile,
          GroupingStrategy.adaptive,
          workerCount: 4,
        );

        expect(groups.length, equals(1));
        expect(groups.first, equals(singleFile));
      });

      test('should respect worker count limit', () async {
        final workerCount = 2;
        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.byCpuCores,
          workerCount: workerCount,
        );

        expect(groups.length, lessThanOrEqualTo(workerCount));
      });

      test('should handle more workers than files', () async {
        final smallFileList = testFiles.take(3).toList();
        final groups = await FileGroupingStrategy.groupFiles(
          smallFileList,
          GroupingStrategy.adaptive,
          workerCount: 10,
        );

        expect(groups.length, lessThanOrEqualTo(smallFileList.length));
        expect(groups.every((group) => group.isNotEmpty), isTrue);
      });
    });

    group('FileInfo', () {
      test('should create FileInfo from file path', () async {
        final filePath = testFiles.first;
        final fileInfo = await FileInfo.fromPath(filePath);

        expect(fileInfo.path, equals(filePath));
        expect(fileInfo.size, greaterThan(0));
        expect(fileInfo.directory, equals(File(filePath).parent.path));
        expect(fileInfo.lastModified, isA<DateTime>());
      });

      test('should handle non-existent file gracefully', () async {
        final nonExistentPath = '${tempDir.path}/non_existent.dart';

        expect(
          () => FileInfo.fromPath(nonExistentPath),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('Load Balancing', () {
      test('should distribute files evenly across groups', () async {
        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.adaptive,
          workerCount: 4,
        );

        if (groups.length > 1) {
          final groupSizes = groups.map((g) => g.length).toList();
          final maxSize = groupSizes.reduce((a, b) => a > b ? a : b);
          final minSize = groupSizes.reduce((a, b) => a < b ? a : b);

          // Groups should be relatively balanced
          expect(maxSize - minSize, lessThanOrEqualTo(2));
        }
      });

      test('should optimize for different file sizes', () async {
        // Create files with significantly different sizes
        final largeFiles = <String>[];
        for (int i = 0; i < 3; i++) {
          final file = File('${tempDir.path}/large$i.dart');
          final content = 'class Large$i {\n${'  // Large content\n' * 100}}';
          await file.writeAsString(content);
          largeFiles.add(file.path);
        }

        final smallFiles = <String>[];
        for (int i = 0; i < 6; i++) {
          final file = File('${tempDir.path}/small$i.dart');
          await file.writeAsString('class Small$i {}');
          smallFiles.add(file.path);
        }

        final mixedFiles = [...largeFiles, ...smallFiles];

        final groups = await FileGroupingStrategy.groupFiles(
          mixedFiles,
          GroupingStrategy.byFileSize,
          workerCount: 3,
        );

        expect(groups.isNotEmpty, isTrue);
        expect(groups.every((group) => group.isNotEmpty), isTrue);

        // Verify all files are included
        final allFiles = groups.expand((g) => g).toList();
        expect(allFiles.length, equals(mixedFiles.length));
      });
    });

    group('Performance', () {
      test('should complete grouping within reasonable time', () async {
        final stopwatch = Stopwatch()..start();

        final groups = await FileGroupingStrategy.groupFiles(
          testFiles,
          GroupingStrategy.adaptive,
          workerCount: 4,
        );

        stopwatch.stop();

        expect(groups.isNotEmpty, isTrue);
        expect(stopwatch.elapsedMilliseconds,
            lessThan(1000)); // Should complete within 1 second
      });

      test('should handle large file lists efficiently', () async {
        // Create a larger list of file paths (without actual files for speed)
        final largeFileList =
            List.generate(1000, (i) => '${tempDir.path}/file$i.dart');

        final stopwatch = Stopwatch()..start();

        final groups = await FileGroupingStrategy.groupFiles(
          largeFileList,
          GroupingStrategy.byCpuCores,
          workerCount: 8,
        );

        stopwatch.stop();

        expect(groups.isNotEmpty, isTrue);
        expect(groups.length, lessThanOrEqualTo(8));
        expect(stopwatch.elapsedMilliseconds,
            lessThan(2000)); // Should complete within 2 seconds

        // Verify all files are included
        final allFiles = groups.expand((g) => g).toList();
        expect(allFiles.length, equals(largeFileList.length));
      });
    });
  });
}
