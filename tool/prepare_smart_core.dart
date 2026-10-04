// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<ProcessResult> git(
  List<String> args,
  String cwd, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    'git',
    ['-c', 'safe.directory=${cwd.replaceAll('\\', '/')}', ...args],
    workingDirectory: cwd,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

Future<void> addObjectSource(String checkout, String objects) async {
  final alternates = File(
    p.join(checkout, '.git', 'objects', 'info', 'alternates'),
  );
  await alternates.parent.create(recursive: true);
  final sink = alternates.openWrite(mode: FileMode.append);
  sink.writeln(p.normalize(objects).replaceAll('\\', '/'));
  await sink.close();
}

Future<void> main(List<String> args) async {
  final root = p.normalize(
    p.join(File.fromUri(Platform.script).parent.path, '..'),
  );
  final source = p.join(root, 'core', 'Clash.Meta');
  final generated = p.join(root, 'core', '.smart-mihomo');
  final patch = File(p.join(root, 'core', 'smart.patch'));

  if (args.contains('--refresh-patch')) {
    // Only operate on the disposable generated checkout, never the app index.
    await git(['diff', '--check'], generated);
    await git(['add', '--all'], generated);
    final diff = await git([
      'diff',
      '--cached',
      '--full-index',
      '--binary',
      'HEAD',
    ], generated);
    if ((diff.stdout as String).isEmpty) {
      throw StateError('No Smart changes found; refusing to empty the patch.');
    }
    await patch.writeAsString(diff.stdout as String);
    print('Updated core/smart.patch from the resolved generated kernel.');
    return;
  }

  final objects = await git(['rev-parse', '--git-path', 'objects'], root);
  final objectPath = p.absolute(
    p.join(root, (objects.stdout as String).trim()),
  );
  final output = Directory(generated);
  if (output.existsSync()) {
    if (!p.isWithin(p.join(root, 'core'), output.absolute.path) ||
        p.basename(output.path) != '.smart-mihomo') {
      throw StateError('Unexpected generated kernel path: ${output.path}');
    }
    output.deleteSync(recursive: true);
  }
  output.createSync(recursive: true);
  for (final entity in Directory(source).listSync(recursive: true)) {
    final target = p.join(generated, p.relative(entity.path, from: source));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
  await git(['init', '--quiet'], generated);
  await addObjectSource(generated, objectPath);
  await git(['add', '--all'], generated);
  await git([
    '-c',
    'user.name=Bettbox Smart build',
    '-c',
    'user.email=smart-build@localhost',
    '-c',
    'commit.gpgsign=false',
    'commit',
    '--quiet',
    '-m',
    'Bettbox kernel before Smart overlay',
  ], generated);
  try {
    await git([
      'apply',
      '--3way',
      '--whitespace=nowarn',
      patch.path,
    ], generated);
  } on ProcessException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Resolve the reported conflicts in core/.smart-mihomo, '
      'then run dart tool/prepare_smart_core.dart --refresh-patch. '
      'Do not rebuild until the patch has been refreshed. '
      'A full Git history is required for three-way merging.',
    );
    exitCode = 1;
    return;
  }
  print('Prepared Smart kernel in core/.smart-mihomo');
}
