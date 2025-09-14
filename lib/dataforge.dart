import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

import 'package:dataforge/src/parser.dart';
import 'package:dataforge/src/writer.dart';
import 'package:dataforge/src/isolate_worker_pool.dart';
import 'package:dataforge/src/performance_logger.dart';

/// Generate data classes for Dart files in the specified directory or file
///
/// [path] can be a directory or a single file
/// [autoModify] if true, will automatically modify the original files
/// [debugMode] if true, will print debug information
/// [useIsolate] if true, will use isolate for concurrent processing
Future<List<String>> generate(String path,
    {bool debugMode = false,
    bool autoModify = false,
    bool useIsolate = true}) async {
  final startTime = DateTime.now();
  if (debugMode) {
    print('[PERF] 🚀 $startTime: Starting dataforge generation');
    print('[PERF]   └─ Target path: "$path"');
    print('[PERF]   └─ Working directory: ${Directory.current.path}');
    print('[PERF]   └─ Use isolate: $useIsolate, Auto modify: $autoModify');
  }

  // Performance logging is handled at the CLI level in bin/dataforge.dart

  if (useIsolate) {
    return await _generateWithIsolate(
      path,
      autoModify: autoModify,
      debugMode: debugMode,
    );
  }

  // Convert relative path to absolute path to ensure consistent behavior
  // regardless of the working directory from which the command is run
  final absolutePath =
      p.isAbsolute(path) ? path : p.join(Directory.current.path, path);
  if (debugMode) {
    print('[DEBUG] ${DateTime.now()}: Resolved absolute path: "$absolutePath"');
  }

  final generatedFiles = <String>[];
  final entity = FileSystemEntity.typeSync(absolutePath);
  final isDirectory = entity == FileSystemEntityType.directory;

  // Initialize timing variables
  int scanTime = 0;
  int filterTime = 0;
  int parallelTime = 0;
  int collectTime = 0;

  if (debugMode) {
    print('[PERF] ${DateTime.now()}: 🚀 Starting generation');
    print('[PERF]   └─ Target path: "$absolutePath"');
    print('[PERF]   └─ Working directory: "${Directory.current.path}"');
    print('[PERF]   └─ Is directory: $isDirectory');
    print('[PERF]   └─ Use isolates: ${useIsolate ? 'Yes' : 'No'}');
    print('[PERF]   └─ Auto modify: ${autoModify ? 'Yes' : 'No'}');
  }

  // Log to performance file if enabled
  logPerf('🚀 Starting generation');
  logPerf('  └─ Target path: "$absolutePath"');
  logPerf('  └─ Working directory: "${Directory.current.path}"');
  logPerf('  └─ Is directory: $isDirectory');
  logPerf('  └─ Use isolates: ${useIsolate ? 'Yes' : 'No'}');
  logPerf('  └─ Auto modify: ${autoModify ? 'Yes' : 'No'}');

  if (isDirectory) {
    // Step 1: Directory scanning
    final scanStartTime = DateTime.now();
    if (debugMode) {
      print('[PERF] $scanStartTime: 📁 Starting directory scan');
    }
    logPerf('$scanStartTime: 📁 Starting directory scan');

    // Optimized file scanning with depth limit and better filtering
    final files =
        _scanDirectory(absolutePath, maxDepth: 10, debugMode: debugMode);
    final scanEndTime = DateTime.now();
    final scanTime = scanEndTime.difference(scanStartTime).inMilliseconds;

    if (debugMode) {
      print('[PERF] $scanEndTime: ⏱️  Directory scan: ${scanTime}ms');
      print('[PERF]   └─ Found ${files.length} dart files');
    }
    logPerfTiming('Directory scan', scanTime);
    logPerf('  └─ Found ${files.length} dart files');

    // Step 2: Pre-filter files to find those with Dataforge annotations
    final filterStartTime = DateTime.now();
    if (debugMode) {
      print('[PERF] $filterStartTime: 🔍 Starting annotation pre-filtering');
    }
    logPerf('$filterStartTime: 🔍 Starting annotation pre-filtering');

    final candidateFiles = <String>[];
    int preFilteredCount = 0;
    int totalFileSize = 0;

    for (final filePath in files) {
      try {
        final file = File(filePath);
        final fileSize = file.lengthSync();
        totalFileSize += fileSize;

        if (_hasDataforgeAnnotations(filePath)) {
          candidateFiles.add(filePath);
        } else {
          preFilteredCount++;
        }
      } catch (e) {
        preFilteredCount++;
        if (debugMode) {
          print('[PERF] ⚠️  Error reading file $filePath: $e');
        }
        logPerf('⚠️  Error reading file $filePath: $e');
      }
    }

    final filterEndTime = DateTime.now();
    final filterTime = filterEndTime.difference(filterStartTime).inMilliseconds;
    final avgFileSize = files.isNotEmpty
        ? (totalFileSize / files.length / 1024).toStringAsFixed(1)
        : '0';

    if (debugMode) {
      print('[PERF] $filterEndTime: ⏱️  Pre-filtering: ${filterTime}ms');
      print('[PERF]   └─ Total files: ${files.length} (avg ${avgFileSize}KB)');
      print(
          '[PERF]   └─ Candidates: ${candidateFiles.length}, Skipped: $preFilteredCount');
    }
    logPerfTiming('Pre-filtering', filterTime);
    logPerf('  └─ Total files: ${files.length} (avg ${avgFileSize}KB)');
    logPerf(
        '  └─ Candidates: ${candidateFiles.length}, Skipped: $preFilteredCount');

    if (candidateFiles.isEmpty) {
      if (debugMode) {
        print('No files with @Dataforge annotations found. in $absolutePath');
      }
      return generatedFiles;
    }

    // Step 3: Process files in parallel with controlled concurrency
    final parallelStartTime = DateTime.now();
    if (debugMode) {
      print('[PERF] $parallelStartTime: ⚙️  Starting parallel processing');
      print('[PERF]   └─ Max concurrency: ${Platform.numberOfProcessors}');
    }
    logPerf('$parallelStartTime: ⚙️  Starting parallel processing');
    logPerf('  └─ Max concurrency: ${Platform.numberOfProcessors}');

    final maxConcurrency = Platform.numberOfProcessors;
    final processedResults = await _processFilesInParallel(
        candidateFiles, absolutePath, maxConcurrency, debugMode, autoModify);

    final parallelEndTime = DateTime.now();
    final parallelTime =
        parallelEndTime.difference(parallelStartTime).inMilliseconds;

    // Step 4: Collect results
    final collectStartTime = DateTime.now();
    int processedCount = 0;
    for (final result in processedResults) {
      if (result.isNotEmpty) {
        generatedFiles.add(result);
        processedCount++;
      }
    }
    final collectEndTime = DateTime.now();
    final collectTime =
        collectEndTime.difference(collectStartTime).inMilliseconds;

    if (debugMode) {
      print(
          '[PERF] $parallelEndTime: ⏱️  Parallel processing: ${parallelTime}ms');
      print('[PERF]   └─ Concurrency: $maxConcurrency workers');
      print('[PERF] $collectEndTime: ⏱️  Result collection: ${collectTime}ms');
      print(
          '[PERF]   └─ Processed: $processedCount, Generated: ${generatedFiles.length}');
    }
    logPerfTiming('Parallel processing', parallelTime);
    logPerf('  └─ Concurrency: $maxConcurrency workers');
    logPerfTiming('Result collection', collectTime);
    logPerf(
        '  └─ Processed: $processedCount, Generated: ${generatedFiles.length}');
  } else {
    if (debugMode) {
      print('[DEBUG] ${DateTime.now()}: Processing single file: $absolutePath');
    }

    // Skip generated .data.dart files
    if (absolutePath.endsWith('.data.dart')) {
      if (debugMode) {
        print(
            '[DEBUG] ${DateTime.now()}: Skipping .data.dart file: $absolutePath');
      }
      return generatedFiles;
    }

    // Skip certain special directories and files
    if (_shouldSkipFile(absolutePath,
        basePath:
            absolutePath.contains('/') ? p.dirname(absolutePath) : null)) {
      if (debugMode) {
        print(
            '[DEBUG] ${DateTime.now()}: Skipping file due to filter: $absolutePath');
      }
      return generatedFiles;
    }

    // Pre-filter: Quick content scan for annotations
    if (!_hasDataforgeAnnotations(absolutePath)) {
      if (debugMode) {
        print(
            '[DEBUG] ${DateTime.now()}: Skipping file without @Dataforge annotations: $absolutePath');
      }
      return generatedFiles;
    }

    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: Creating parser for single file: $absolutePath');
    }

    final parseStartTime = DateTime.now();
    final parser = Parser(absolutePath);
    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: Starting parseDartFile() for single file: $absolutePath');
    }
    final parseRes = parser.parseDartFile();
    final parseEndTime = DateTime.now();

    if (debugMode) {
      final parseTime = parseEndTime.difference(parseStartTime).inMilliseconds;
      print(
          '[DEBUG] ${DateTime.now()}: parseDartFile() completed for single file: $absolutePath, result: ${parseRes != null ? 'success' : 'null'}, time: ${parseTime}ms');
    }

    if (parseRes != null) {
      if (debugMode) {
        print(
            '[DEBUG] ${DateTime.now()}: Creating writer for single file: $absolutePath');
      }
      final writeStartTime = DateTime.now();
      final writer = Writer(parseRes,
          projectRoot: p.dirname(absolutePath),
          debugMode: debugMode,
          autoModify: autoModify);
      if (debugMode) {
        print(
            '[DEBUG] ${DateTime.now()}: Starting writeCodeAsync() for single file: $absolutePath');
      }
      final generatedFile = await writer.writeCodeAsync();
      final writeEndTime = DateTime.now();

      if (debugMode) {
        final writeTime =
            writeEndTime.difference(writeStartTime).inMilliseconds;
        print(
            '[DEBUG] ${DateTime.now()}: writeCodeAsync() completed for single file: $absolutePath, generated: ${generatedFile.isNotEmpty ? generatedFile : 'empty'}, time: ${writeTime}ms');
      }

      if (generatedFile.isNotEmpty) {
        generatedFiles.add(generatedFile);
      }
    }
  }
  // Final performance summary
  final endTime = DateTime.now();
  final totalTime = endTime.difference(startTime).inMilliseconds;

  if (debugMode) {
    print('[PERF] 🏁 $endTime: Generation completed in ${totalTime}ms');
    print('[PERF]   └─ Generated files: ${generatedFiles.length}');
    if (isDirectory) {
      print('[PERF]   └─ Time breakdown:');
      print(
          '[PERF]     ├─ Directory scan: ${scanTime}ms (${(scanTime / totalTime * 100).toStringAsFixed(1)}%)');
      print(
          '[PERF]     ├─ Pre-filtering: ${filterTime}ms (${(filterTime / totalTime * 100).toStringAsFixed(1)}%)');
      print(
          '[PERF]     ├─ Parallel processing: ${parallelTime}ms (${(parallelTime / totalTime * 100).toStringAsFixed(1)}%)');
      print(
          '[PERF]     └─ Result collection: ${collectTime}ms (${(collectTime / totalTime * 100).toStringAsFixed(1)}%)');
    }
  }

  // Log performance summary to file if enabled
  logPerf('🏁 Generation completed in ${totalTime}ms');
  logPerf('  └─ Generated files: ${generatedFiles.length}');
  if (isDirectory) {
    logPerf('  └─ Time breakdown:');
    logPerf(
        '    ├─ Directory scan: ${scanTime}ms (${(scanTime / totalTime * 100).toStringAsFixed(1)}%)');
    logPerf(
        '    ├─ Pre-filtering: ${filterTime}ms (${(filterTime / totalTime * 100).toStringAsFixed(1)}%)');
    logPerf(
        '    ├─ Parallel processing: ${parallelTime}ms (${(parallelTime / totalTime * 100).toStringAsFixed(1)}%)');
    logPerf(
        '    └─ Result collection: ${collectTime}ms (${(collectTime / totalTime * 100).toStringAsFixed(1)}%)');
  }

  if (generatedFiles.isNotEmpty) {
    print('✅ Generated ${generatedFiles.length} files in ${totalTime}ms');
  }

  return generatedFiles;
}

