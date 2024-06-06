// ignore_for_file: deprecated_member_use

@TestOn('vm')
@Timeout(Duration(seconds: 120))
import 'dart:async';

// ignore: unused_import
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_mqtt_interface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_tcp_interface.dart';
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
import 'original/test_utils/database_vm.dart';
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
}

class DualTcpExecutor extends BaseExecutor {
  DualTcpExecutor() : super();

  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
        .hostAll([
      DriftTcpInterface(ipAddress: InternetAddress.anyIPv4, port: 4040),
      DriftMqttInterface(host: '127.0.0.1')
    ], onlyAcceptSingleConnection: true);
    return DatabaseConnection.delayed(_buildRemoteConnection());
  }

  Future<DatabaseConnection> _buildRemoteConnection() async {
    return (await DriftTcpInterface.remote(
            ipAddress: InternetAddress.loopbackIPv4, port: 4040))
        .value!;
  }
}

class DualMqttExecutor extends BaseExecutor {
  DualMqttExecutor() : super();

  @override
  DatabaseConnection createConnection() {
    Database(DatabaseConnection(NativeDatabase(file, logStatements: true)))
        .hostAll([
      DriftTcpInterface(ipAddress: InternetAddress.anyIPv4, port: 4040),
      DriftMqttInterface(host: '127.0.0.1')
    ], onlyAcceptSingleConnection: true);
    return DatabaseConnection.delayed(_buildRemoteConnection());
  }

  Future<DatabaseConnection> _buildRemoteConnection() async {
    return (await DriftMqttInterface.remote(host: '127.0.0.1')).value!;
  }
}

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();
  if (!await BaseExecutor.tempDir.exists()) {
    await BaseExecutor.tempDir.create(recursive: true);
  }
  runAllTests(TCPExecutor());
  runAllTests(MqttExecutor());
  runAllTests(DualTcpExecutor());
  runAllTests(DualMqttExecutor());

  test('can save and restore a database', () async {
    final mainFile = File(join(join(Directory.current.path, 'temp'),
        'drift-save-and-restore-tests-1'));
    final createdForSwap = File(join(join(Directory.current.path, 'temp'),
        'drift-save-and-restore-tests-2'));

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
