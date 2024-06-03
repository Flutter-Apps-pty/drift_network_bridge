import 'dart:async';

import 'package:async/async.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';

class DriftMultipleInterface extends DriftBridgeInterface {
  final List<DriftBridgeInterface> interfaces;


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
    return _DriftMultipleClient(await Future.wait(interfaces.map((e) async => await e.connect())));
  }

  /// Combines the incoming connections from both primary and secondary interfaces
  ///
  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      StreamGroup.merge(interfaces.map((e) => e.incomingConnections));

  @override
  FutureOr<void> setupServer() {
    // This is handled by the primary and secondary interfaces
  }
}

class _DriftMultipleClient extends DriftBridgeClient {
  final List<DriftBridgeClient> clients;

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
}
