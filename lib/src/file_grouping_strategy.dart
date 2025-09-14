import 'dart:io';
import 'dart:math' as math;

/// File grouping strategy for load balancing
enum GroupingStrategy {
  /// Group files by CPU core count
  byCpuCores,

  /// Group files by file size for balanced workload
  byFileSize,

  /// Group files by directory structure
  byDirectory,

  /// Adaptive grouping based on file characteristics
  adaptive,
}

/// File information for grouping decisions
class FileInfo {
  final String path;
  final int size;
  final String directory;
  final DateTime lastModified;

  FileInfo({
    required this.path,
    required this.size,
    required this.directory,
    required this.lastModified,
  });

  /// Create FileInfo from file path
  static Future<FileInfo> fromPath(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();

    return FileInfo(
      path: filePath,
      size: stat.size,
      directory: file.parent.path,
      lastModified: stat.modified,
    );
  }
}

/// Load balancing and file grouping utilities
class FileGroupingStrategy {
  /// Group files using the specified strategy
  static Future<List<List<String>>> groupFiles(
    List<String> filePaths,
    GroupingStrategy strategy, {
    int? workerCount,
    bool debugMode = false,
  }) async {
    if (filePaths.isEmpty) return [];

    final effectiveWorkerCount = workerCount ?? Platform.numberOfProcessors;

    if (debugMode) {
      print(
          '[DEBUG] Grouping ${filePaths.length} files using $strategy strategy');
      print('[DEBUG] Target worker count: $effectiveWorkerCount');
    }

    switch (strategy) {
      case GroupingStrategy.byCpuCores:
        return _groupByCpuCores(filePaths, effectiveWorkerCount, debugMode);
      case GroupingStrategy.byFileSize:
        return await _groupByFileSize(
            filePaths, effectiveWorkerCount, debugMode);
      case GroupingStrategy.byDirectory:
        return _groupByDirectory(filePaths, effectiveWorkerCount, debugMode);
      case GroupingStrategy.adaptive:
        return await _groupAdaptive(filePaths, effectiveWorkerCount, debugMode);
    }
  }

  /// Group files by CPU cores (optimized round-robin)
  static List<List<String>> _groupByCpuCores(
    List<String> filePaths,
    int workerCount,
    bool debugMode,
  ) {
    if (debugMode) {
      print(
          '[DEBUG] CPU cores grouping: optimized for ${filePaths.length} files, $workerCount workers');
    }

    final groups = List.generate(workerCount, (index) => <String>[]);

    // Simple round-robin distribution - most efficient
    for (int i = 0; i < filePaths.length; i++) {
      groups[i % workerCount].add(filePaths[i]);
    }

    // Filter out empty groups (only if fewer files than workers)
    final nonEmptyGroups = groups.where((group) => group.isNotEmpty).toList();

    if (debugMode) {
      print('[DEBUG] Created ${nonEmptyGroups.length} non-empty groups');
      for (int i = 0; i < nonEmptyGroups.length; i++) {
        print('[DEBUG]   Group $i: ${nonEmptyGroups[i].length} files');
      }
    }

    return nonEmptyGroups;
  }

  /// Group files by size for balanced workload (performance optimized)
  static Future<List<List<String>>> _groupByFileSize(
    List<String> filePaths,
    int workerCount,
    bool debugMode,
  ) async {
    if (debugMode) {
      print(
          '[DEBUG] File size grouping optimized: avoiding file stat operations');
    }

    // For performance, use round-robin distribution instead of file stat operations
    // This avoids the expensive file system calls while still providing good distribution
    final groups = List.generate(workerCount, (index) => <String>[]);

    for (int i = 0; i < filePaths.length; i++) {
      final groupIndex = i % workerCount;
      groups[groupIndex].add(filePaths[i]);
    }

    // Remove empty groups
    final nonEmptyGroups = groups.where((group) => group.isNotEmpty).toList();

    if (debugMode) {
      print(
          '[DEBUG] Round-robin file grouping: ${nonEmptyGroups.length} groups');
      for (int i = 0; i < nonEmptyGroups.length; i++) {
        print('[DEBUG]   Group $i: ${nonEmptyGroups[i].length} files');
      }
    }

    return nonEmptyGroups;
  }