/// Generate data classes using isolate-based concurrent processing
///
/// [path] can be a directory or a single file
/// [autoModify] if true, will automatically modify the original files
/// [debugMode] if true, will print debug information
Future<List<String>> _generateWithIsolate(
  String path, {
  bool autoModify = false,
  bool debugMode = false,
}) async {
  final startTime = DateTime.now();
  if (debugMode) {
    print('[DEBUG] Starting isolate-based generation for: $path');
  }

  // Convert relative path to absolute path
  final absolutePath = Directory(path).absolute.path;
  final projectRoot = _findProjectRoot(absolutePath);

  if (debugMode) {
    print('[DEBUG] Project root: $projectRoot');
  }

  // Collect all Dart files that need processing
  final dartFiles = <String>[];
  final entity = FileSystemEntity.typeSync(absolutePath);

  if (entity == FileSystemEntityType.file) {
    if (absolutePath.endsWith('.dart') &&
        _hasDataforgeAnnotations(absolutePath)) {
      dartFiles.add(absolutePath);
    }
  } else if (entity == FileSystemEntityType.directory) {
    dartFiles.addAll(_scanDirectory(absolutePath));
  } else {
    throw ArgumentError('Path does not exist or is not accessible: $path');
  }

  if (dartFiles.isEmpty) {
    if (debugMode) {
      print('[DEBUG] No files with @dataforge annotations found');
    }
    return [];
  }

  if (debugMode) {
    print('[DEBUG] Found ${dartFiles.length} files to process with isolates');
  }

  // Initialize isolate worker pool
  final workerPool = IsolateWorkerPool(
    debugMode: debugMode,
  );

  try {
    // Initialize the worker pool
    await workerPool.initialize();

    if (debugMode) {
      print(
          '[DEBUG] Worker pool initialized with ${workerPool.workerCount} workers');
    }

    // Submit tasks for processing
    final generatedFiles = await workerPool.submitTasks(
      dartFiles,
      projectRoot,
      autoModify: autoModify,
    );

    final processingTime = DateTime.now().difference(startTime).inMilliseconds;
    if (debugMode) {
      print('[DEBUG] Isolate processing completed in ${processingTime}ms');
      print('[DEBUG] Generated ${generatedFiles.length} files');

      // Print pool statistics
      final stats = workerPool.statistics;
      print('[DEBUG] Pool statistics:');
      print('  - Workers: ${stats['workerCount']}');
      print('  - Tasks processed: ${stats['totalTasksProcessed']}');
      print('  - Files processed: ${stats['totalFilesProcessed']}');
      print('  - Total processing time: ${stats['totalProcessingTime']}ms');
      print(
          '  - Average processing time: ${stats['averageProcessingTime'].toStringAsFixed(2)}ms');
    }

    return generatedFiles;
  } finally {
    // Always shutdown the worker pool
    await workerPool.shutdown();
  }
}

