import 'dart:async';

import 'package:async/async.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';

/// A class that implements [DriftBridgeInterface] to manage multiple interfaces.
///
/// This class allows handling multiple [DriftBridgeInterface] instances simultaneously.
class DriftMultipleInterface extends DriftBridgeInterface {
  /// The list of [DriftBridgeInterface] instances managed by this class.
  final List<DriftBridgeInterface> interfaces;

  /// Creates a new [DriftMultipleInterface] with the given list of interfaces.
  DriftMultipleInterface(this.interfaces);

  @override
  void close() {
    for (var interface in interfaces) {
      interface.close();
    }
  }

  @override
  void shutdown() {
    for (var interface in interfaces) {
      interface.shutdown();
    }
  }

  @override
  Future<DriftBridgeClient> connect() async {
    return _DriftMultipleClient(
        await Future.wait(interfaces.map((e) async => await e.connect())));
  }

  /// Combines the incoming connections from all managed interfaces.
  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      StreamGroup.merge(interfaces.map((e) => e.incomingConnections));

  @override
  FutureOr<void> setupServer() async {
    for (var interface in interfaces) {
      await interface.setupServer();
    }
    return Future.value();
  }

  @override
  void onConnected(Function() onConnected) {
    for (var interface in interfaces) {
      interface.onConnected(onConnected);
    }
  }

  @override
  void onDisconnected(Function() onDisconnected) {
    for (var interface in interfaces) {
      interface.onDisconnected(onDisconnected);
    }
  }

  @override
  void onReconnected(Function() onReconnected) {
    for (var interface in interfaces) {
      interface.onReconnected(onReconnected);
    }
  }

  @override
  // TODO: implement connectionStream
  Stream<bool> get connectionStream => throw UnimplementedError();
}

/// A private class that implements [DriftBridgeClient] to manage multiple clients.
///
/// This class is used internally by [DriftMultipleInterface] to handle multiple client connections.
class _DriftMultipleClient extends DriftBridgeClient {
  /// The list of [DriftBridgeClient] instances managed by this class.
  final List<DriftBridgeClient> clients;

  /// Creates a new [_DriftMultipleClient] with the given list of clients.
  _DriftMultipleClient(this.clients);

  @override
  void listen(Function(Object message) onData, {required Function() onDone}) {
    for (var client in clients) {
      client.listen(onData, onDone: onDone);
    }
  }

  @override
  void close() {
    for (var client in clients) {
      client.close();
    }
  }

  @override
  void send(Object? message) {
    for (var client in clients) {
      client.send(message);
    }
  }

  @override
  // TODO: implement connectionStream
  Stream<bool> get connectionStream => throw UnimplementedError();
}
