
import 'package:drift_network_bridge/drift_network_bridge.dart';

import '../test/integration_tests/drift_testcases/tests.dart';
import '../test/original/test_utils/database_vm.dart';

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  preferLocalSqlite3();
  final tcpController = RemoteDatabase((conn) {
    return Database(conn);
  }, DriftTcpInterface(ipAddress: InternetAddress.loopbackIPv4, port: 4040));
  final tcpDb = await tcpController.asyncDb;

  final mqttController = RemoteDatabase((conn) {
    return Database(conn);
  }, DriftMqttInterface(host: 'test.mosquitto.org'));
  final mqttDb = await mqttController.asyncDb;
  }, DriftMqttInterface(host: '127.0.0.1'));
  final db = await dbController.asyncDb;

  try {
    final tcpUsers = await tcpDb()?.users.all().get();
    print(tcpUsers);
    final mqttUsers = await mqttDb()?.users.all().get();
    print(mqttUsers);
    final test = await db()?.users.all().get();
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
      final test = await db()?.users.all().get();
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
