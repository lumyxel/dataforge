# 工具脚本

这个目录包含了项目的辅助工具脚本。

## format_project.dart - 一键格式化脚本

这个脚本可以一键执行 `dart fix --apply` 和 `dart format` 来格式化整个工程。

### 使用方法

```bash
# 格式化整个项目（默认）
dart run tools/format_project.dart

# 格式化指定目录
dart run tools/format_project.dart -p lib
dart run tools/format_project.dart --path test

# 显示帮助信息
dart run tools/format_project.dart --help
```

### 功能特点

- 🔧 **自动修复**: 使用 `dart fix --apply` 自动修复代码问题
- 🎨 **代码格式化**: 使用 `dart format` 格式化代码风格
- 📁 **灵活路径**: 支持指定要格式化的目录
- 🚀 **友好反馈**: 提供详细的执行进度和结果反馈
- ❌ **错误处理**: 完善的错误处理和用户提示

### 与代码生成器的区别

- **代码生成器** (`bin/data_class_gen.dart`): 只格式化本次生成的 `.data.dart` 文件
- **格式化脚本** (`tools/format_project.dart`): 格式化整个项目或指定目录的所有 Dart 文件

### 示例输出

```
🚀 开始格式化项目...
📁 目标路径: .

🔧 正在执行 dart fix --apply...
   ✅ dart fix --apply . 执行成功
   📝 输出: Computing fixes in data_class_gen...
Nothing to fix!
🎨 正在执行 dart format...
   ✅ dart format . 执行成功
   📝 输出: Formatted 39 files (3 changed) in 0.34 seconds.

✅ 项目格式化完成！
```

## 其他工具

### update_version.dart - 版本更新工具

用于更新项目版本号的工具脚本。