import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_network_bridge/drift_network_bridge.dart';

import '../network_client_impl.dart';

//todo allow to change or update the interface
/// A class that manages a remote database connection using Drift.
class RemoteDatabase<T extends GeneratedDatabase> {
  /// The current database instance.
  GeneratedDatabase? _db;

  /// A factory function that creates a new database instance.
  final T Function(DatabaseConnection conn) _factory;

  /// The Drift bridge interface used for remote communication.
  DriftBridgeInterface _interface;

  /// A flag indicating whether to automatically reconnect on disconnection.
  final bool autoReconnect;

  /// A completer that completes when the first database connection is established.
  Completer<T> _completer = Completer();

  /// A timer used for scheduling reconnection attempts.
  Timer? _reconnectTimer;

  /// Creates a new instance of [RemoteDatabase].
  ///
  /// [_factory] is a function that creates a new database instance.
  /// [interface] is the Drift bridge interface used for remote communication.
  /// [autoReconnect] is a flag indicating whether to automatically reconnect on disconnection.
  RemoteDatabase(this._factory, this._interface, {this.autoReconnect = true}) {
    _innerConnect();
  }

  /// Returns a function that provides the current database instance asynchronously.
  ///
  /// The returned function will wait for the first database connection to be established
  /// before returning the current database instance.
  Future<T? Function()> get asyncDb async {
    await _completer.future;
    return db;
  }

  /// Returns a function that provides the current database instance.
  ///
  /// The returned function will return null if no database connection is currently established.
  T? Function() get db => () => _db as T?;

  /// Establishes a remote database connection.
  Future<void> _innerConnect() async {
    final connectionResult = await DriftBridgeInterface.remote(_interface);
    if (connectionResult.isError) {
      if (autoReconnect) {
        _scheduleReconnect();
      }
      return;
    }

    _db = _factory(connectionResult.value!);
    if (!_completer.isCompleted) {
      _completer.complete(_db as T);
    }
    _db?.onDisconnect(_onDisconnect);
  }

  /// Handles the disconnection event of the current database instance.
  void _onDisconnect() {
    _db?.close(); //does this get hit?
    _db = null;
    if (autoReconnect) {
      _scheduleReconnect();
    }
  }

  /// Schedules a reconnection attempt after a specified delay.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _innerConnect);
  }

  /// Initiates a manual reconnection attempt.
  Future<void> reconnect() async {
    _reconnectTimer?.cancel();
    await _innerConnect();
  }

  /// Checks if a database connection is currently established.
  bool isConnected() => _db != null;

  /// Updates the interface used for remote communication.
  Future<void> updateInterface(DriftBridgeInterface newInterface) async {
    // ignore: invalid_use_of_protected_member
    if (_db?.resolvedEngine.connection.executor is! RemoteQueryExecutor &&
        _db != null) {
      return;
    }
    RemoteQueryExecutor? executor =
        // ignore: invalid_use_of_protected_member
        _db?.resolvedEngine.connection.executor as RemoteQueryExecutor?;

    executor?.close();
    _interface = newInterface;
    await _reconnectWithNewInterface();
  }

  /// Reconnects with the new interface.
  Future<void> _reconnectWithNewInterface() async {
    _reconnectTimer?.cancel();
    final remote = (_db?.executor as RemoteQueryExecutor?);
    (_db?.executor as RemoteQueryExecutor?)?.client.serverInfo;
    _db?.close();
    _db = null;
    _completer = Completer();
    await _innerConnect();
  }
}
