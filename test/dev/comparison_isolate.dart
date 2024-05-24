// ignore_for_file: deprecated_member_use

@TestOn('vm')
@Timeout(Duration(seconds: 120))
import 'dart:async';
// ignore: unused_import
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:drift/remote.dart';
import 'package:drift_network_bridge/implementation/mqtt/mqtt_database_gateway.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/DriftMqttInterface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/DriftTcpInterface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';
import '../integration_tests/drift_testcases/database/database.dart';
import '../integration_tests/drift_testcases/data/sample_data.dart' as people;
import 'package:test/test.dart';
import '../integration_tests/drift_testcases/suite/crud_tests.dart';
import '../integration_tests/drift_testcases/suite/custom_objects.dart';
import '../integration_tests/drift_testcases/suite/migrations.dart';
import '../integration_tests/drift_testcases/suite/suite.dart';
import '../integration_tests/drift_testcases/suite/transactions.dart';
import '../orginal/test_utils/database_vm.dart';

Future<void> main() async {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    preferLocalSqlite3();
  });

  test('Short lived TCP User Test', () async {
    final connection = DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);

    Completer<User>? userCompleter = Completer();
    await db.networkWithDatabase(
      computation: (database) async {
        final user = await database.getUserById(1);
        print('User: $user');
        userCompleter.complete(user);
      },
      connect: (connection) {
        return Database(connection);
      }, networkInterface: DriftTcpInterface(),
    );

    expect(userCompleter.future, completion(User(
      id: 1,
      name: 'Dash',
      birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
      profilePicture: null,
      preferences: null,
    )));
  });

  test('Create a server based on the existing database TCP', () async {
    final connection = DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);

    final server = await db.networkConnection(DriftTcpInterface());

    final client = Database(await server.connect());
    final user = await client.getUserById(1);
    expect(user, User(
      id: 1,
      name: 'Dash',
      birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
      profilePicture: null,
      preferences: null,
    ));
  });

  test('Simulate 2 different applications TCP' , () async {
    final connection = DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);
    await db.networkConnection(DriftTcpInterface());
    final remote = Database(await DriftTcpInterface.remote());
    final user = await remote.getUserById(1);
    expect(user, User(
      id: 1,
      name: 'Dash',
      birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
      profilePicture: null,
      preferences: null,
    ));
  });

  test('Short lived Mqtt User Test', () async {
    final connection = DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);

    Completer<User>? userCompleter = Completer();
    await db.networkWithDatabase(
      computation: (database) async {
        final user = await database.getUserById(1);
        print('User: $user');
        userCompleter.complete(user);
      },
      connect: (connection) {
        return Database(connection);
      }, networkInterface: DriftMqttInterface(),
    );

    expect(userCompleter.future, completion(User(
      id: 1,
      name: 'Dash',
      birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
      profilePicture: null,
      preferences: null,
    )));
  });

  test('Create a server based on the existing database TCP', () async {
    final connection = DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);

    final server = await db.networkConnection(DriftMqttInterface());

    final client = Database(await server.connect());
    final user = await client.getUserById(1);
    expect(user, User(
      id: 1,
      name: 'Dash',
      birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
      profilePicture: null,
      preferences: null,
    ));
  });

  test('Simulate 2 different applications Mqtt' , () async {
    final connection = DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);
    await db.networkConnection(DriftMqttInterface());
    final remote = Database(await DriftMqttInterface.remote());
    final user = await remote.getUserById(1);
    expect(user, User(
      id: 1,
      name: 'Dash',
      birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
      profilePicture: null,
      preferences: null,
    ));
  });
}
