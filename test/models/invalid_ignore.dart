import 'package:dataforge_annotation/dataforge_annotation.dart';

@Dataforge()
class Ignore {
  @override
  @JsonKey(ignore: true)
  final String name; // 修改为可空类型
  @override
  final int age;

  Ignore({
    required this.name, // 移除 required
    required this.age,
  });
}
