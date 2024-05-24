import 'dart:io';

Future<void> main() async {
  // Directory where the drift repository will be cloned or updated
  final String targetDir = 'packages/drift';

  // Git repository URL
  final String repoUrl = 'https://github.com/simolus3/drift.git';

  // Branch to checkout
  final String branch = 'latest-release';

  final directory = Directory(targetDir);

  if (await directory.exists()) {
    // If directory exists, reset and pull latest changes
    print('Updating the repository in $targetDir...');
    await Process.run('git', ['reset', '--hard'], workingDirectory: targetDir);
    await Process.run('git', ['clean', '-fd'], workingDirectory: targetDir);
    await Process.run('git', ['pull'], workingDirectory: targetDir);
    await Process.run('git', ['checkout', branch], workingDirectory: targetDir);
    await Process.run('git', ['pull', 'origin', branch], workingDirectory: targetDir);
    print('Repository updated.');
  } else {
    // If directory does not exist, clone the repository
    print('Cloning the repository into $targetDir...');
    await Process.run('git', ['clone', '-b', branch, repoUrl, targetDir]);
    print('Repository cloned.');
  }
}