/// Find the project root directory by looking for pubspec.yaml
String _findProjectRoot(String startPath) {
  var current = Directory(startPath);

  // If startPath is a file, start from its parent directory
  if (FileSystemEntity.typeSync(startPath) == FileSystemEntityType.file) {
    current = current.parent;
  }

  // Walk up the directory tree looking for pubspec.yaml
  while (current.path != current.parent.path) {
    final pubspecFile = File('${current.path}/pubspec.yaml');
    if (pubspecFile.existsSync()) {
      return current.path;
    }
    current = current.parent;
  }

  // If no pubspec.yaml found, return the original directory
  return Directory(startPath).parent.path;
}

/// Optimized directory scanning with depth limit and better filtering
List<String> _scanDirectory(String path,
    {int maxDepth = 10, bool debugMode = false}) {
  final dartFiles = <String>[];
  final startTime = DateTime.now();

  void scanRecursive(String currentPath, int currentDepth) {
    if (currentDepth > maxDepth) return;

    try {
      final dir = Directory(currentPath);
      if (!dir.existsSync()) return;

      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          // Skip common directories that don't contain source code
          if (_shouldSkipDirectory(dirName)) {
            if (debugMode) {
              print(
                  '[DEBUG] ${DateTime.now()}: Skipping directory: ${entity.path}');
            }
            continue;
          }
          scanRecursive(entity.path, currentDepth + 1);
        } else if (entity is File && entity.path.endsWith('.dart')) {
          final filePath = entity.absolute.path;

          // Skip generated .data.dart files
          if (filePath.endsWith('.data.dart')) {
            continue;
          }

          // Skip certain special files
          if (_shouldSkipFile(filePath, basePath: path)) {
            continue;
          }

          dartFiles.add(filePath);
        }
      }
    } catch (e) {
      if (debugMode) {
        print(
            '[DEBUG] ${DateTime.now()}: Error scanning directory $currentPath: $e');
      }
    }
  }

  scanRecursive(path, 0);

  if (debugMode) {
    final scanTime = DateTime.now().difference(startTime).inMilliseconds;
    print(
        '[DEBUG] ${DateTime.now()}: Directory scan completed in ${scanTime}ms, found ${dartFiles.length} dart files');
  }

  return dartFiles;
}

