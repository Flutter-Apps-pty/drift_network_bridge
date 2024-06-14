import 'dart:io';

import 'package:drift_network_bridge/drift_network_bridge.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_mqtt_interface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_tcp_interface.dart';
import 'package:drift_network_bridge/src/network_remote/runtime/remote_database.dart';

import '../test/integration_tests/drift_testcases/tests.dart';
import '../test/original/test_utils/database_vm.dart';

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();
  // final dbController = RemoteDatabase((conn) {
  //   return Database(conn);
  // }, DriftTcpInterface(ipAddress: InternetAddress.loopbackIPv4, port: 4040));
  // final _db = await dbController.asyncDb;

  final dbController = RemoteDatabase((conn) {
    return Database(conn);
  }, DriftMqttInterface(host: '127.0.0.1'));
  final _db = await dbController.asyncDb;

  // final tcpConnection = await DriftTcpInterface.remote(
  //     ipAddress: InternetAddress.loopbackIPv4, port: 4040);
  // // final mqttConnection = await DriftMqttInterface.remote(
  // //     host: 'test.mosquitto.org', name: 'unit_device');
  // final tcpDb = Database(tcpConnection.value!);
  // final mqttDb = Database(mqttConnection.value!);
  //
  try {
    final test = await _db()?.users.all().get();
    print(test);
  } catch (e, stacktrace) {
    print(e);
    print(stacktrace);
  }

  while (true) {
    await Future.delayed(Duration(seconds: 2));
    try {
      if (!dbController.isConnected()) {
        print('reconnecting from controller');
        // dbController.updateInterface(DriftTcpInterface(
        //     ipAddress: InternetAddress.loopbackIPv4, port: 4040));
      }
      final test = await _db()?.users.all().get();
      print(test);
      // if (test != null) {
      //   dbController.updateInterface(DriftTcpInterface(
      //       ipAddress: InternetAddress.loopbackIPv4, port: 4041));
      // }
    } catch (e, stacktrace) {
      // dbController.updateInterface(DriftTcpInterface(
      //     ipAddress: InternetAddress.loopbackIPv4, port: 4040));
      print(e);
      print(stacktrace);
    }
  }

  // try {
  //   final test = await mqttDb.users.all().get();
  //   print(test);
  // } catch (e, stacktrace) {
  //   print(e);
  //   print(stacktrace);
  // }
}
