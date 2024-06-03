@Timeout(Duration(seconds: 120))
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_mqtt_interface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_tcp_interface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';
import 'package:drift_network_bridge/src/network_remote/network_communication.dart';

import 'package:test/test.dart';
import 'integration_tests/drift_testcases/database/database.dart';
import 'original/test_utils/database_vm.dart';

void main() {
  setUpAll((){
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test('recover from half connection', () async {
    DriftNetworkCommunication.timeout = const Duration(seconds: 5);
    final server = await Database(DatabaseConnection(testInMemoryDatabase())).hostAll([DriftTcpInterface(),
      DriftMqttInterface(host: '127.0.0.1', name: 'unit_device')],onlyAcceptSingleConnection: false);
    final tcpConnection = (await DriftTcpInterface.remote(ipAddress: InternetAddress.loopbackIPv4, port: 4040)).value!;
    final mqttConnection = (await DriftMqttInterface.remote(host: '127.0.0.1', name: 'unit_device')).value!;
    Database remoteTcpDb = Database(tcpConnection);
    Database remoteMqttDb = Database(mqttConnection);

    /// Force ensure open
    await remoteTcpDb.users.select().get();
    await remoteMqttDb.users.select().get();
    server.simulateNetworkFailure();
    await expectLater(
      remoteMqttDb.users.select().get(),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      remoteTcpDb.users.select().get(),
      throwsA(isA<TimeoutException>()),
    );
    server.simulateNetworkRecovery();
    expect(await remoteTcpDb.users.select().get(), isNotEmpty);
    expect(await remoteMqttDb.users.select().get(), isNotEmpty);
  });

  test('Connection error test', () async {
    DriftNetworkCommunication.timeout = const Duration(seconds: 5);
    await Database(DatabaseConnection(testInMemoryDatabase())).hostAll([DriftTcpInterface(),
      DriftMqttInterface(host: '127.0.0.1', name: 'unit_device')],onlyAcceptSingleConnection: false);

    // Expect a SocketException when trying to connect to the remote TCP database with an incorrect port
    expect(
          () async => (await DriftTcpInterface.remote(
        ipAddress: InternetAddress.loopbackIPv4,
        port: 4041,
      )).valueOrThrow,
      throwsA(isA<SocketException>()),
    );
    // Expect a SocketException when trying to connect to the remote MQTT database with an incorrect name
    expect(
          () async => (await DriftMqttInterface.remote(
        host: '127.0.0.1',
        name: 'not_unit_device',
      )).valueOrThrow,
      throwsA(isA<TimeoutException>()),
    );
  });
}
