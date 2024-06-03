import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_data.dart';
import 'package:uuid/v8.dart';

extension on MqttServerClient {
  int publishString(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    // Publish the event to the MQTT broker
    print('publishing $topic with\nmessage $message');
    return publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
  }
}

extension on SubscriptionTopic {
  bool safeMatch(PublicationTopic matcheeTopic) {
    if(matcheeTopic.topicFragments.length != topicFragments.length) {
      return false;
    }
    return matches(matcheeTopic);
  }
}

class DriftMqttInterface extends DriftBridgeInterface {
  late MqttServerClient serverClient;
  final Completer _promiseToClose = Completer();
  final String host;
  final int port;
  final String name;

  DriftMqttInterface({required this.host, this.port = 1883, this.name = 'drift_bridge'});
  SubscriptionTopic get sIncomingTopic => SubscriptionTopic('$name/stream/#');
  PublicationTopic get pIncomingTopic => PublicationTopic('$name/stream');
  final StreamController<DriftBridgeClient> _incomingConnections = StreamController.broadcast();

  Future<ErrorOr<void>> _initializeServer() async {
    try{
      await serverClient.connect();
      serverClient.subscribe(sIncomingTopic.rawTopic, MqttQos.exactlyOnce);
      _promiseToClose.future.then((_) {
        Future.delayed(const Duration(seconds: 1), () {
          serverClient.disconnect();
        });
      });
      serverClient.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) async {
        ///create new clients for each incoming connection
        for (var message in messages) {
          final payload = MqttPublishPayload.bytesToStringAsString(
              ((message.payload) as MqttPublishMessage).payload.message);
          if(sIncomingTopic.safeMatch(PublicationTopic(message.topic))){
            if(payload.contains('ok')) return;
            final newClient = DriftMqttClient(MqttServerClient.withPort(
                host, 'server-$payload', port),name,isClient: false);
            newClient.session = payload;
            await newClient.connect();
            _incomingConnections.add(newClient);
            serverClient.publishString('${pIncomingTopic.rawTopic}/$payload', 'ok');
          }
          else{
            print('Discarding message from ${message.topic} : $payload');
          }
        }
      });
    } catch (e) {
      print('Error connecting to the server $e');
      return ErrorOr.error(e);
    }
    return ErrorOr.value(null);
  }

  @override
  void close() {
    if(_promiseToClose.isCompleted){
      return;
    }
    _promiseToClose.complete();
    // serverClient.disconnect();
  }

  @override
  void shutdown() {
    close();
  }

  @override//called for connectTo server
  Future<DriftBridgeClient> connect() async {
    final session = UuidV8().generate();
    DriftMqttClient client = DriftMqttClient(MqttServerClient.withPort(
        host, 'client-$session', port),name);
    client.session = session;
    await client.connect();
    client.subscribe('$name/$session', MqttQos.exactlyOnce);
    /// notify server of new client session
    client.publishString('${pIncomingTopic.rawTopic}/$session', session);
    return client;
  }

  ///note we have to make client unique as well as their publishing and receiving topics
  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      _incomingConnections.stream;

  static Future<ErrorOr<DatabaseConnection>> remote({
    required String host,
    int port = 1883,
    String name = 'drift_bridge',
    void Function(Object error)? onConnectionError,
  }) =>
      DriftBridgeInterface.remote(DriftMqttInterface(host: host, port: port,name: name));

  @override
  FutureOr<void> setupServer() {
    serverClient = MqttServerClient.withPort(
        host, name, port);
    serverClient.connectionMessage ??= MqttConnectMessage();
    serverClient.connectionMessage =
        serverClient.connectionMessage!.startClean();
    serverClient.logging(on: false);
    serverClient.keepAlivePeriod = 30;
    serverClient.setProtocolV311();
    // serverClient.autoReconnect = true;
    // serverClient.resubscribeOnAutoReconnect = true;
   return Future.sync(_initializeServer);
  }
}

class DriftMqttClient extends DriftBridgeClient {
  final MqttServerClient client;
  final String _name;
  final bool isClient;
  PublicationTopic get pIncomingTopic => PublicationTopic('$_name/stream/$session');
  SubscriptionTopic get sDataTopic => isClient?SubscriptionTopic('$_name/$session/client'):SubscriptionTopic('$_name/$session/host');
  PublicationTopic get pDataTopic => isClient?PublicationTopic('$_name/$session/host'):PublicationTopic('$_name/$session/client');

  String session = '';
  bool sessionReady = false;
  DriftMqttClient(this.client,this._name,{this.isClient = true}){
    client.connectionMessage ??= MqttConnectMessage();
    client.connectionMessage = client.connectionMessage!.startClean();
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.setProtocolV311();
    // client.autoReconnect = true;
    // client.resubscribeOnAutoReconnect = true;
    client.onConnected = () {
      client.subscribe(sDataTopic.rawTopic, MqttQos.exactlyOnce);
    };
  }

  @override
  void close() {
    client.disconnect();
  }

  @override
  void send(Object? message) {
    if (message is List) {
      client.publishString(pDataTopic.rawTopic,
          jsonEncode(message));
    } else if (message is String){
      //_disconnect as String
      client.publishString(pDataTopic.rawTopic,
          message);
    }
  }

  @override
  void listen(Function(Object message) onData, {required Function() onDone}) {
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (var message in messages) {
        final payload = MqttPublishPayload.bytesToStringAsString(
            ((message.payload) as MqttPublishMessage).payload.message);
        if(SubscriptionTopic(message.topic).safeMatch(pIncomingTopic)){
          if(payload == 'ok') {
            sessionReady = true;
          }
        }
        else if(SubscriptionTopic(message.topic).safeMatch(PublicationTopic(sDataTopic.rawTopic))){

          final data = jsonDecode(payload);
          onData(data);
        }
        else {
          print('Discarding message from ${message.topic} : $payload');
          print('should not be here');
        }
      }
    }, onDone: onDone);
  }

  Future<MqttClientConnectionStatus?> connect() => client.connect();

  Subscription? subscribe(String topic, MqttQos qosLevel) => client.subscribe(topic, qosLevel);

  int publishMessage(
      String topic, MqttQos qualityOfService, Uint8Buffer data,
      {bool retain = false}) => client.publishMessage(topic, qualityOfService, data,retain: retain);

  void publishString(String rawTopic, String session) => client.publishString(rawTopic, session);
}