/// Check if directory should be skipped
bool _shouldSkipDirectory(String dirName) {
  const skipDirs = {
    '.dart_tool',
    '.git',
    '.idea',
    '.vscode',
    'build',
    '.pub-cache',
    'node_modules',
    '.packages',
    'coverage',
    'doc',
    'docs',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    'ios',
    'android',
    'web',
    'windows',
    'macos',
    'linux',
  };
  return skipDirs.contains(dirName);
}

/// Quick pre-filter to check if file contains Dataforge annotations
bool _hasDataforgeAnnotations(String filePath) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return false;

    // Read file content efficiently
    final content = file.readAsStringSync();

    // Quick string search for annotations - support both @Dataforge and @Dataforge()
    return content.contains('@Dataforge') ||
        content.contains('@dataforge') ||
        content.contains('@DataClass') ||
        content.contains('dataforge_annotation');
  } catch (e) {
    // If we can't read the file, skip it
    return false;
  }
}

/// Determine whether a file should be skipped
bool _shouldSkipFile(String filePath, {String? basePath}) {
  // Skip files in excluded directories (this is a backup check)
  if (filePath.contains('/.dart_tool/') ||
      filePath.contains('/.git/') ||
      filePath.contains('/build/') ||
      filePath.contains('/.idea/') ||
      filePath.contains('/.pub-cache/') ||
      filePath.contains('/node_modules/')) {
    return true;
  }
  return false;
}

