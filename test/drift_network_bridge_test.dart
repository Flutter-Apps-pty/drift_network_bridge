// ignore_for_file: deprecated_member_use

@TestOn('vm')
@Timeout(Duration(seconds: 120))
import 'dart:async';
// ignore: unused_import
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:drift/remote.dart';
import 'package:drift_network_bridge/implementation/mqtt/mqtt_database_gateway.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/DriftMqttInterface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/DriftTcpInterface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';
import 'integration_tests/drift_testcases/database/database.dart';
import 'integration_tests/drift_testcases/data/sample_data.dart' as people;
import 'package:test/test.dart';
import 'integration_tests/drift_testcases/suite/crud_tests.dart';
import 'integration_tests/drift_testcases/suite/custom_objects.dart';
import 'integration_tests/drift_testcases/suite/migrations.dart';
import 'integration_tests/drift_testcases/suite/suite.dart';
import 'integration_tests/drift_testcases/suite/transactions.dart';
import 'orginal/test_utils/database_vm.dart';
// import 'database/database.dart';

class NbExecutor extends TestExecutor {
  final MqttDatabaseGateway gw;
  // late DatabaseConnection clientConn;
  NbExecutor(this.gw);

  @override
  bool get supportsReturning => true;

  @override
  bool get supportsNestedTransactions => true;

  Completer? closedCompleter;


  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection.delayed(Future.sync(() async {
      // final isolate = await createIsolate();
      final connection = gw.createConnection();
      await (connection.connect());
      // return isolate.connect(singleClientMode: true);
      return await connectToRemoteAndInitialize(connection);
    }));
  }


  @override
  Future clearDatabaseAndClose(Database db) async {
    closedCompleter = Completer();
    for (var table in db.allTables) {
      await db.customStatement('DELETE FROM ${table.actualTableName}');
      await db.customStatement('DELETE FROM sqlite_sequence WHERE name = "${table.actualTableName}"');
    }
    await db.transaction(() async {
      await db.batch((batch) {
        batch.insertAll(
            db.users, [people.dash, people.duke, people.gopher]);
      });
    });
    closedCompleter!.complete();
  }

  @override
  Future<void> deleteData() async {

  }

}

class TCPExecutor extends TestExecutor {
  // late DatabaseConnection clientConn;
  TCPExecutor();

  @override
  bool get supportsReturning => true;

  @override
  bool get supportsNestedTransactions => true;

  Completer? closedCompleter;


  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase.memory(logStatements: true,))).networkConnection(DriftTcpInterface());
    final connection =DatabaseConnection.delayed(Future.sync(() async {
      return await DriftTcpInterface.remote();
    }));

    return connection;
  }


  @override
  Future clearDatabaseAndClose(Database db) async {
    // closedCompleter = Completer();
    // for (var table in db.allTables) {
    //   // await db.customStatement('DELETE FROM ${table.actualTableName}');
    //   // await db.customStatement('DELETE FROM sqlite_sequence WHERE name = "${table.actualTableName}"');
    // }
    // await db.transaction(() async {
    //   await db.batch((batch) {
    //     batch.insertAll(
    //         db.users, [people.dash, people.duke, people.gopher]);
    //   });
    // });
    // closedCompleter!.complete();
  }

  @override
  Future<void> deleteData() async {

  }

}

class MqttExecutor extends TestExecutor {
  // late DatabaseConnection clientConn;
  MqttExecutor();

  @override
  bool get supportsReturning => true;

  @override
  bool get supportsNestedTransactions => true;

  Completer? closedCompleter;


  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase.memory(logStatements: true,))).networkConnection(DriftMqttInterface());
    final connection =DatabaseConnection.delayed(Future.sync(() async {
      return await DriftMqttInterface.remote();
    }));

    return connection;
  }


  @override
  Future clearDatabaseAndClose(Database db) async {
    // closedCompleter = Completer();
    // for (var table in db.allTables) {
    //   // await db.customStatement('DELETE FROM ${table.actualTableName}');
    //   // await db.customStatement('DELETE FROM sqlite_sequence WHERE name = "${table.actualTableName}"');
    // }
    // await db.transaction(() async {
    //   await db.batch((batch) {
    //     batch.insertAll(
    //         db.users, [people.dash, people.duke, people.gopher]);
    //   });
    // });
    // closedCompleter!.complete();
  }

  @override
  Future<void> deleteData() async {

  }

}

Future<void> main() async {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    preferLocalSqlite3();
  });
  // final db = Database(DatabaseConnection(NativeDatabase.memory(logStatements: true,)));
  // final gate = MqttDatabaseGateway('127.0.0.1', 'unit_device', 'drift/test_site',);

  // gate.serve(db);
  // await gate.isReady;
  // await Future.delayed(Duration(seconds: 5));
  // final executer = NbExecutor(gate);
  // runAllTests(TCPExecutor());
  runAllTests(MqttExecutor());
}
void runAllTests(TestExecutor executor) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() async {
    await executor.deleteData();
  });

  crudTests(executor);
  customObjectTests(executor);
  migrationTests(executor); //todo figure out how to test migrations
  transactionTests(executor);

  test('can close database without interacting with it', () async {
    final connection = executor.createConnection();

    await connection.executor.close();
  });
}

Matcher toString(Matcher matcher) => _ToString(matcher);

class _ToString extends CustomMatcher {
  _ToString(Matcher matcher)
      : super("Object string represent is", "toString()", matcher);

  @override
  Object? featureValueOf(dynamic actual) => actual.toString();
}
