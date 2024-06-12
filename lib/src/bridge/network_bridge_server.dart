import 'package:drift/drift.dart';
import 'package:drift_network_bridge/drift_network_bridge.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';

@internal
const disconnectMessage = '_disconnect';

@internal
Future<StreamChannel> remoteConnectToServer(
    DriftBridgeInterface networkInterface, bool serialize) async {
  final controller = StreamChannelController<Object?>(
      allowForeignErrors: false, sync: true); // channel controller

  final clientConnection = await networkInterface.connect();

  /// This is dual client listening here if it receives from the server tcp it will send to tcp
  /// and if it receives from the server mqtt it will send to mqtt database
  clientConnection.listen((message) {
    if (message == disconnectMessage) {
      // Server has closed the connection
      controller.local.sink.close();
    } else {
      controller.local.sink.add(message);
    }
  }, onDone: () {
    // Connection closed by the server
    controller.local.sink.close();
  });

  /// Receiving form server aka database and forwarding to the client
  /// We have to distinguish between the two connections
  controller.local.stream.listen((message) {
    clientConnection.send(message); //todo replace this with generic send
    // we have to extract the identity somehow here and push it off in the send
  }, onDone: () {
    // Closed locally - notify the remote end about this.
    clientConnection.send(disconnectMessage);
    clientConnection.close();
  });

  return controller.foreign;
}

@internal
class NetworkDriftServer {
  final bool killServerWhenDone;
  final bool onlyAcceptSingleConnection;

  final DriftNetworkServer server;
  final DriftBridgeInterface networkInterface;
  @visibleForTesting
  bool dontReply = false;
  NetworkDriftServer(
    this.networkInterface,
    QueryExecutor connection, {
    this.killServerWhenDone = true,
    bool closeConnectionAfterShutdown = true,
    this.onlyAcceptSingleConnection = false,
  }) : server = DriftNetworkServer(
          connection,
          allowRemoteShutdown: true,
          closeConnectionAfterShutdown: closeConnectionAfterShutdown,
        ) {
    /// host listening for incoming connections first connect is TCP, second is MQTT so its serves both
    (networkInterface.setupServer() as Future<void>).then((_) {
      final subscription =
          networkInterface.incomingConnections.listen((incomingConnection) {
        if (onlyAcceptSingleConnection) {
          networkInterface.close();
        }

        final controller = StreamChannelController<Object?>(
            allowForeignErrors: false, sync: true);
        incomingConnection.listen((message) {
          if (dontReply) return;
          if (message == disconnectMessage) {
            // Client closed the connection
            controller.local.sink.close();

            if (onlyAcceptSingleConnection) {
              // The only connection was closed, so shut down the server.
              server.shutdown();
            }
          } else {
            controller.local.sink.add(message);
          }
        }, onDone: () {
          // Connection closed by the client
          controller.local.sink.close();
        });

        controller.local.stream.listen((message) {
          incomingConnection.send(message); //replying to incoming connection
        }, onDone: () {
          // Closed locally - notify the client about this.
          incomingConnection.send(disconnectMessage);
          connection.close();
        });

        server.serve(controller.foreign, serialize: true);
      });
      server.done.then((_) {
        subscription.cancel();
        networkInterface.close();
        if (killServerWhenDone) networkInterface.shutdown();
      });
    });
  }

  @visibleForTesting
  void simulateNetworkFailure() {
    dontReply = true;
  }

  @visibleForTesting
  void simulateNetworkRecovery() {
    dontReply = false;
  }
}
