import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';
import 'package:drift_network_bridge/src/drift_bridge_server.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/src/typed_buffer.dart';
import 'package:uuid/data.dart';
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
  final String _topic = 'drift_test_server';
  Completer _promiseToClose = Completer();
  SubscriptionTopic get sIncomingTopic => SubscriptionTopic('$_topic/stream/#');
  PublicationTopic get pIncomingTopic => PublicationTopic('$_topic/stream');
  final StreamController<DriftBridgeClient> _incomingConnections = StreamController.broadcast();
  DriftMqttInterface({bool server = true}) {
    if(server) {
      serverClient = MqttServerClient.withPort(
          '127.0.0.1', 'drift_test_server', 1883);
      serverClient.connectionMessage ??= MqttConnectMessage();
      serverClient.connectionMessage =
          serverClient.connectionMessage!.startClean();
      serverClient.logging(on: false);
      serverClient.keepAlivePeriod = 30;
      serverClient.setProtocolV311();
      Future.sync(_initializeServer);
    }
  }

  Future<void> _initializeServer() async {
    await serverClient.connect();
    serverClient.subscribe(sIncomingTopic.rawTopic, MqttQos.exactlyOnce);
    _promiseToClose.future.then((_) {
      serverClient.disconnect();
    });
    serverClient.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) async {
      ///create new clients for each incoming connection
      for (var message in messages) {
        if(sIncomingTopic.safeMatch(PublicationTopic(message.topic))){
          final payload = MqttPublishPayload.bytesToStringAsString(
              ((message.payload) as MqttPublishMessage).payload.message);
          final newClient = DriftMqttClient(MqttServerClient.withPort(
              '127.0.0.1', 'server-$payload', 1883),isClient: false);
          newClient.session = payload;
          await newClient.connect();
          _incomingConnections.add(newClient);
          serverClient.publishString('${pIncomingTopic.rawTopic}/$payload', 'ok');
        }
        else{
          print('Discarding message from ${message.topic}');
        }

      }
    });
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
        '127.0.0.1', 'client-$session', 1883));
    client.session = session;
    await client.connect();
    client.subscribe('${pIncomingTopic.rawTopic}/$session', MqttQos.exactlyOnce);
    client.publishString('${pIncomingTopic.rawTopic}/$session', session);
    return client;
  }

  ///note we have to make client unique as well as their publishing and receiving topics
  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      _incomingConnections.stream;

  static Future<DatabaseConnection> remote() async {
    DriftBridgeServer server = DriftBridgeServer(DriftMqttInterface(server: false));
    return  server.connect();
  }

}

class DriftMqttClient extends DriftBridgeClient {
  final MqttServerClient client;
  final String _topic = 'drift_test_server';
  final bool isClient;
  PublicationTopic get pIncomingTopic => PublicationTopic('$_topic/stream/$session');
  SubscriptionTopic get sDataTopic => isClient?SubscriptionTopic('$_topic/stream/$session/client'):SubscriptionTopic('$_topic/stream/$session/host');
  PublicationTopic get pDataTopic => isClient?PublicationTopic('$_topic/stream/$session/host'):PublicationTopic('$_topic/stream/$session/client');
  // SubscriptionTopic get sTopic => SubscriptionTopic(_counterpartTopic);
  // SubscriptionTopic get sCloseTopic => SubscriptionTopic('$_counterpartTopic/close');
  // SubscriptionTopic get sErrorTopic => SubscriptionTopic('$_counterpartTopic/error');
  //
  //
  // PublicationTopic get pTopic => PublicationTopic('$_topic/stream/${client.clientIdentifier}');
  // PublicationTopic get pCloseTopic => PublicationTopic('$_topic/close');
  // PublicationTopic get pErrorTopic => PublicationTopic('$_topic/error');
  String session = '';
  bool sessionReady = false;
  DriftMqttClient(this.client,{this.isClient = true}){
    client.connectionMessage ??= MqttConnectMessage();
    client.connectionMessage = client.connectionMessage!.startClean();
    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.setProtocolV311();
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