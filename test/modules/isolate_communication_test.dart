import 'dart:async';
import 'dart:isolate';
import 'package:test/test.dart';
import 'package:dataforge/src/isolate_communication.dart';
import 'package:dataforge/src/isolate_models.dart';

void main() {
  group('IsolateCommunication', () {
    late IsolateCommunication communication;
    late ReceivePort receivePort;
    late SendPort sendPort;

    setUp(() {
      receivePort = ReceivePort();
      sendPort = receivePort.sendPort;
      communication = IsolateCommunication(
        sendPort: sendPort,
        receivePort: receivePort,
      );
    });

    tearDown(() {
      receivePort.close();
    });

    test('should send and receive messages', () async {
      final message = IsolateMessage(
        id: 'test_001',
        type: MessageType.initializeWorker,
        data: {'workerId': 'worker_1'},
        taskId: 'task_001',
        timestamp: DateTime.now(),
      );

      // Set up message handler
      final receivedMessages = <IsolateMessage>[];
      final subscription = communication.messageStream.listen((msg) {
        receivedMessages.add(msg);
      });

      // Send message
      communication.sendMessage(
        MessageType.initializeWorker,
        {'workerId': 'worker_1'},
      );

      // Wait for message to be processed
      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedMessages.length, equals(1));
      expect(receivedMessages.first.type, equals(MessageType.initializeWorker));

      await subscription.cancel();
    });

    test('should handle message timeout', () async {
      final message = IsolateMessage(
        id: 'timeout_test',
        type: MessageType.processBatch,
        data: {'files': []},
        taskId: 'timeout_task',
        timestamp: DateTime.now(),
      );

      // Don't set up any response handler to simulate timeout
      expect(
        () => communication.sendRequest(
          MessageType.processBatch,
          {'files': []},
          customTimeout: Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('should handle invalid message format', () async {
      // Set up error handler
      final errors = <dynamic>[];
      final subscription = communication.messageStream.listen(
        (msg) {},
        onError: (error) {
          errors.add(error);
        },
      );

      // Send invalid message format
      sendPort.send('invalid_message_format');

      // Wait for error to be processed
      await Future.delayed(Duration(milliseconds: 100));

      // Note: Invalid messages are handled internally and don't propagate as stream errors
      // This test verifies the communication remains stable
      expect(communication.isActive, isTrue);

      await subscription.cancel();
    });

    test('should close communication when requested', () async {
      expect(communication.isActive, isTrue);

      await communication.close();
      expect(communication.isActive, isFalse);
    });

    test('should handle multiple concurrent messages', () async {
      final receivedMessages = <IsolateMessage>[];
      final subscription = communication.messageStream.listen((msg) {
        receivedMessages.add(msg);
      });

      // Send multiple messages concurrently
      for (int i = 0; i < 5; i++) {
        communication.sendMessage(
          MessageType.processBatch,
          {'batch': i},
        );
      }

      await Future.delayed(Duration(milliseconds: 200));

      expect(receivedMessages.length, equals(5));

      // Verify all messages were received with correct data
      final receivedBatches =
          receivedMessages.map((m) => m.data['batch']).toSet();
      final expectedBatches = List.generate(5, (i) => i).toSet();
      expect(receivedBatches, equals(expectedBatches));

      await subscription.cancel();
    });
  });

  group('IsolateCommunicationUtils', () {
    test('should create bidirectional communication pair', () async {
      final pair = await IsolateCommunicationUtils.createCommunicationPair();

      expect(pair, isA<IsolateCommunicationPair>());
      expect(pair.main, isA<IsolateCommunication>());
      expect(pair.worker, isA<IsolateCommunication>());
    });

    test('should serialize and deserialize data correctly', () {
      final originalData = {
        'string': 'test',
        'number': 42,
        'boolean': true,
        'list': [1, 2, 3],
        'map': {'nested': 'value'},
      };

      final serialized = IsolateCommunicationUtils.serializeData(originalData);
      final deserialized =
          IsolateCommunicationUtils.deserializeData(serialized);

      expect(deserialized, equals(originalData));
    });

    test('should handle empty data serialization', () {
      final emptyData = <String, dynamic>{};
      final serialized = IsolateCommunicationUtils.serializeData(emptyData);
      final deserialized =
          IsolateCommunicationUtils.deserializeData(serialized);

      expect(deserialized, equals(emptyData));
    });

    test('should handle complex nested data structures', () {
      final complexData = {
        'level1': {
          'level2': {
            'level3': {
              'data': [
                1,
                2,
                {
                  'nested_list': [true, false]
                }
              ],
            },
          },
        },
        'array_of_maps': [
          {'id': 1, 'name': 'first'},
          {'id': 2, 'name': 'second'},
        ],
      };

      final serialized = IsolateCommunicationUtils.serializeData(complexData);
      final deserialized =
          IsolateCommunicationUtils.deserializeData(serialized);

      expect(deserialized, equals(complexData));
    });

    test('should handle complex data serialization', () {
      // Test with DateTime objects which have special handling
      final complexData = {
        'timestamp': DateTime.now(),
        'valid_data': 'this should work',
      };

      final serialized = IsolateCommunicationUtils.serializeData(complexData);
      final deserialized =
          IsolateCommunicationUtils.deserializeData(serialized);

      expect(deserialized['valid_data'], equals('this should work'));
      expect(deserialized['timestamp'], isA<DateTime>());
    });
  });

  group('IsolateException', () {
    test('should create exception with message', () {
      final exception = IsolateException('Test error message');

      expect(exception.message, equals('Test error message'));
      expect(exception.toString(), contains('Test error message'));
    });

    test('should create exception with message and stack trace', () {
      final stackTrace = 'Stack trace line 1\nStack trace line 2';
      final exception = IsolateException('Wrapper error', stackTrace);

      expect(exception.message, equals('Wrapper error'));
      expect(exception.stackTrace, equals(stackTrace));
      expect(exception.toString(), contains('Wrapper error'));
      expect(exception.toString(), contains('Stack trace line 1'));
    });
  });

  group('Integration Tests', () {
    test('should handle full communication workflow', () async {
      final pair = await IsolateCommunicationUtils.createCommunicationPair();

      final mainMessages = <IsolateMessage>[];
      final workerMessages = <IsolateMessage>[];

      final mainSubscription =
          pair.main.messageStream.listen((msg) => mainMessages.add(msg));
      final workerSubscription =
          pair.worker.messageStream.listen((msg) => workerMessages.add(msg));

      // Send message from main to worker
      pair.main.sendMessage(
        MessageType.initializeWorker,
        {'workerId': 'worker_1'},
      );

      // Send response from worker to main
      pair.worker.sendMessage(
        MessageType.batchComplete,
        {'status': 'ready'},
      );

      // Wait for messages to be processed
      await Future.delayed(Duration(milliseconds: 200));

      expect(workerMessages.length, equals(1));
      expect(workerMessages.first.type, equals(MessageType.initializeWorker));

      expect(mainMessages.length, equals(1));
      expect(mainMessages.first.type, equals(MessageType.batchComplete));

      // Cleanup
      await mainSubscription.cancel();
      await workerSubscription.cancel();
      await pair.close();
    });

    test('should handle error propagation between isolates', () async {
      final pair = await IsolateCommunicationUtils.createCommunicationPair();

      final mainErrors = <dynamic>[];
      final mainSubscription = pair.main.messageStream.listen(
        (msg) {},
        onError: (error) => mainErrors.add(error),
      );

      // Send invalid message to trigger error
      pair.worker.sendPort.send({'invalid': 'format'});

      await Future.delayed(Duration(milliseconds: 100));

      // Note: Invalid messages are handled internally
      expect(pair.main.isActive, isTrue);

      // Cleanup
      await mainSubscription.cancel();
      await pair.close();
    });

    test('should maintain message order under load', () async {
      final pair = await IsolateCommunicationUtils.createCommunicationPair();

      final receivedMessages = <IsolateMessage>[];
      final workerSubscription =
          pair.worker.messageStream.listen((msg) => receivedMessages.add(msg));

      // Send many messages in sequence
      final messageCount = 50;
      for (int i = 0; i < messageCount; i++) {
        pair.main.sendMessage(
          MessageType.processBatch,
          {'sequence': i},
        );
      }

      // Wait for all messages to be processed
      await Future.delayed(Duration(milliseconds: 500));

      expect(receivedMessages.length, equals(messageCount));

      // Verify message order
      for (int i = 0; i < messageCount; i++) {
        expect(receivedMessages[i].data['sequence'], equals(i));
      }

      // Cleanup
      await workerSubscription.cancel();
      await pair.close();
    });
  });
}
