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
import '../integration_tests/drift_testcases/database/database.dart';
import 'package:test/test.dart';
import '../original/test_utils/database_vm.dart';

Future<void> main() async {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    preferLocalSqlite3();
  });

  test('Short lived TCP User Test', () async {
    final connection =
        DatabaseConnection(NativeDatabase.memory(logStatements: true));
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
      },
      networkInterface: DriftTcpInterface(),
    );

    expect(
        userCompleter.future,
        completion(User(
          id: 1,
          name: 'Dash',
          birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
          profilePicture: null,
          preferences: null,
        )));
  });

  test('Create a server based on the existing database TCP', () async {
    final connection =
        DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);

    final server = await db.host(DriftTcpInterface());
    final connRslt = await server.connect();
    if (connRslt.isError) {
      throw connRslt.error!;
    }
    final client = Database(connRslt.value!);
    final user = await client.getUserById(1);
    expect(
        user,
        User(
          id: 1,
          name: 'Dash',
          birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
          profilePicture: null,
          preferences: null,
        ));
  });

  test('Simulate 2 different applications TCP', () async {
    final connection =
        DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);
    await db.host(
        DriftTcpInterface(ipAddress: InternetAddress.anyIPv4, port: 4040));
    final remoteConnection = await DriftTcpInterface.remote(
        ipAddress: InternetAddress.loopbackIPv4, port: 4040);
    final remote = Database(remoteConnection.value!);
    final user = await remote.getUserById(1);
    expect(
        user,
        User(
          id: 1,
          name: 'Dash',
          birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
          profilePicture: null,
          preferences: null,
        ));
  });

  test('Short lived Mqtt User Test', () async {
    final connection =
        DatabaseConnection(NativeDatabase.memory(logStatements: true));
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
      },
      networkInterface:
          DriftMqttInterface(host: 'test.mosquitto.org', name: 'unit_device'),
    );

    expect(
        userCompleter.future,
        completion(User(
          id: 1,
          name: 'Dash',
          birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
          profilePicture: null,
          preferences: null,
        )));
  });

  test('Create a server based on the existing database TCP', () async {
    final connection =
        DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);

    final server = await db.host(
        DriftMqttInterface(host: 'test.mosquitto.org', name: 'unit_device'));
    final connRslt = await server.connect();
    if (connRslt.isError) {
      throw connRslt.error!;
    }
    final client = Database(connRslt.value!);
    final user = await client.getUserById(1);
    expect(
        user,
        User(
          id: 1,
          name: 'Dash',
          birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
          profilePicture: null,
          preferences: null,
        ));
  });

  test('Simulate 2 different applications Mqtt', () async {
    final connection =
        DatabaseConnection(NativeDatabase.memory(logStatements: true));
    final db = Database(connection);
    await db.host(
        DriftMqttInterface(host: 'test.mosquitto.org', name: 'unit_device'));
    final remoteConnection = await DriftMqttInterface.remote(
        host: 'test.mosquitto.org', name: 'unit_device');
    final remote = Database(remoteConnection.value!);
    final user = await remote.getUserById(1);
    expect(
        user,
        User(
          id: 1,
          name: 'Dash',
          birthDate: DateTime.parse('2011-10-11 00:00:00.000'),
          profilePicture: null,
          preferences: null,
        ));
  });
}