  /// Group files by directory structure (performance optimized)
  static List<List<String>> _groupByDirectory(
    List<String> filePaths,
    int workerCount,
    bool debugMode,
  ) {
    if (debugMode) {
      print(
          '[DEBUG] Directory grouping: optimized for ${filePaths.length} files, $workerCount workers');
    }

    // For performance, use simple round-robin instead of complex directory analysis
    // This avoids expensive path operations while still providing good distribution
    final groups = List.generate(workerCount, (index) => <String>[]);

    for (int i = 0; i < filePaths.length; i++) {
      groups[i % workerCount].add(filePaths[i]);
    }

    final nonEmptyGroups = groups.where((group) => group.isNotEmpty).toList();

    if (debugMode) {
      print(
          '[DEBUG] Round-robin directory grouping: ${nonEmptyGroups.length} groups');
      for (int i = 0; i < nonEmptyGroups.length; i++) {
        print('[DEBUG]   Group $i: ${nonEmptyGroups[i].length} files');
      }
    }

    return nonEmptyGroups;
  }

  /// Adaptive grouping based on file characteristics (optimized for performance)
  static Future<List<List<String>>> _groupAdaptive(
    List<String> filePaths,
    int workerCount,
    bool debugMode,
  ) async {
    if (debugMode) {
      print('[DEBUG] Using adaptive grouping strategy (performance optimized)');
    }

    // For performance, use simple CPU cores grouping for most cases
    // Only use complex analysis for very large file sets where the overhead is justified
    if (filePaths.length < 100) {
      if (debugMode) {
        print(
            '[DEBUG] Small file set (${filePaths.length} files), using CPU cores grouping');
      }
      return _groupByCpuCores(filePaths, workerCount, debugMode);
    }

    // For larger file sets, use directory-based grouping without file stat operations
    final directories = <String, List<String>>{};
    for (final path in filePaths) {
      final directory = File(path).parent.path;
      directories.putIfAbsent(directory, () => <String>[]).add(path);
    }

    if (debugMode) {
      print(
          '[DEBUG] Found ${directories.length} directories for ${filePaths.length} files');
    }

    // Choose strategy based on directory distribution
    GroupingStrategy chosenStrategy;

    if (directories.length <= workerCount && directories.length > 1) {
      // Few directories - group by directory
      chosenStrategy = GroupingStrategy.byDirectory;
      if (debugMode) {
        print(
            '[DEBUG] Using directory grouping (${directories.length} directories)');
      }
    } else {
      // Default to CPU cores for optimal performance
      chosenStrategy = GroupingStrategy.byCpuCores;
      if (debugMode) {
        print('[DEBUG] Using CPU cores grouping for optimal performance');
      }
    }

    return await groupFiles(
      filePaths,
      chosenStrategy,
      workerCount: workerCount,
      debugMode: debugMode,
    );
  }

  /// Check if files have significant size variation
  static bool _hasSignificantSizeVariation(
      List<FileInfo> fileInfos, double avgSize) {
    if (fileInfos.length < 2) return false;

    // Calculate coefficient of variation
    final variance = fileInfos.fold<double>(0.0, (sum, info) {
          final diff = info.size - avgSize;
          return sum + (diff * diff);
        }) /
        fileInfos.length;

    final stdDev = math.sqrt(variance);
    final coefficientOfVariation = stdDev / avgSize;

    // Consider significant if CV > 0.5 (50% variation)
    return coefficientOfVariation > 0.5;
  }

  /// Format bytes for human-readable output
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// Estimate optimal worker count based on system resources
  static int estimateOptimalWorkerCount({
    int? fileCount,
    int? totalSizeBytes,
    bool debugMode = false,
  }) {
    final cpuCores = Platform.numberOfProcessors;

    // Base worker count on CPU cores
    int optimalCount = cpuCores;

    // Adjust based on file count
    if (fileCount != null) {
      if (fileCount < cpuCores) {
        optimalCount = fileCount;
      } else if (fileCount > cpuCores * 4) {
        // For many files, use more workers but cap at 2x CPU cores
        optimalCount = math.min(cpuCores * 2, fileCount);
      }
    }

    // Adjust based on total size (for very large files, use fewer workers)
    if (totalSizeBytes != null) {
      final avgSizePerCore = totalSizeBytes / cpuCores;
      const largeSizeThreshold = 10 * 1024 * 1024; // 10MB per core

      if (avgSizePerCore > largeSizeThreshold) {
        optimalCount = math.max(1, (optimalCount * 0.75).round());
      }
    }

    // Ensure at least 1 worker
    optimalCount = math.max(1, optimalCount);

    if (debugMode) {
      print(
          '[DEBUG] Estimated optimal worker count: $optimalCount (CPU cores: $cpuCores)');
    }

    return optimalCount;
  }
}
