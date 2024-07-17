import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_network_bridge/drift_network_bridge.dart';
import 'package:path/path.dart';

import '../../integration_tests/drift_testcases/database/database.dart';
import '../../interceptor/log_interceptor.dart';
import '../../original/test_utils/database_vm.dart';
import 'drift_interceptor_select.dart';

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();
  if (!await BaseExecutor.tempDir.exists()) {
    await BaseExecutor.tempDir.create(recursive: true);
  }

  final file = File(join(BaseExecutor.tempDir.path, BaseExecutor.fileName));

  Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
      .hostAll([
    DriftTcpInterface(),
    DriftMqttInterface(
      host: 'test.mosquitto.org',
    )
  ], onlyAcceptSingleConnection: true, interceptor: LogInterceptor());

  while (true) {
    await Future.delayed(Duration(seconds: 1));
  }
}
