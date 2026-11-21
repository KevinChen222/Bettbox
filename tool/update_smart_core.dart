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
  final generated = p.join(root, 'core', '.smart-mihomo');
  const sourcePaths = ['*.go', 'go.mod', 'go.sum'];
  final deleted = await prepare.git([
    'diff',
    '--name-only',
    '-z',
    '--no-renames',
    '--diff-filter=D',
    previous,
    latest,
    '--',
    ...sourcePaths,
  ], checkout);
  final tracked = await prepare.git(['ls-files', '-z'], generated);
  final trackedPaths = (tracked.stdout as String).split('\x00').toSet();
  // Bettbox may already have applied some deletions from the shared Mihomo base.
  final alreadyDeleted = (deleted.stdout as String)
      .split('\x00')
      .where((path) => path.isNotEmpty && !trackedPaths.contains(path))
      .map((path) => ':(exclude,literal)$path');
  // Preserve Bettbox adaptations while merging the old-to-new Smart delta.
  final delta = await prepare.git([
    'diff',
    '--no-renames',
    '--full-index',
    '--binary',
    previous,
    latest,
    '--',
    ...sourcePaths,
    ...alreadyDeleted,
  ], checkout);
  final patch = File(p.join(generated, '.git', 'incoming-smart.patch'));
  final incoming = delta.stdout as String;
  await patch.writeAsString(incoming);
  final candidate = {...manifest, 'revision': latest};
  final encoder = const JsonEncoder.withIndent('  ');
  await File(p.join(root, '.test', 'smart-candidate.json'))
      .writeAsString('${encoder.convert(candidate)}\n');
  await prepare.addObjectSource(generated, p.join(checkout, '.git', 'objects'));
  try {
    if (incoming.isNotEmpty) {
      await prepare.git([
        'apply',
        '--3way',
        '--whitespace=nowarn',
        patch.path,
      ], generated);
    }
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
