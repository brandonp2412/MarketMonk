import 'dart:io';

void main() async {
  final pubspec = File('pubspec.yaml');
  final lines = await pubspec.readAsLines();
  String currentVersion =
      lines.firstWhere((line) => line.startsWith('version:')).split(' ')[1];

  List<String> versionParts = currentVersion.split('.');
  int major = int.parse(versionParts[0]);
  int minor = int.parse(versionParts[1]);
  final last = versionParts[2].split('+');
  int patch = int.parse(last[0]);
  int build = int.parse(last[1]);

  int newPatch = patch + 1;
  int newBuild = build + 1;
  String newVersion = '$major.$minor.$newPatch+$newBuild';

  for (int i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('version:')) {
      lines[i] = 'version: $newVersion';
      break;
    }
  }
  await pubspec.writeAsString(lines.join('\n'));

  await Process.run('git', ['add', 'pubspec.yaml']);
  await Process.run('git', ['commit', '-m', 'Bump version to $newVersion']);
  await Process.run('git', ['tag', 'v$newVersion']);

  await Process.run('git', ['push', 'origin', 'main']);
  await Process.run('git', ['push', 'origin', 'v$newVersion']);
}
