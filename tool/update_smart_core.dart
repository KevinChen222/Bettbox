// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'prepare_smart_core.dart' as prepare;

Future<void> main() async {
  final root = p.normalize(
    p.join(File.fromUri(Platform.script).parent.path, '..'),
  );
  final manifestFile = File(p.join(root, 'core', 'smart-source.json'));
  final manifest =
      jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
  final checkout = p.join(root, '.test', 'smart-source');
  if (!Directory(p.join(checkout, '.git')).existsSync()) {
    Directory(checkout).createSync(recursive: true);
    await prepare.git(['init', '--quiet'], checkout);
    await prepare.git([
      'remote',
      'add',
      'origin',
      manifest['repository'] as String,
    ], checkout);
  }
  final remote = await prepare.git(['remote', 'get-url', 'origin'], checkout);
  if ((remote.stdout as String).trim() != manifest['repository']) {
    throw StateError('Unexpected Smart source remote; refusing to fetch.');
  }
  await prepare.git([
    'remote',
    'set-url',
    '--push',
    'origin',
    'DISABLED',
  ], checkout);
  await prepare.git(['fetch', 'origin', manifest['ref'] as String], checkout);
  final latestResult = await prepare.git(['rev-parse', 'FETCH_HEAD'], checkout);
  final latest = (latestResult.stdout as String).trim();
  final previous = manifest['revision'] as String;
  if (previous == latest) {
    print('Smart source is already current: $latest');
    return;
  }
  try {
    await prepare.git(['cat-file', '-e', previous], checkout);
  } on ProcessException {
    await prepare.git(['fetch', 'origin', previous], checkout);
  }
  await prepare.main([]);
  if (exitCode != 0) return;
  // Preserve Bettbox adaptations while merging the old-to-new Smart delta.
  // This also carries changes to the official Mihomo base included by Smart.
  final delta = await prepare.git([
    'diff',
    '--full-index',
    '--binary',
    previous,
    latest,
    '--',
    '*.go',
    'go.mod',
    'go.sum',
  ], checkout);
  final generated = p.join(root, 'core', '.smart-mihomo');
  final patch = File(p.join(generated, '.git', 'incoming-smart.patch'));
  await patch.writeAsString(delta.stdout as String);
  final candidate = {...manifest, 'revision': latest};
  final encoder = const JsonEncoder.withIndent('  ');
  await File(
    p.join(root, '.test', 'smart-candidate.json'),
  ).writeAsString('${encoder.convert(candidate)}\n');
  await prepare.addObjectSource(generated, p.join(checkout, '.git', 'objects'));
  try {
    await prepare.git(
      ['apply', '--3way', '--whitespace=nowarn', patch.path],
      generated,
      environment: {
        'GIT_ALTERNATE_OBJECT_DIRECTORIES': p.join(checkout, '.git', 'objects'),
      },
    );
  } on ProcessException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Resolve conflicts in core/.smart-mihomo, run '
      'dart tool/prepare_smart_core.dart --refresh-patch, then copy '
      '.test/smart-candidate.json to core/smart-source.json. '
      'Do not rerun this updater before saving the resolved patch.',
    );
    exitCode = 1;
    return;
  }
  await prepare.main(['--refresh-patch']);
  await manifestFile.writeAsString('${encoder.convert(candidate)}\n');
  print('Updated Smart source: $previous -> $latest. Run all build checks.');
}