/// Process files in parallel with controlled concurrency
/// Returns a list of generated file paths
Future<List<String>> _processFilesInParallel(
  List<String> filePaths,
  String projectRoot,
  int maxConcurrency,
  bool debugMode,
  bool autoModify,
) async {
  final results = <String>[];

  // Split files into batches for controlled concurrency
  final batches = <List<String>>[];
  for (int i = 0; i < filePaths.length; i += maxConcurrency) {
    final end = (i + maxConcurrency < filePaths.length)
        ? i + maxConcurrency
        : filePaths.length;
    batches.add(filePaths.sublist(i, end));
  }

  if (debugMode) {
    print(
        '[DEBUG] ${DateTime.now()}: Processing ${filePaths.length} files in ${batches.length} batches (max concurrency: $maxConcurrency)');
  }

  // Process each batch in parallel
  for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
    final batch = batches[batchIndex];
    final batchStartTime = DateTime.now();

    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: Processing batch ${batchIndex + 1}/${batches.length} with ${batch.length} files');
    }

    // Process files in current batch concurrently
    final batchFutures = batch.map((filePath) =>
        _processFile(filePath, projectRoot, debugMode, autoModify));
    final batchResults = await Future.wait(batchFutures);

    results.addAll(batchResults);

    final batchEndTime = DateTime.now();
    final batchTime = batchEndTime.difference(batchStartTime).inMilliseconds;

    if (debugMode) {
      final successCount = batchResults.where((r) => r.isNotEmpty).length;
      print(
          '[DEBUG] ${DateTime.now()}: Batch ${batchIndex + 1} completed in ${batchTime}ms ($successCount/${batch.length} successful)');
    }
  }

  return results;
}

/// Process a single file and return the generated file path
Future<String> _processFile(String filePath, String projectRoot, bool debugMode,
    bool autoModify) async {
  try {
    final fileStartTime = DateTime.now();

    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: Processing file: ${p.basename(filePath)}');
    }

    // Parse the file
    final parseStartTime = DateTime.now();
    final parser = Parser(filePath);
    final parseRes = parser.parseDartFile();
    final parseEndTime = DateTime.now();

    if (parseRes == null) {
      if (debugMode) {
        final parseTime =
            parseEndTime.difference(parseStartTime).inMilliseconds;
        print(
            '[DEBUG] ${DateTime.now()}: Parse failed for ${p.basename(filePath)} in ${parseTime}ms');
      }
      return '';
    }

    // Generate code
    final writeStartTime = DateTime.now();
    final writer = Writer(parseRes,
        projectRoot: projectRoot, debugMode: debugMode, autoModify: autoModify);
    final generatedFile = await writer.writeCodeAsync();
    final writeEndTime = DateTime.now();

    final fileEndTime = DateTime.now();

    if (debugMode) {
      final parseTime = parseEndTime.difference(parseStartTime).inMilliseconds;
      final writeTime = writeEndTime.difference(writeStartTime).inMilliseconds;
      final totalTime = fileEndTime.difference(fileStartTime).inMilliseconds;
      print(
          '[DEBUG] ${DateTime.now()}: File ${p.basename(filePath)} completed in ${totalTime}ms (parse:${parseTime}ms, write:${writeTime}ms)');
    }

    return generatedFile;
  } catch (e) {
    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: Error processing ${p.basename(filePath)}: $e');
    }
    return '';
  }
}
