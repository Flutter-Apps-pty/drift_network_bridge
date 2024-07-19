import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';
import 'package:logger/logger.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_data.dart';
import 'package:uuid/v8.dart';

/// Extension on MqttServerClient to add a method for publishing strings.
extension on MqttServerClient {
  /// Publishes a string message to the specified topic.
  ///
  /// Returns the message identifier or -1 if there was an error.
  int publishString(String topic, String message, {bool retaining = false}) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    Logger().d('publishing $topic with\nmessage $message');
    return runZonedGuarded<int>(() {
          return publishMessage(topic, MqttQos.exactlyOnce, builder.payload!,
              retain: retaining);
        }, (error, stack) {
          Logger().e('Error publishing message $error');
        }) ??
        -1;
  }
}

/// Extension on SubscriptionTopic to add a safe matching method.
extension on SubscriptionTopic {
  /// Safely matches a publication topic against this subscription topic.
  ///
  /// Returns true if the topics match, false otherwise.
  bool safeMatch(PublicationTopic matcheeTopic) {
    if (matcheeTopic.topicFragments.length != topicFragments.length) {
      return false;
    }
    return matches(matcheeTopic);
  }
}

/// A Drift bridge interface implementation using MQTT for communication.
class DriftMqttInterface extends DriftBridgeInterface {
  /// The MQTT server client used for communication.
  late Stream<bool> _connectionController;
  late MqttServerClient serverClient;

  /// A completer that resolves when the interface is closed.
  final Completer _promiseToClose = Completer();

  /// The host address of the MQTT broker.
  final String host;

  /// The port number of the MQTT broker.
  final int port;

  /// The name of this MQTT bridge.
  final String name;

  /// Callback function to be called when a connection is established.
  Function()? _onConnected;

  /// Creates a new DriftMqttInterface instance.
  ///
  /// [host] is the address of the MQTT broker.
  /// [port] is the port number of the MQTT broker (default is 1883).
  /// [name] is the name of this MQTT bridge (default is 'drift_bridge').
  DriftMqttInterface(
      {required this.host, this.port = 1883, this.name = 'drift_bridge'});

  /// The subscription topic for incoming messages.
  SubscriptionTopic get sIncomingTopic => SubscriptionTopic('$name/stream/#');

  /// The publication topic for incoming messages.
  PublicationTopic get pIncomingTopic => PublicationTopic('$name/stream');

  /// A stream controller for incoming connections.
  final StreamController<DriftBridgeClient> _incomingConnections =
      StreamController.broadcast();

  /// Initializes the MQTT server.
  ///
  /// Returns an [ErrorOr] containing void if successful, or an error if not.
  Future<ErrorOr<void>> _initializeServer() async {
    try {
      await serverClient.connect();
      serverClient.subscribe(sIncomingTopic.rawTopic, MqttQos.exactlyOnce);
      _promiseToClose.future.then((_) {
        Future.delayed(const Duration(seconds: 1), () {
          serverClient.disconnect();
        });
      });
      serverClient.updates!
          .listen((List<MqttReceivedMessage<MqttMessage>> messages) async {
        for (var message in messages) {
          final payload = MqttPublishPayload.bytesToStringAsString(
              ((message.payload) as MqttPublishMessage).payload.message);
          if (sIncomingTopic.safeMatch(PublicationTopic(message.topic))) {
            if (payload.contains('ok')) return;
            final newClient = DriftMqttClient(
                MqttServerClient.withPort(host, 'server-$payload', port), name,
                isClient: false);
            _connectionController = newClient.connectionStream;
            newClient.session = payload;
            await newClient.connect();
            _incomingConnections.add(newClient);
            serverClient.publishString(
                '${pIncomingTopic.rawTopic}/$payload', 'ok');
          } else {
            Logger().i('Discarding message from ${message.topic} : $payload');
          }
        }
      });
    } catch (e) {
      Logger().e('Error connecting to the server $e');
      return ErrorOr.error(e);
    }
    return ErrorOr.value(null);
  }

  @override
  void close() {
    if (_promiseToClose.isCompleted) {
      return;
    }
    _promiseToClose.complete();
  }

  @override
  void shutdown() {
    close();
  }

  @override
  Future<DriftBridgeClient> connect() async {
    final session = UuidV8().generate();
    DriftMqttClient client = DriftMqttClient(
        MqttServerClient.withPort(host, 'client-$session', port), name);
    client.session = session;
    _connectionController = client.connectionStream;
    await client.connect();
    client.subscribe('$name/$session', MqttQos.exactlyOnce);
    client.publishString('${pIncomingTopic.rawTopic}/$session', session);
    return client;
  }

  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      _incomingConnections.stream;

  /// Creates a remote database connection using MQTT.
  ///
  /// Returns an [ErrorOr] containing a [DatabaseConnection] if successful, or an error if not.
  static Future<ErrorOr<DatabaseConnection>> remote({
    required String host,
    int port = 1883,
    String name = 'drift_bridge',
  }) =>
      DriftBridgeInterface.remote(
          DriftMqttInterface(host: host, port: port, name: name));

  @override
  FutureOr<void> setupServer() {
    serverClient = MqttServerClient.withPort(host, name, port);
    serverClient.connectionMessage ??= MqttConnectMessage()
        .withWillRetain()
        .withWillTopic('$name/connection')
        .withWillMessage('false')
        .withWillQos(MqttQos.exactlyOnce)
        .startClean();

    serverClient.logging(on: false);
    serverClient.keepAlivePeriod = 30;
    serverClient.setProtocolV311();
    serverClient.autoReconnect = true;
    serverClient.onConnected = () {
      serverClient.publishString('$name/connection', 'true', retaining: true);
      _onConnected?.call();
    };
    return _initializeServer().then((serverState) {
      if (serverState.isError) {
        Logger().e('Error initializing server $serverState');
        Logger().i('Retrying server initialization');
        Future.delayed(const Duration(seconds: 5), () {
          setupServer();
        });
      }
      return serverState.value;
    });
  }

