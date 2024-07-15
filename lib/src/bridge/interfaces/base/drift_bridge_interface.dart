import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import '../../../drift_bridge_server.dart';

/// Abstract class defining the interface for a Drift bridge.
abstract class DriftBridgeInterface {
  /// Stream of incoming client connections.
  Stream<DriftBridgeClient> get incomingConnections;

  /// Closes the bridge interface.
  Stream<bool> get connectionStream;
  void close();

  /// Shuts down the bridge interface.
  void shutdown();

  /// Establishes a connection and returns a DriftBridgeClient.
  FutureOr<DriftBridgeClient> connect();

  /// Sets up the server for the bridge.
  FutureOr<void> setupServer();

  /// Registers a callback to be called when a connection is established.
  void onConnected(Function() onConnected);

  /// Registers a callback to be called when a connection is lost.
  void onDisconnected(Function() onDisconnected);

  /// Registers a callback to be called when a connection is re-established.
  void onReconnected(Function() onReconnected);

  /// Creates a remote database connection using the provided interface.
  ///
  /// Returns an [ErrorOr] containing either a [DatabaseConnection] or an error.
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

/// Abstract class defining the interface for a Drift bridge client.
abstract class DriftBridgeClient {
  Stream<bool> get connectionStream;
  /// Listens for incoming messages and registers callbacks for data and completion.
  ///
  /// [onData] is called when a message is received.
  /// [onDone] is called when the connection is closed.
  void listen(Function(Object message) onData, {required Function() onDone});

  /// Closes the client connection.
  void close();

  /// Sends a message through the client connection.
  void send(Object? message);
}
