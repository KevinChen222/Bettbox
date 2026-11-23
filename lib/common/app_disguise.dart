import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/plugins/app.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class AppDisguisePreset {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color backgroundColor;

  const AppDisguisePreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.backgroundColor,
  });

  static const defaultPreset = AppDisguisePreset(
    id: 'default',
    title: '默认（Bettbox Smart）',
    subtitle: '原始应用图标与名称',
    icon: Icons.bolt_rounded,
    backgroundColor: Color(0xFF00897B),
  );

  static const notes = AppDisguisePreset(
    id: 'notes',
    title: '笔记',
    subtitle: '伪装为记事本图标与名称',
    icon: Icons.description_outlined,
    backgroundColor: Color(0xFFF59E0B),
  );

  static const calculator = AppDisguisePreset(
    id: 'calculator',
    title: '计算器',
    subtitle: '伪装为计算器图标与名称',
    icon: Icons.calculate_outlined,
    backgroundColor: Color(0xFF1E293B),
  );

  static const toolbox = AppDisguisePreset(
    id: 'toolbox',
    title: '实用工具',
    subtitle: '伪装为通用工具图标与名称',
    icon: Icons.grid_view_rounded,
    backgroundColor: Color(0xFF0D9488),
  );

  static const List<AppDisguisePreset> values = [
    defaultPreset,
    notes,
    calculator,
    toolbox,
  ];

  static AppDisguisePreset fromId(String? id) {
    return values.firstWhere(
      (preset) => preset.id == id,
      orElse: () => defaultPreset,
    );
  }
}

String effectiveAppName(String? customAppName) {
  final trimmed = customAppName?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }
  return appName;
}

File? resolveCustomAppIconFile(String? iconPath) {
  final trimmed = iconPath?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final file = File(trimmed);
  return file.existsSync() ? file : null;
}

Uint8List encodeSquareAppIconPng(Uint8List rawBytes, {int size = 256}) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or invalid image format');
  }
  final oriented = img.bakeOrientation(decoded);
  final side = oriented.width < oriented.height
      ? oriented.width
      : oriented.height;
  final offsetX = (oriented.width - side) ~/ 2;
  final offsetY = (oriented.height - side) ~/ 2;
  final cropped = oriented.width == oriented.height
      ? oriented
      : img.copyCrop(oriented, x: offsetX, y: offsetY, width: side, height: side);
  final resized = cropped.width == size
      ? cropped
      : img.copyResize(
          cropped,
          width: size,
          height: size,
          interpolation: img.Interpolation.cubic,
        );
  return Uint8List.fromList(img.encodePng(resized));
}

Future<String> saveCustomAppIconFromFile(
  String sourcePath, {
  String? previousPath,
  String? targetDirPath,
}) async {
  final rawBytes = await File(sourcePath).readAsBytes();
  final pngBytes = await Isolate.run(() => encodeSquareAppIconPng(rawBytes));
  final dirPath = targetDirPath ?? await appPath.homeDirPath;
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  final targetPath = p.join(
    dir.path,
    'custom_app_icon_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await File(targetPath).writeAsBytes(pngBytes, flush: true);
  await deleteCustomAppIcon(previousPath, homeDirPath: dir.path);
  return targetPath;
}

Future<void> deleteCustomAppIcon(String? iconPath, {String? homeDirPath}) async {
  final trimmed = iconPath?.trim();
  if (trimmed == null || trimmed.isEmpty) return;
  try {
    final baseDir = homeDirPath ?? await appPath.homeDirPath;
    final normalizedBase = p.normalize(baseDir);
    final normalizedPath = p.normalize(trimmed);
    if (!p.isWithin(normalizedBase, normalizedPath)) return;
    final file = File(normalizedPath);
    if (file.existsSync()) {
      await file.delete();
    }
  } catch (e) {
    commonPrint.warn('Delete custom app icon failed: $e');
  }
}

Future<void> syncNativeAppDisguise({
  required String? name,
  required String? iconPath,
}) async {
  if (!system.isAndroid) return;
  try {
    final existingIconPath = resolveCustomAppIconFile(iconPath)?.path;
    await app.updateAppDisguise(name: name, iconPath: existingIconPath);
  } catch (e) {
    commonPrint.warn('Sync native app disguise failed: $e');
  }
}
