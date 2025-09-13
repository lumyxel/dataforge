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

#### 2. 内存管理

- **分批处理**: 避免一次性加载过多文件
- **垃圾回收**: 定期触发 GC 释放内存
- **资源监控**: 监控内存使用情况

#### 3. 错误处理

- **超时机制**: 设置任务处理超时
- **重试策略**: 失败任务的重试机制
- **降级处理**: Isolate 不可用时回退到单线程处理

## 实现计划

### 阶段 1: 核心组件实现

1. 实现 `IsolateWorkerPool` 类
2. 实现 `IsolateWorker` 类
3. 设计消息通信协议

### 阶段 2: 文件处理逻辑迁移

1. 将现有的 `_processFile` 逻辑迁移到 Isolate 中
2. 实现文件分组算法
3. 集成到现有的 `generate` 函数

### 阶段 3: 性能优化和测试

1. 添加性能监控和调试日志
2. 实现错误处理和重试机制
3. 进行性能基准测试

### 阶段 4: 配置和调优

1. 添加并发配置选项
2. 实现自适应负载均衡
3. 优化内存使用

## 预期收益

### 性能提升

- **CPU 利用率**: 充分利用多核 CPU，理论上可获得接近核心数倍的性能提升
- **处理速度**: 大项目文件处理速度显著提升
- **响应性**: 主线程不被阻塞，保持良好的响应性

### 资源优化

- **内存分布**: 内存负载分散到多个 Isolate
- **故障隔离**: 单个文件处理错误不影响其他文件
- **可扩展性**: 可根据硬件配置动态调整并发度

## 风险和挑战

### 技术风险

1. **Isolate 开销**: Isolate 创建和通信的开销
2. **内存增长**: 多个 Isolate 可能增加总内存使用
3. **调试复杂性**: 多进程调试的复杂性增加

### 缓解策略

1. **性能基准**: 建立详细的性能基准测试
2. **渐进式部署**: 提供开关控制新旧架构
3. **监控告警**: 添加资源使用监控

## 配置选项

```dart
class ConcurrencyConfig {
  final bool enableIsolateProcessing;  // 是否启用 Isolate 处理
  final int? maxWorkers;               // 最大工作进程数
  final int batchSize;                 // 批处理大小
  final Duration taskTimeout;          // 任务超时时间
  final bool enablePrewarm;            // 是否启用预热
}
```

## 总结

基于 Isolate 的并发处理架构将显著提升 DataForge 在处理大型项目时的性能。通过合理的文件分组、Isolate 池管理和错误处理机制，可以在保证稳定性的同时最大化利用硬件资源。

该架构的实现将分阶段进行，确保每个阶段都有充分的测试和验证，最终为用户提供更快、更稳定的代码生成体验。