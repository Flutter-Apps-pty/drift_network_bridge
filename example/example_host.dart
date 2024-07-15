import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_network_bridge/drift_network_bridge.dart';

import '../test/integration_tests/drift_testcases/database/database.dart';
import '../test/original/test_utils/database_vm.dart';

Future<void> main() async {
  preferLocalSqlite3();

  // final db =
  //     Database(DatabaseConnection(NativeDatabase.memory(logStatements: true)));
  // db.host(DriftTcpInterface());
  final db =
      Database(DatabaseConnection(NativeDatabase.memory(logStatements: true)));
  db.hostAll(
      [DriftMqttInterface(host: 'test.mosquitto.org'), DriftTcpInterface()]);
  // startServer();
}

void startServer() async {
  var server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
  print('Server started on ${server.address.address}:${server.port}');

  await for (var socket in server) {
    handleClient(socket);
  }
}

void handleClient(Socket socket) {
  print(
      'Client connected: ${socket.remoteAddress.address}:${socket.remotePort}');

  socket.listen(
    (Uint8List data) {
      final message = String.fromCharCodes(data);
      print('Received message: $message');

      final response = 'Server received: $message';
      socket.write(response);
    },
    onError: (error) {
      print('Error: $error');
      socket.close();
    },
    onDone: () {
      print('Client disconnected');
      socket.close();
    },
  );
}
