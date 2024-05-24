
import 'dart:async';
import 'dart:io';

import 'package:drift_network_bridge/src/network_remote/network_client_impl.dart';



abstract class DriftBridgeInterface{
  Stream <DriftBridgeClient> get incomingConnections;

  void close();

  void shutdown();

  FutureOr<DriftBridgeClient> connect();
}

abstract class DriftBridgeClient {
  void listen(Function(Object message) onData, {required Function() onDone});

  void close();

  void send(Object? message);
}