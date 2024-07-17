@TestOn('vm')
@Timeout(Duration(seconds: 120))
import 'dart:async';

// ignore: unused_import
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_network_bridge/drift_network_bridge.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_mqtt_interface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_tcp_interface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';
import 'package:path/path.dart';
import '../../integration_tests/drift_testcases/database/database.dart';
import '../../integration_tests/drift_testcases/data/sample_data.dart'
    as people;
import 'package:test/test.dart';
import '../../integration_tests/drift_testcases/suite/crud_tests.dart';
import '../../integration_tests/drift_testcases/suite/custom_objects.dart';
import '../../integration_tests/drift_testcases/suite/migrations.dart';
import '../../integration_tests/drift_testcases/suite/suite.dart';
import '../../integration_tests/drift_testcases/suite/transactions.dart';
import '../../interceptor/log_interceptor.dart';
import '../../original/test_utils/database_vm.dart';
// import 'database/database.dart';

abstract class BaseExecutor extends TestExecutor {
  static String fileName = 'drift-native-tests.sqlite';
  static Directory tempDir = Directory(join(Directory.current.path, 'temp'));
  late File file;

  BaseExecutor() {
    file = File(join(tempDir.path, fileName));
  }

  @override
  bool get supportsReturning => true;

  @override
  bool get supportsNestedTransactions => true;

  Completer? closedCompleter;

  @override
  Future clearDatabaseAndClose(Database db) async {
    closedCompleter = Completer();
    for (var table in db.allTables) {
      await db.customStatement('DELETE FROM ${table.actualTableName}');
      await db.customStatement(
          'DELETE FROM sqlite_sequence WHERE name = "${table.actualTableName}"');
    }
    await db.transaction(() async {
      await db.batch((batch) {
        batch.insertAll(db.users, [people.dash, people.duke, people.gopher]);
      });
    });
    closedCompleter!.complete();
  }

  @override
  Future<void> deleteData() async {
    final ref = Database.executor(NativeDatabase(file));
    await clearDatabaseAndClose(ref);
    ref.close();
  }
}

class TCPExecutor extends BaseExecutor {
  TCPExecutor() : super();

  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
        .host(DriftTcpInterface(), onlyAcceptSingleConnection: true);
    return DatabaseConnection.delayed(_buildRemoteConnection());
  }

  Future<DatabaseConnection> _buildRemoteConnection() async {
    return (await DriftTcpInterface.remote(
            ipAddress: InternetAddress.loopbackIPv4, port: 4040))
        .value!;
  }
}

class MqttExecutor extends BaseExecutor {
  MqttExecutor() : super();

  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
        .host(DriftMqttInterface(host: '127.0.0.1'),
            onlyAcceptSingleConnection: true);
    return DatabaseConnection.delayed(_buildRemoteConnection());
  }

  Future<DatabaseConnection> _buildRemoteConnection() async {
    return (await DriftMqttInterface.remote(host: '127.0.0.1')).value!;
  }

  @override
  Future clearDatabaseAndClose(Database db) async {
    await super.clearDatabaseAndClose(db);

    /// allow time before next test start for latency to resolve
    await Future.delayed(Duration(milliseconds: 500));
  }
}

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();

  final remoteAccess =
      RemoteDatabase<Database>((conn) => Database(conn), DriftTcpInterface());
  await remoteAccess.asyncDb;

  final users = await remoteAccess.db()!.users.select().get();

  print(users);
}
