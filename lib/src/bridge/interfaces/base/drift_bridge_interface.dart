
import 'dart:async';
import 'package:drift/drift.dart';
import '../../../drift_bridge_server.dart';



abstract class DriftBridgeInterface{
  final bool isServer;

  DriftBridgeInterface({this.isServer = true}){
    if(isServer){
      setupServer();
    }
  }

  Stream <DriftBridgeClient> get incomingConnections;
  void close();
  void shutdown();
  FutureOr<DriftBridgeClient> connect();
  FutureOr<void> setupServer();

  static DatabaseConnection remote(DriftBridgeInterface interface)  {
    DriftBridgeServer server = DriftBridgeServer(interface);

    return DatabaseConnection.delayed(Future.sync(() async {
      return await server.connect();
    }));
  }
}

abstract class DriftBridgeClient {
  void listen(Function(Object message) onData, {required Function() onDone});

  void close();

  void send(Object? message);

}