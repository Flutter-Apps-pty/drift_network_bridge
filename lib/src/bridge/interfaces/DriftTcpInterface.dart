import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';

class DriftTcpInterface extends DriftBridgeInterface {
  late ServerSocket server;

  DriftTcpInterface({bool server = true}) {
    if (server) {
      Future.sync(_initializeServer);
    }
  }

  Future<void> _initializeServer() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 4040);
  }

  @override
  void close() {
    server.close();
  }

  @override
  void shutdown() {
    close();
  }

  @override
  Future<DriftBridgeClient> connect() async {
    return DriftTcpClient(
        await Socket.connect(InternetAddress.loopbackIPv4, 4040));
  }

  static Future<DatabaseConnection> remote() async {
    DriftBridgeServer server =
        DriftBridgeServer(DriftTcpInterface(server: false));
    return server.connect();
  }

  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      server.asBroadcastStream().transform(StreamTransformer.fromBind(
          (stream) => stream.map((socket) => DriftTcpClient(socket))));
}

class DriftTcpClient extends DriftBridgeClient {
  final Socket socket;

  DriftTcpClient(this.socket);

  @override
  void close() {
    socket.close();
  }

  @override
  void send(Object? message) {
    if (message is List) {
      socket.add(jsonEncode(message).codeUnits);
    } else if (message is String) {
      //_disconnect as String
      socket.add(message.codeUnits);
    }
  }

  @override
  void listen(Function(Object message) onData, {required Function() onDone}) {
    socket.listen((data) {
      /// sometimes data is too quick then multiple pack
      String serialized = utf8.decode(data);
      while (serialized.contains('][')) {
        final index = serialized.indexOf('][');
        onData(jsonDecode(serialized.substring(0, index + 1)));
        serialized = serialized.substring(index + 1);
      }
      if (serialized.contains('[')) {
        onData(jsonDecode(serialized));
      } else {
        onData(serialized);
      }
    }, onDone: onDone);
  }
}
