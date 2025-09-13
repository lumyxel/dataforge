import 'package:dataforge_annotation/dataforge_annotation.dart';

part 'override_test.model.data.dart';

@Dataforge()
class OverrideTestModel with _OverrideTestModel {
  @override
  final String name;
  @override
  final int value;
  @override
  final bool isActive;

  const OverrideTestModel({
    required this.name,
    required this.value,
    required this.isActive,
  });

  factory OverrideTestModel.fromJson(Map<String, dynamic> json) {
    return OverrideTestModel(
      name: json['name'] as String,
      value: json['value'] as int,
      isActive: json['isActive'] as bool,
    );
  }
}
