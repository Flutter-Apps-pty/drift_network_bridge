import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import '../../../drift_bridge_server.dart';

abstract class DriftBridgeInterface {
  Stream<DriftBridgeClient> get incomingConnections;
  void close();
  void shutdown();
  FutureOr<DriftBridgeClient> connect();
  FutureOr<void> setupServer();

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
  void listen(Function(Object message) onData, {required Function() onDone});

  void close();

  void send(Object? message);
}
