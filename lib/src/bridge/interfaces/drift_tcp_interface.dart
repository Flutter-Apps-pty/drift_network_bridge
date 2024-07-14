import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import 'package:drift_network_bridge/src/bridge/interfaces/base/drift_bridge_interface.dart';
import 'package:logger/logger.dart';

class DriftTcpInterface extends DriftBridgeInterface {
  final _connectionController = StreamController<bool>.broadcast();
  late ServerSocket server;

  final InternetAddress? ipAddress;

  final int port;

  DriftTcpInterface({this.ipAddress, this.port = 4040});
  Function()? _onConnected;
  @override
  void close() => server.close();

  @override
  void shutdown() => close();

  @override
  Future<DriftBridgeClient> connect() async {
    return DriftTcpClient(
        await Socket.connect(ipAddress ?? InternetAddress.loopbackIPv4, port));
  }

  static Future<ErrorOr<DatabaseConnection>> remote(
          {required InternetAddress ipAddress, int port = 4040}) =>
      DriftBridgeInterface.remote(
          DriftTcpInterface(ipAddress: ipAddress, port: port));

  @override
  Stream<DriftBridgeClient> get incomingConnections =>
      server.asBroadcastStream().transform(StreamTransformer.fromBind(
          (stream) => stream.map((socket) => DriftTcpClient(socket))));

  @override
  Future<void> setupServer() async {
    server =
        await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
    _onConnected?.call();
  }

  @override
  void onConnected(Function() onConnected) {
    _connectionController.add(true);
    _onConnected = onConnected;
  }

  @override
  void onDisconnected(Function() onDisconnected) {
    // TODO: implement onDisconnected
  }

  @override
  void onReconnected(Function() onReconnected) {
    // TODO: implement onReconnected
  }

  @override
  Stream<bool> get connectionStream => _connectionController.stream;
}

class DriftTcpClient extends DriftBridgeClient {
  final StreamController<bool> _connectionStreamController =
      StreamController<bool>.broadcast();
  Socket socket;
  bool closed = false;
  List<int> _buffer = [];
  final StreamController<Object> _messageController =
      StreamController<Object>();

  DriftTcpClient(this.socket) {
    socket.done.then((value) {
      closed = true;
      _connectionStreamController.add(false);
    });
    _connectionStreamController.add(true);
  }

  @override
  void close() {
    closed = true;
    socket.close();
    _messageController.close();
  }

  @override
  void send(Object? message) {
    if (closed) {
      Logger().d('TCP: Connection closed, cannot send message');
      return;
    }
    Logger().d('TCP: Sending $message');
    runZonedGuarded<void>(() async {
      if (message is List) {
        socket.add(jsonEncode(message).codeUnits);
      } else if (message is String) {
        socket.add(message.codeUnits);
      }
    }, (error, stack) {
      Logger().e('Error sending message: $error');
    });
  }

  @override
  void listen(Function(Object message) onData, {required Function() onDone}) {
    socket.listen((data) {
      _buffer.addAll(data);
      _processBuffer();
    }, onError: (err) {
      Logger().e('Error: $err');
      _connectionStreamController.add(false);
    }, onDone: () {
      Logger().i('Client disconnected');
      _connectionStreamController.add(false);
      close();
      onDone();
    });

    _messageController.stream.listen(onData);
  }

  void _processBuffer() {
    while (true) {
      int bracketStart = _buffer.indexOf('['.codeUnitAt(0));
      if (bracketStart == -1) break;

      int bracketEnd = -1;
      int openBrackets = 0;
      for (int i = bracketStart; i < _buffer.length; i++) {
        if (_buffer[i] == '['.codeUnitAt(0)) openBrackets++;
        if (_buffer[i] == ']'.codeUnitAt(0)) openBrackets--;
        if (openBrackets == 0) {
          bracketEnd = i;
          break;
        }
      }

      if (bracketEnd == -1) break; // No complete message found

      String message = utf8.decode(
          _buffer.sublist(bracketStart, bracketEnd + 1),
          allowMalformed: true);

      // Remove unprintable characters
      message = message.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
      try {
        _messageController.add(jsonDecode(message));
      } catch (e) {
        Logger().e('Error decoding message: $e');
        _messageController.add(message); // Fall back to sending the raw string
      }

      _buffer = _buffer.sublist(bracketEnd + 1);
    }

    // Process any remaining non-JSON data
    if (_buffer.isNotEmpty) {
      String remaining = utf8.decode(_buffer, allowMalformed: true);
      if (!remaining.startsWith('[')) {
        _messageController.add(remaining);
        _buffer.clear();
      }
    }
  }

  @override
  // TODO: implement connectionStream
  Stream<bool> get connectionStream => _connectionStreamController.stream;
}
