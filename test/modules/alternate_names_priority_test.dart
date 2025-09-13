import 'package:test/test.dart';
import '../models/alternate_names_priority_test.model.dart';

/// Test cases for alternateNames operator priority fix
void main() {
  group('AlternateNames Priority Tests', () {
    test('should correctly handle alternateNames with proper operator priority',
        () {
      // Test case 1: Primary field name exists
      final json1 = {
        'owner': 'primary_owner',
        'ownerCopyright': 'alternate_owner',
        'title': 'primary_title',
        'name': 'alternate_title',
      };

      final result1 = AlternateNamesPriorityTest.fromJson(json1);
      expect(result1.owner, equals('primary_owner'));
      expect(result1.title, equals('primary_title'));
    });

    test('should fallback to first alternate name when primary is null', () {
      // Test case 2: Primary field is null, use first alternate
      final json2 = {
        'ownerCopyright': 'first_alternate_owner',
        'copyright_owner': 'second_alternate_owner',
        'name': 'first_alternate_title',
        'displayName': 'second_alternate_title',
      };

      final result2 = AlternateNamesPriorityTest.fromJson(json2);
      expect(result2.owner, equals('first_alternate_owner'));
      expect(result2.title, equals('first_alternate_title'));
    });

    test('should fallback to second alternate name when first is null', () {
      // Test case 3: Primary and first alternate are null, use second alternate
      final json3 = {
        'copyright_owner': 'second_alternate_owner',
        'displayName': 'second_alternate_title',
      };

      final result3 = AlternateNamesPriorityTest.fromJson(json3);
      expect(result3.owner, equals('second_alternate_owner'));
      expect(result3.title, equals('second_alternate_title'));
    });

    test('should handle all fields as null when no matching keys exist', () {
      // Test case 4: No matching keys exist
      final json4 = {
        'unknown_field': 'some_value',
        'another_field': 'another_value',
      };

      final result4 = AlternateNamesPriorityTest.fromJson(json4);
      expect(result4.owner, isNull);
      expect(result4.title, isNull);
      expect(result4.description, isNull);
    });

    test('should handle mixed scenarios correctly', () {
      // Test case 5: Mixed scenario - some fields use alternates, others don't
      final json5 = {
        'ownerCopyright': 'alternate_owner', // owner field uses alternate
        'title': 'primary_title', // title field uses primary
        'description': 'some_description', // description field (no alternates)
      };

      final result5 = AlternateNamesPriorityTest.fromJson(json5);
      expect(result5.owner, equals('alternate_owner'));
      expect(result5.title, equals('primary_title'));
      expect(result5.description, equals('some_description'));
    });

    test('should verify generated code has correct parentheses', () {
      // This test verifies that the operator priority fix is working
      // by ensuring the ?? operator works correctly with multiple alternates
      final json6 = {
        'copyright_owner': 'last_alternate',
      };

      final result6 = AlternateNamesPriorityTest.fromJson(json6);
      // If parentheses are missing, this would fail due to operator priority
      expect(result6.owner, equals('last_alternate'));
    });
  });
}
