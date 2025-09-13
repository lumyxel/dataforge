import 'package:dataforge_annotation/dataforge_annotation.dart';

part 'alternate_names_priority_test.model.data.dart';

/// Test model for alternateNames operator priority fix
@Dataforge()
class AlternateNamesPriorityTest with _AlternateNamesPriorityTest {
  /// Field with multiple alternate names to test operator priority
  @override
  @JsonKey(name: 'owner', alternateNames: ['ownerCopyright', 'copyright_owner'])
  final String? owner;

  /// Another field with alternateNames for comprehensive testing
  @override
  @JsonKey(name: 'title', alternateNames: ['name', 'displayName'])
  final String? title;

  /// Regular field without alternateNames for comparison
  @override
  final String? description;

  const AlternateNamesPriorityTest({
    this.owner,
    this.title,
    this.description,
  });
  factory AlternateNamesPriorityTest.fromJson(Map<String, dynamic> json) {
    return _AlternateNamesPriorityTest.fromJson(json);
  }
}