  @override
  void onConnected(Function() onConnected) {
    _onConnected = onConnected;
  }

  @override
  void onDisconnected(Function() onDisconnected) {
    serverClient.onDisconnected = onDisconnected;
  }

  @override
  void onReconnected(Function() onReconnected) {
    serverClient.onAutoReconnect = onReconnected;
  }

  @override
  // TODO: implement connectionStream
  Stream<bool> get connectionStream => _connectionController;
}

/// A Drift bridge client implementation using MQTT for communication.
class DriftMqttClient extends DriftBridgeClient {
  /// The MQTT client used for communication.
  final StreamController<bool> _connectionStreamController =
      StreamController<bool>.broadcast();
  final MqttServerClient client;

  /// The name of this MQTT bridge.
  final String _name;

  /// Indicates whether this is a client-side instance.
  final bool isClient;

  /// Indicates whether the client is closed.
  bool closed = false;

  /// The publication topic for incoming messages.
  PublicationTopic get pIncomingTopic =>
      PublicationTopic('$_name/stream/$session');

  /// The subscription topic for data messages.
  SubscriptionTopic get sDataTopic => isClient
      ? SubscriptionTopic('$_name/$session/client')
      : SubscriptionTopic('$_name/$session/host');

  /// The subscription topic for server connection status.
  SubscriptionTopic get sServerConnection =>
      SubscriptionTopic('$_name/connection');

  /// The publication topic for data messages.
  PublicationTopic get pDataTopic => isClient
      ? PublicationTopic('$_name/$session/host')
      : PublicationTopic('$_name/$session/client');

  /// The session identifier.
  String session = '';

  /// Indicates whether the session is ready.
  bool sessionReady = false;

  /// Creates a new DriftMqttClient instance.
  ///
  /// [client] is the MQTT client to use.
  /// [_name] is the name of this MQTT bridge.
  /// [isClient] indicates whether this is a client-side instance (default is true).
  DriftMqttClient(this.client, this._name, {this.isClient = true}) {
    client.connectionMessage ??= MqttConnectMessage();
    client.connectionMessage = client.connectionMessage!.startClean();
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.setProtocolV311();
    client.autoReconnect = true;
    client.onConnected = () {
      client.subscribe(sDataTopic.rawTopic, MqttQos.exactlyOnce);
      if (isClient) {
        client.subscribe(sServerConnection.rawTopic, MqttQos.exactlyOnce);
      }
      _connectionStreamController.add(true);
    };
    client.onDisconnected = () {
      _connectionStreamController.add(false);
      closed = true;
    };
    client.onAutoReconnected = () {
      _connectionStreamController.add(true);
    };
  }

  @override
  void close() {
    closed = true;
    try {
      Future.microtask(() => client.disconnect());
    } catch (e) {
      Logger().e('Error disconnecting client $e');
    }
  }

  @override
  void send(Object? message) {
    if (closed) {
      Logger().d('Mqtt: Connection closed, cannot send message');
      return;
    }
    try {
      if (message is List) {
        client.publishString(pDataTopic.rawTopic, jsonEncode(message));
      } else if (message is String) {
        client.publishString(pDataTopic.rawTopic, message);
      }
    } catch (e) {
      Logger().e('Error sending message $e');
    }
  }

  @override
  void listen(void Function(Object message) onData,
      {required void Function() onDone}) {
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      if (closed) return;
      for (var message in messages) {
        String payload = MqttPublishPayload.bytesToStringAsString(
            ((message.payload) as MqttPublishMessage).payload.message);
        if (SubscriptionTopic(message.topic)
            .safeMatch(PublicationTopic(sServerConnection.rawTopic))) {
          if (payload == 'false') {
            close();
          }
        } else if (SubscriptionTopic(message.topic).safeMatch(pIncomingTopic)) {
          if (payload == 'ok') {
            sessionReady = true;
          }
        } else if (SubscriptionTopic(message.topic)
            .safeMatch(PublicationTopic(sDataTopic.rawTopic))) {
          payload = payload.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
          while (payload.contains('][')) {
            final index = payload.indexOf('][');
            onData(jsonDecode(payload.substring(0, index + 1)));
            payload = payload.substring(index + 1);
          }
          if (payload.contains('[')) {
            onData(jsonDecode(payload));
          } else {
            onData(payload);
          }
          Logger().d('Received data from ${message.topic} : $payload');
        } else {
          Logger().i('Discarding message from ${message.topic} : $payload');
        }
      }
    }, onDone: () {
      Logger().i('Client disconnected');
      close();
      onDone();
    });
  }

  /// Connects the MQTT client.
  ///
  /// Returns a Future that completes with the connection status.
  Future<MqttClientConnectionStatus?> connect() => client.connect();

  /// Subscribes to the specified topic.
  ///
  /// Returns a [Subscription] object if successful, null otherwise.
  Subscription? subscribe(String topic, MqttQos qosLevel) =>
      client.subscribe(topic, qosLevel);

  /// Publishes a message to the specified topic.
  ///
  /// Returns the message identifier.
  int publishMessage(String topic, MqttQos qualityOfService, Uint8Buffer data,
          {bool retain = false}) =>
      client.publishMessage(topic, qualityOfService, data, retain: retain);

  /// Publishes a string message to the specified topic.
  void publishString(String rawTopic, String session) =>
      client.publishString(rawTopic, session);

  @override
  // TODO: implement connectionStream
  Stream<bool> get connectionStream => _connectionStreamController.stream;
}
