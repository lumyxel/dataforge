import 'dart:async';
import 'package:test/test.dart';
import 'package:dataforge/src/isolate_models.dart';

void main() {
  group('MessageType', () {
    test('should have all required message types', () {
      expect(MessageType.values.length, equals(7));
      expect(MessageType.values, contains(MessageType.initializeWorker));
      expect(MessageType.values, contains(MessageType.processBatch));
      expect(MessageType.values, contains(MessageType.batchComplete));
      expect(MessageType.values, contains(MessageType.workerError));
      expect(MessageType.values, contains(MessageType.shutdown));
      expect(MessageType.values, contains(MessageType.error));
      expect(MessageType.values, contains(MessageType.success));
    });
  });

  group('IsolateMessage', () {
    test('should create message with required fields', () {
      final timestamp = DateTime.now();
      final message = IsolateMessage(
        id: 'test-id',
        type: MessageType.processBatch,
        data: {'key': 'value'},
        timestamp: timestamp,
        taskId: 'task-1',
      );

      expect(message.id, equals('test-id'));
      expect(message.type, equals(MessageType.processBatch));
      expect(message.data, equals({'key': 'value'}));
      expect(message.timestamp, equals(timestamp));
      expect(message.taskId, equals('task-1'));
    });

    test('should serialize to JSON correctly', () {
      final timestamp = DateTime.now();
      final message = IsolateMessage(
        id: 'test-id',
        type: MessageType.processBatch,
        data: {
          'files': ['file1.dart', 'file2.dart']
        },
        timestamp: timestamp,
        taskId: 'task-1',
      );

      final json = message.toJson();

      expect(json['id'], equals('test-id'));
      expect(json['type'], equals(MessageType.processBatch.index));
      expect(
          json['data'],
          equals({
            'files': ['file1.dart', 'file2.dart']
          }));
      expect(json['timestamp'], equals(timestamp.millisecondsSinceEpoch));
      expect(json['taskId'], equals('task-1'));
    });

    test('should deserialize from JSON correctly', () {
      final timestamp = DateTime.now();
      final json = {
        'id': 'test-id',
        'type': MessageType.batchComplete.index,
        'data': {
          'results': ['result1', 'result2']
        },
        'timestamp': timestamp.millisecondsSinceEpoch,
        'taskId': 'task-1',
      };

      final message = IsolateMessage.fromJson(json);

      expect(message.id, equals('test-id'));
      expect(message.type, equals(MessageType.batchComplete));
      expect(
          message.data,
          equals({
            'results': ['result1', 'result2']
          }));
      expect(message.timestamp, equals(timestamp));
      expect(message.taskId, equals('task-1'));
    });

    test('should handle null taskId', () {
      final timestamp = DateTime.now();
      final message = IsolateMessage(
        id: 'test-id',
        type: MessageType.shutdown,
        data: {},
        timestamp: timestamp,
      );

      expect(message.taskId, isNull);

      final json = message.toJson();
      expect(json['taskId'], isNull);

      final deserializedMessage = IsolateMessage.fromJson(json);
      expect(deserializedMessage.taskId, isNull);
    });
  });

  group('WorkTask', () {
    test('should create work task with required fields', () {
      final task = WorkTask(
        taskId: 'task-1',
        filePaths: ['file1.dart', 'file2.dart'],
        projectRoot: '/project/root',
        debugMode: false,
        autoModify: true,
      );

      expect(task.taskId, equals('task-1'));
      expect(task.filePaths, equals(['file1.dart', 'file2.dart']));
      expect(task.projectRoot, equals('/project/root'));
      expect(task.debugMode, isFalse);
      expect(task.autoModify, isTrue);
      expect(task.completer, isA<Completer<List<String>>>());
    });

    test('should serialize to data map correctly', () {
      final task = WorkTask(
        taskId: 'task-1',
        filePaths: ['file1.dart', 'file2.dart'],
        projectRoot: '/project/root',
        debugMode: true,
        autoModify: false,
      );

      final data = task.toData();

      expect(data['taskId'], equals('task-1'));
      expect(data['filePaths'], equals(['file1.dart', 'file2.dart']));
      expect(data['projectRoot'], equals('/project/root'));
      expect(data['debugMode'], isTrue);
      expect(data['autoModify'], isFalse);
    });

    test('should deserialize from data map correctly', () {
      final data = {
        'taskId': 'task-1',
        'filePaths': ['file1.dart', 'file2.dart'],
        'projectRoot': '/project/root',
        'debugMode': true,
        'autoModify': false,
      };

      final task = WorkTask.fromData(data);

      expect(task.taskId, equals('task-1'));
      expect(task.filePaths, equals(['file1.dart', 'file2.dart']));
      expect(task.projectRoot, equals('/project/root'));
      expect(task.debugMode, isTrue);
      expect(task.autoModify, isFalse);
    });

    test('should handle task completion via completer', () async {
      final task = WorkTask(
        taskId: 'task-1',
        filePaths: ['file1.dart'],
        projectRoot: '/project/root',
        debugMode: false,
        autoModify: true,
      );

      expect(task.completer.isCompleted, isFalse);

      // Simulate task completion
      final results = ['Generated file1.data.dart'];
      task.completer.complete(results);

      expect(task.completer.isCompleted, isTrue);
      final completedResults = await task.completer.future;
      expect(completedResults, equals(results));
    });
  });

  group('WorkerStatus', () {
    test('should have all required worker statuses', () {
      expect(WorkerStatus.values.length, equals(5));
      expect(WorkerStatus.values, contains(WorkerStatus.initializing));
      expect(WorkerStatus.values, contains(WorkerStatus.idle));
      expect(WorkerStatus.values, contains(WorkerStatus.busy));
      expect(WorkerStatus.values, contains(WorkerStatus.error));
      expect(WorkerStatus.values, contains(WorkerStatus.shutdown));
    });
  });

  group('WorkerStats', () {
    test('should create worker stats with default values', () {
      final stats = WorkerStats();

      expect(stats.tasksProcessed, equals(0));
      expect(stats.filesProcessed, equals(0));
      expect(stats.totalProcessingTime, equals(0));
      expect(stats.averageProcessingTime, equals(0.0));
    });

    test('should update stats when task is completed', () {
      final stats = WorkerStats();
      final fileCount = 3;
      final processingTime = 500;

      stats.updateStats(fileCount, processingTime);

      expect(stats.tasksProcessed, equals(1));
      expect(stats.filesProcessed, equals(3));
      expect(stats.totalProcessingTime, equals(500));
      expect(stats.averageProcessingTime, equals(500.0 / 3));
    });

    test('should calculate average processing time correctly', () {
      final stats = WorkerStats();

      stats.updateStats(2, 100); // 2 files, 100ms
      stats.updateStats(3, 200); // 3 files, 200ms
      stats.updateStats(1, 50); // 1 file, 50ms

      expect(stats.tasksProcessed, equals(3));
      expect(stats.filesProcessed, equals(6));
      expect(stats.totalProcessingTime, equals(350));
      expect(stats.averageProcessingTime, equals(350.0 / 6));
    });

    test('should handle zero files processed', () {
      final stats = WorkerStats();
      expect(stats.averageProcessingTime, equals(0.0));
    });
  });
}
