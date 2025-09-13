import 'package:dataforge_annotation/dataforge_annotation.dart';

part 'widget_skeleton_test.model.data.dart';

@Dataforge()
class WidgetSkeletonModel with _TokenBean, _WidgetSkeletonModel {
  @override
  final String name;
  @override
  final String value;

  const WidgetSkeletonModel({
    required this.name,
    required this.value,
  });
  factory WidgetSkeletonModel.fromJson(Map<String, dynamic> json) {
    return _WidgetSkeletonModel.fromJson(json);
  }
}

mixin _TokenBean {
  // Mock mixin class
}
