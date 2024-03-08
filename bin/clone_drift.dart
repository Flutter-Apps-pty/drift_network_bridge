import 'dart:io';

Future<void> main() async {
  // Directory where the drift repository will be cloned or updated
  final String targetDir = 'packages/drift';

  // Git repository URL
  final String repoUrl = 'https://github.com/simolus3/drift.git';

  final directory = Directory(targetDir);

  if (await directory.exists()) {
    // If directory exists, reset and pull latest changes
    print('Updating the repository in $targetDir...');
    await Process.run('git', ['reset', '--hard'], workingDirectory: targetDir);
    await Process.run('git', ['clean', '-fd'], workingDirectory: targetDir);
    await Process.run('git', ['pull'], workingDirectory: targetDir);
    print('Repository updated.');
  } else {
    // If directory does not exist, clone the repository
    print('Cloning the repository into $targetDir...');
    await Process.run('git', ['clone', repoUrl, targetDir]);
    print('Repository cloned.');
  }
}
