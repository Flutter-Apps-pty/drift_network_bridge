import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_tcp_interface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';

import '../test/integration_tests/drift_testcases/database/database.dart';
import '../test/original/test_utils/database_vm.dart';

Future<void> main() async {
  preferLocalSqlite3();

  final db =
      Database(DatabaseConnection(NativeDatabase.memory(logStatements: true)));
  db.host(DriftTcpInterface());
}
