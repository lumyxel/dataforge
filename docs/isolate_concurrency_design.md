# Isolate 并发处理架构设计文档

## 概述

本文档描述了 DataForge 项目中基于 CPU 核心数的 Isolate 并发处理架构设计。该架构旨在通过真正的并行处理来提升大项目中多文件解析和代码生成的性能。

## 当前架构分析

### 现有实现

当前的并发处理使用 `Future.wait()` 进行批处理：

```dart
// 当前的批处理方式
final maxConcurrency = Platform.numberOfProcessors;
final batchFutures = batch.map((filePath) => _processFile(filePath, projectRoot, debugMode, autoModify));
final batchResults = await Future.wait(batchFutures);
```

### 现有架构的限制

1. **单线程限制**: 所有处理都在主 Isolate 中进行，无法利用多核 CPU
2. **内存压力**: 大量文件同时处理可能导致内存峰值过高
3. **阻塞风险**: 单个文件处理异常可能影响整个批次

## 新架构设计

### 核心思想

1. **文件分组**: 根据 CPU 核心数将文件列表平均分组
2. **Isolate 池**: 为每个分组创建独立的 Isolate 工作进程
3. **任务分发**: 主 Isolate 负责任务分发和结果收集
4. **资源管理**: 合理控制 Isolate 数量和生命周期

### 架构组件

#### 1. IsolateWorkerPool (Isolate 工作池)

```dart
class IsolateWorkerPool {
  final int workerCount;
  final List<IsolateWorker> workers;
  final Queue<WorkTask> taskQueue;
  
  // 初始化工作池
  Future<void> initialize();
  
  // 提交任务
  Future<List<String>> submitTasks(List<String> filePaths);
  
  // 关闭工作池
  Future<void> shutdown();
}
```

#### 2. IsolateWorker (单个 Isolate 工作进程)

```dart
class IsolateWorker {
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;
  
  // 启动 Isolate
  Future<void> start();
  
  // 处理任务
  Future<List<String>> processBatch(List<String> filePaths);
  
  // 停止 Isolate
  Future<void> stop();
}
```

#### 3. WorkTask (工作任务)

```dart
class WorkTask {
  final List<String> filePaths;
  final String projectRoot;
  final bool debugMode;
  final bool autoModify;
  final Completer<List<String>> completer;
}
```

### 文件分组策略

#### 分组算法

```dart
List<List<String>> _groupFilesByCpuCores(List<String> files) {
  final coreCount = Platform.numberOfProcessors;
  final groupSize = (files.length / coreCount).ceil();
  
  final groups = <List<String>>[];
  for (int i = 0; i < files.length; i += groupSize) {
    final end = math.min(i + groupSize, files.length);
    groups.add(files.sublist(i, end));
  }
  
  return groups;
}
```

#### 负载均衡

- **文件大小权重**: 考虑文件大小进行更智能的分组
- **动态调整**: 根据处理速度动态调整任务分配
- **故障转移**: 单个 Isolate 异常时的任务重分配

### Isolate 通信协议

#### 消息类型

```dart
enum MessageType {
  initializeWorker,    // 初始化工作进程
  processBatch,        // 处理文件批次
  batchComplete,       // 批次处理完成
  workerError,         // 工作进程错误
  shutdown,            // 关闭工作进程
}
```

#### 消息格式

```dart
class IsolateMessage {
  final MessageType type;
  final Map<String, dynamic> data;
  final String? taskId;
}
```

### 性能优化策略

#### 1. 预热机制

```dart
// Isolate 预热，避免冷启动开销
Future<void> _warmupIsolates() async {
  for (final worker in workers) {
    await worker.processBatch([]); // 空批次预热
  }
}
```
