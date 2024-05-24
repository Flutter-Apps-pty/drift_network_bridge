import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';



import 'interfaces/base/drift_bridge_interface.dart';
import 'package:drift/src/remote/protocol.dart';
// All of this is drift-internal and not exported, so:
// ignore_for_file: public_member_api_docs

@internal
const disconnectMessage = '_disconnect';

@internal
Future<StreamChannel> connectToServer(DriftBridgeInterface networkInterface, bool serialize) async {
  final controller =
  StreamChannelController<Object?>(allowForeignErrors: false, sync: true);

  final connection = await networkInterface.connect();
  connection.listen((message) {
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

  controller.local.stream.listen((message) {
    connection.send(message);
  }, onDone: () {
    // Closed locally - notify the remote end about this.
    connection.send(disconnectMessage);
    connection.close();
  });

  return controller.foreign;
}

@internal
class NetworkDriftServer {
  final bool killServerWhenDone;
  final bool onlyAcceptSingleConnection;

  final DriftServer server;
  final DriftBridgeInterface networkInterface;
  int _counter = 0;

  NetworkDriftServer(
      this.networkInterface,
      QueryExecutor connection, {
        this.killServerWhenDone = true,
        bool closeConnectionAfterShutdown = true,
        this.onlyAcceptSingleConnection = false,
      }) : server = DriftServer(
    connection,
    allowRemoteShutdown: true,
    closeConnectionAfterShutdown: closeConnectionAfterShutdown,
  ) {
    final subscription = networkInterface.incomingConnections.listen((driftBridgeConnection) {
      if (onlyAcceptSingleConnection) {
        networkInterface.close();
      }

      final controller = StreamChannelController<Object?>(
          allowForeignErrors: false, sync: true);

      driftBridgeConnection.listen((message) {
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
        driftBridgeConnection.send(message);
      }, onDone: () {
        // Closed locally - notify the client about this.
        driftBridgeConnection.send(disconnectMessage);
        connection.close();
      });

      server.serve(controller.foreign, serialize: true); //todo change serialize to false and test again
    });

    server.done.then((_) {
      subscription.cancel();
      networkInterface.close();
      if (killServerWhenDone) networkInterface.shutdown();
    });
  }
}