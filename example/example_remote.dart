import 'dart:io';

import 'package:drift_network_bridge/src/bridge/interfaces/drift_mqtt_interface.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/drift_tcp_interface.dart';

import '../test/integration_tests/drift_testcases/tests.dart';
import '../test/original/test_utils/database_vm.dart';

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();

  final tcpDb = Database(DriftTcpInterface.remote(ipAddress: InternetAddress.loopbackIPv4, port: 4040));
  final mqttDb = Database(DriftMqttInterface.remote(host: 'test.mosquitto.org', name: 'unit_device'));

  try {
    final test = await tcpDb.users.all().get();
    print(test);
  }
  catch(e,stacktrace){
    print(e);
    print(stacktrace);
  }
  try {
    final test = await mqttDb.users.all().get();
    print(test);
  }
  catch(e,stacktrace){
    print(e);
    print(stacktrace);
  }
}
