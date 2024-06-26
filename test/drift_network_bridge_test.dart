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
import 'package:path/path.dart';
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
      await db.customStatement('DELETE FROM sqlite_sequence WHERE name = "${table.actualTableName}"');
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

class NbExecutor extends BaseExecutor {
  final MqttDatabaseGateway gw;

  NbExecutor(this.gw) : super();

  @override
  DatabaseConnection createConnection() {
    return DatabaseConnection.delayed(Future.sync(() async {
      final connection = gw.createConnection();
      await connection.connect();
      return await connectToRemoteAndInitialize(connection);
    }));
  }
}

class TCPExecutor extends BaseExecutor {
  TCPExecutor() : super();

  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
        .networkConnection(DriftTcpInterface());
    final connection = DatabaseConnection.delayed(Future.sync(() async {
      return await DriftTcpInterface.remote();
    }));

    return connection;
  }
}

class MqttExecutor extends BaseExecutor {
  MqttExecutor() : super();

  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
        .networkConnection(DriftMqttInterface());
    final connection = DatabaseConnection.delayed(Future.sync(() async {
      return await DriftMqttInterface.remote();
    }));

    return connection;
  }
}

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();
  final Directory tempDir = Directory(join(Directory.current.path, 'temp'));
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }

  // final gate = MqttDatabaseGateway('127.0.0.1', 'unit_device', 'drift/test_site');
  // await gate.serve(Database(DatabaseConnection(NativeDatabase.memory(logStatements: true))));
  // await gate.isReady;

  // runAllTests(NbExecutor(gate));
  runAllTests(TCPExecutor());
  runAllTests(MqttExecutor());
  // final db = Database(DatabaseConnection(NativeDatabase.memory(logStatements: true,)));
  // final gate = MqttDatabaseGateway('127.0.0.1', 'unit_device', 'drift/test_site',);

  // gate.serve(db);
  // await gate.isReady;
  // await Future.delayed(Duration(seconds: 5));
  // final executer = NbExecutor(gate);
  // runAllTests(TCPExecutor());
  // runAllTests(MqttExecutor());

  test('can save and restore a database', () async {
    final mainFile =
    File(join(join(Directory.current.path,'temp'), 'drift-save-and-restore-tests-1'));
    final createdForSwap =
    File(join(join(Directory.current.path,'temp'), 'drift-save-and-restore-tests-2'));

    if (await mainFile.exists()) {
      await mainFile.delete();
    }
    if (await createdForSwap.exists()) {
      await createdForSwap.delete();
    }

    const nameInSwap = 'swap user';
    const nameInMain = 'main';

    // Prepare the file we're swapping in later
    final dbForSetup = Database.executor(NativeDatabase(createdForSwap));
    await dbForSetup.into(dbForSetup.users).insert(
        UsersCompanion.insert(name: nameInSwap, birthDate: DateTime.now()));
    await dbForSetup.close();

    // Open the main file
    var db = Database.executor(NativeDatabase(mainFile));
    await db.into(db.users).insert(
        UsersCompanion.insert(name: nameInMain, birthDate: DateTime.now()));
    await db.close();

    // Copy swap file to main file
    await mainFile.writeAsBytes(await createdForSwap.readAsBytes(),
        flush: true);

    // Re-open database
    db = Database.executor(NativeDatabase(mainFile));
    final users = await db.select(db.users).get();

    expect(
      users.map((u) => u.name),
      allOf(contains(nameInSwap), isNot(contains(nameInMain))),
    );
  });
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
