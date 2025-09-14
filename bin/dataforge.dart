import 'dart:io';
import 'package:args/args.dart';
import 'package:dataforge/dataforge.dart';
import 'package:dataforge/src/performance_logger.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser();

  parser.addOption("path", defaultsTo: "");
  parser.addFlag("format", defaultsTo: false, help: "Format generated code");
  parser.addFlag("debug",
      abbr: "d", defaultsTo: false, help: "Enable debug logging");
  parser.addFlag("auto-modify",
      help:
          "Automatically modify source files (add with clauses, @override annotations, and part declarations)",
      defaultsTo: false);
  parser.addFlag("perf-log",
      help: "Enable performance logging to separate file", defaultsTo: false);
  parser.addFlag("help",
      abbr: "h", defaultsTo: false, help: "Show help information");

  final res = parser.parse(args);

  if (res.flag("help")) {
    print('DataForge - Dart data class generator\n');
    print('Usage: dataforge [path] [options]\n');
    print('Arguments:');
    print('  path              Path to generate code (default: lib and test)');
    print('Options:');
    print('  --format          Format generated code');
    print('  -d, --debug       Enable debug logging');
    print(
        '  --auto-modify     Automatically modify source files (add with clauses, @override annotations, and part declarations) [default: false]');
    print('  --perf-log        Enable performance logging to separate file');
    print('  -h, --help        Show this help information');
    return;
  }

  // Handle positional arguments (path can be passed as first argument)
  String path = res.option("path") ?? "";
  if (path.isEmpty && res.rest.isNotEmpty) {
    path = res.rest.first;
  }
  bool shouldFormat = res.flag("format");
  bool debugMode = res.flag("debug");
  bool autoModify = res.flag("auto-modify");
  bool perfLog = res.flag("perf-log");
  List<String> generatedFiles = [];

  // Initialize performance logging if enabled
  if (perfLog) {
    final targetPath = path.isEmpty ? Directory.current.path : path;
    await PerformanceLogger.instance.initialize(targetPath, enabled: true);
  }

  // Record generation start time
  final generationStartTime = DateTime.now();
  if (perfLog) {
    logPerf('🚀 Starting dataforge generation');
    final targetPath = path.isEmpty ? Directory.current.path : path;
    logPerf('  └─ Target path: "$targetPath"');
    logPerf('  └─ Working directory: ${Directory.current.path}');
    logPerf('  └─ Use isolate: true , Auto modify: $autoModify');
  }

  if (debugMode) {
    print('[DEBUG] ${DateTime.now()}: Starting dataforge...');
    print('[DEBUG] Arguments: $args');
  }

  if (debugMode) {
    print('[DEBUG] ${DateTime.now()}: Parsed path: "$path"');
    print('[DEBUG] ${DateTime.now()}: Should format: $shouldFormat');
    print(
        '[DEBUG] ${DateTime.now()}: Current working directory: ${Directory.current.path}');
  }

  // Show loading indicator
  print('🔨 Generating code...');

  // Record generation phase timing
  final codeGenStartTime = DateTime.now();

  if (path.isEmpty) {
    if (debugMode) {
      print(
          '\n[DEBUG] ${DateTime.now()}: Path is empty, generating for lib and test directories');
      print('[DEBUG] ${DateTime.now()}: Starting generate(\'lib\')');
    }

    final libStartTime = DateTime.now();
    final libFiles =
        await generate('lib', debugMode: debugMode, autoModify: autoModify);
    final libEndTime = DateTime.now();
    final libTime = libEndTime.difference(libStartTime).inMilliseconds;

    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: generate(\'lib\') completed, found ${libFiles.length} files');
    }
    if (perfLog) {
      logPerfTiming('📁 Generated lib directory', libTime,
          details: '${libFiles.length} files');
    }
    generatedFiles.addAll(libFiles);

    if (debugMode) {
      print('[DEBUG] ${DateTime.now()}: Starting generate(\'test\')');
    }

    final testStartTime = DateTime.now();
    final testFiles =
        await generate('test', debugMode: debugMode, autoModify: autoModify);
    final testEndTime = DateTime.now();
    final testTime = testEndTime.difference(testStartTime).inMilliseconds;

    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: generate(\'test\') completed, found ${testFiles.length} files');
    }
    if (perfLog) {
      logPerfTiming('📁 Generated test directory', testTime,
          details: '${testFiles.length} files');
    }
    generatedFiles.addAll(testFiles);
  } else {
    if (debugMode) {
      print('\n[DEBUG] ${DateTime.now()}: Starting generate(\'$path\')');
    }

    final pathStartTime = DateTime.now();
    final pathFiles =
        await generate(path, debugMode: debugMode, autoModify: autoModify);
    final pathEndTime = DateTime.now();
    final pathTime = pathEndTime.difference(pathStartTime).inMilliseconds;

    if (debugMode) {
      print(
          '[DEBUG] ${DateTime.now()}: generate(\'$path\') completed, found ${pathFiles.length} files');
    }
    if (perfLog) {
      logPerfTiming('📁 Generated path: $path', pathTime,
          details: '${pathFiles.length} files');
    }
    generatedFiles.addAll(pathFiles);
  }

  final codeGenEndTime = DateTime.now();
  final codeGenTime =
      codeGenEndTime.difference(codeGenStartTime).inMilliseconds;

  if (debugMode) {
    print(
        '[DEBUG] ${DateTime.now()}: Total generated files: ${generatedFiles.length}');
    if (generatedFiles.isNotEmpty) {
      print('[DEBUG] Generated files: ${generatedFiles.join(", ")}');
    }
  }

  // Format only the files that were generated in this run
  int formatTime = 0;
  if (generatedFiles.isNotEmpty) {
    if (shouldFormat) {
      if (debugMode) {
        print('[DEBUG] ${DateTime.now()}: Starting code formatting...');
      }

      final formatStartTime = DateTime.now();
      await _formatGeneratedCode(generatedFiles, debugMode);
      final formatEndTime = DateTime.now();
      formatTime = formatEndTime.difference(formatStartTime).inMilliseconds;

      if (debugMode) {
        print('[DEBUG] ${DateTime.now()}: Code formatting completed');
      }
      if (perfLog) {
        logPerfTiming('🎨 Code formatting', formatTime,
            details: '${generatedFiles.length} files');
      }
    } else {
      print('\n✅ Generated ${generatedFiles.length} files successfully!');
    }
  } else {
    print('\n✅ No files to generate.');
  }

  // Record total execution time and log performance breakdown
  final generationEndTime = DateTime.now();
  final totalTime =
      generationEndTime.difference(generationStartTime).inMilliseconds;

  if (perfLog) {
    // Log performance breakdown
    final breakdown = <String, int>{
      'Code Generation': codeGenTime,
    };
    if (formatTime > 0) {
      breakdown['Code Formatting'] = formatTime;
    }

    // Log breakdown details and total execution time
    PerformanceLogger.instance
        .logBreakdown('Total dataforge execution', totalTime, breakdown);
    logPerfTiming('📊 Files generated', 0,
        details: '${generatedFiles.length} files');
  }

  if (debugMode) {
    print('[DEBUG] ${DateTime.now()}: dataforge execution completed');
  }

  // Close performance logging if enabled
  if (perfLog) {
    await PerformanceLogger.instance.close();
  }
}

/// Automatically format generated code using dart fix and dart format
/// Only processes the files that were generated in this run
Future<void> _formatGeneratedCode(
    List<String> generatedFiles, bool debugMode) async {
  stdout.write('.');

  try {
    if (generatedFiles.isEmpty) {
      return;
    }

    // Run dart fix --apply on each generated file individually
    for (final file in generatedFiles) {
      final fixResult = await Process.run('dart', ['fix', '--apply', file]);
      if (fixResult.exitCode != 0) {
        print('Warning: Failed to apply fixes to $file');
      }
    }

    stdout.write('.');

    // Run dart format on generated files only
    final formatArgs = ['format', ...generatedFiles];
    await Process.run('dart', formatArgs);

    stdout.write('.');
    print('\n✅ Generated ${generatedFiles.length} files successfully!');
  } catch (e) {
    print('\n⚠ Warning: Failed to format generated code: $e');
  }
}
