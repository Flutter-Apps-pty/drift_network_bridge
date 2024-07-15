// ignore_for_file: public_member_api_docs

import 'dart:io';

void kDebugPrint(String message, {bool Function(String str)? cond}) {
  if (!bool.fromEnvironment('dart.vm.profile') &&
      !bool.fromEnvironment('dart.vm.product') &&
      (cond == null || cond(message))) {
    print(message);
  }
}

bool kIsTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
