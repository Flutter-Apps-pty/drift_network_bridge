import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import '../../../drift_bridge_server.dart';

abstract class DriftBridgeInterface {
  Stream<DriftBridgeClient> get incomingConnections;
  Stream<bool> get connectionStream;
  void close();
  void shutdown();
  FutureOr<DriftBridgeClient> connect();
  FutureOr<void> setupServer();
  void onConnected(Function() onConnected);
  void onDisconnected(Function() onDisconnected);
  void onReconnected(Function() onReconnected);
  static Future<ErrorOr<DatabaseConnection>> remote(
      DriftBridgeInterface interface) async {
    DriftBridgeServer server = DriftBridgeServer(interface);
    final connRslt = await server.connect();
    if (connRslt.isValue) {
      return ErrorOr.value(connRslt.value!);
    }
    return ErrorOr.error(connRslt.error!);
  }
}

abstract class DriftBridgeClient {
  Stream<bool> get connectionStream;
  void listen(Function(Object message) onData, {required Function() onDone});

  void close();

  void send(Object? message);
}
