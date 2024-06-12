/// Contains utils to run drift databases over a network.
///
/// Please note that this API requires a network interface to be implemented.
library drift_network_bridge;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:drift_network_bridge/drift_network_bridge.dart';
import 'package:drift_network_bridge/error_handling/error_or.dart';
import 'package:drift_network_bridge/src/network_remote/network_client_impl.dart';
import 'package:drift_network_bridge/src/network_remote/network_communication.dart';
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';
// ignore: implementation_imports
import 'package:drift/src/remote/protocol.dart';

import 'bridge/network_bridge_server.dart';

/// Signature of a function that opens a database connection.
typedef DatabaseOpener = QueryExecutor Function();

/// Defines utilities to run drift over a network. In the operation
/// mode created by these utilities, there's a single server instance doing
/// all the work. Any other client can use the [connect] method to obtain an
/// instance of a [GeneratedDatabase] class that will delegate its work onto the
/// server. Auto-updating queries, and transactions work across the network, and
/// the user facing api is exactly the same.
///
/// Please note that, while running drift over a network can reduce
/// lags in client applications, the overall database performance will be worse.
/// This is because result data is not available directly and instead needs to be
/// transferred over the network.
///
/// The easiest way to use drift over a network is to use
/// `NativeDatabase.createOnServer`, which is a drop-in replacement for
/// `NativeDatabase` that uses a [DriftBridgeServer] under the hood.
///
/// See also:
/// - The [detailed documentation](https://drift.simonbinder.eu/docs/advanced-features/network),
///   which provides example codes on how to use this api.
class DriftBridgeServer {
  /// The underlying network interface used to establish a connection with this
  /// [DriftBridgeServer].
  ///
  /// This interface can be implemented using various network protocols such as
  /// TCP, UDP, Firebase, MQTT, etc.
  final DriftBridgeInterface networkInterface;

  /// The flag indicating whether messages between this [DriftBridgeServer]
  /// and the clients should be serialized.
  final bool serialize;

  final NetworkDriftServer? server;

  /// Creates a [DriftBridgeServer] talking to clients by using the
  /// [DriftBridgeInterface].
  ///
  /// {@template drift_server_serialize}
  /// Internally, drift uses a network interface to send commands to the server
  /// dispatching database actions.
  /// In most setups, those channels can send and receive almost any Dart object.
  /// In special cases though, the platform only supports sending simple types
  /// across the network. To support those setups, drift can serialize its
  /// internal communication to only send simple types across the network. The
  /// [serialize] parameter, which is enabled by default, controls this behavior.
  ///
  /// In most scenarios, [serialize] can be disabled for a considerable
  /// performance improvement.
  /// {@endtemplate}
  DriftBridgeServer(this.networkInterface,
      {this.serialize = true, this.server});

  Future<StreamChannel> _open() {
    return remoteConnectToServer(networkInterface, serialize);
  }

  /// Connects to this [DriftBridgeServer] from a client.
  ///
  /// All operations on the returned [DatabaseConnection] will be executed on the
  /// server.
  ///
  /// When [singleClientMode] is enabled (it defaults to `false`), drift assumes
  /// that the server will only be connected to once. In this mode, drift will
  /// shutdown the server once the returned [DatabaseConnection] is closed.
  /// Also, stream queries are more efficient when this mode is enables since we
  /// don't have to synchronize table updates to other clients (since there are
  /// none).
  ///
  /// Setting the [serverDebugLog] is only helpful when debugging drift itself.
  /// It will print messages exchanged between the client and the server.
  Future<ErrorOr<DatabaseConnection>> connect({
    bool serverDebugLog = false,
    bool singleClientMode = false,
  }) async {
    try {
      final connection = await connectToNetworkAndInitialize(
        await _open(),
        debugLog: serverDebugLog,
        serialize: serialize,
        singleClientMode: singleClientMode,
      ).timeout(DriftNetworkCommunication.timeout, onTimeout: () {
        throw TimeoutException('Connection to server timed out');
      });
      return ErrorOr.value(DatabaseConnection(connection.executor,
          streamQueries: connection.streamQueries, connectionData: this));
    } catch (e) {
      return ErrorOr.error(e);
    }
  }

  /// Stops the server and disconnects all [DatabaseConnection]s created.
  /// If you only want to disconnect a database connection created via
  /// [connect], use [GeneratedDatabase.close] instead.
  Future<void> shutdownAll() async {
    return shutdown(await _open(), serialize: serialize);
  }

  /// Creates a new [DriftBridgeServer] that listens for client connections.
  ///
  /// The [opener] function will be used to open the [DatabaseConnection] used
  /// by the server.
  ///
  /// To close the server later, use [shutdownAll]. Or, if you know that only
  /// a single client will connect, set `singleClientMode: true` in [connect].
  /// That way, the drift server will shutdown when the client is closed.
  ///
  /// {@macro drift_server_serialize}
  static Future<DriftBridgeServer> create(
    DatabaseOpener opener, {
    bool serialize = false,
    required DriftBridgeInterface networkInterface,
  }) async {
    NetworkDriftServer(networkInterface, opener(), killServerWhenDone: false);

    return DriftBridgeServer(networkInterface, serialize: serialize);
  }

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void simulateNetworkFailure() => server?.simulateNetworkFailure();

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  void simulateNetworkRecovery() => server?.simulateNetworkRecovery();
}

/// Experimental methods to connect to an existing drift database from different
/// clients over a network.
extension ComputeWithDriftBridgeServer<DB extends DatabaseConnectionUser>
    on DB {
  @experimental
  Future<DriftBridgeServer> hostAll(
      List<DriftBridgeInterface> networkInterfaces,
      {bool onlyAcceptSingleConnection = false}) async {
    return host(DriftMultipleInterface(networkInterfaces),
        onlyAcceptSingleConnection: onlyAcceptSingleConnection);
  }

  @experimental
  bool isConnected() {
    // ignore: invalid_use_of_protected_member
    if (resolvedEngine.connection.executor is! RemoteQueryExecutor) {
      return false;
    }
    final client =
        // ignore: invalid_use_of_protected_member
        (resolvedEngine.connection.executor as RemoteQueryExecutor).client;
    return client.isConnected();
  }

  void onDisconnect(void Function() callback) {
    // ignore: invalid_use_of_protected_member
    if (resolvedEngine.connection.executor is! RemoteQueryExecutor) {
      return;
    }
    final client =
        // ignore: invalid_use_of_protected_member
        (resolvedEngine.connection.executor as RemoteQueryExecutor).client;
    client.onDisconnect(callback);
  }

  /// Creates a [DriftBridgeServer] that, when connected to, will run queries on the
  /// database already opened by `this`.
  ///
  /// This can be used to share an existing database across a network, as instances
  /// of generated database classes can't be sent over the network by default. A
  /// [DriftBridgeServer] can be created though, which enables a concise way to open a
  /// temporary server that is using an existing database:
  ///
  /// ```dart
  /// Future<void> main() async {
  ///   final database = MyDatabase(...);
  ///
  ///   // Create a server based on the existing database
  ///   final server = await database.networkConnection(DriftBridgeInterface);
  ///
  ///   // Clients can connect to the server and use the same logical database
  ///   final client = MyDatabase(await server.connect());
  ///   await client.batch(...);
  /// }
  /// ```
  ///
  /// The example of running a short-lived server for a single task unit
  /// requiring a database is also available through [networkWithDatabase].
  @experimental
  Future<DriftBridgeServer> host(DriftBridgeInterface networkInterface,
      {bool onlyAcceptSingleConnection = false}) async {
    // ignore: invalid_use_of_protected_member
    final localConnection = resolvedEngine.connection;

    // Set up a drift server acting as a proxy to the existing database
    // connection.
    final server = NetworkDriftServer(
      networkInterface,
      localConnection,
      onlyAcceptSingleConnection: onlyAcceptSingleConnection,
      closeConnectionAfterShutdown: true,
      killServerWhenDone: false,
    );

    // Since the existing database didn't use a server, we need to
    // manually forward stream query updates.
    final forwardToServer = tableUpdates().listen((localUpdates) {
      server.server.dispatchTableUpdateNotification(
          NotifyTablesUpdated(localUpdates.toList()));
    });
    final forwardToLocal =
        server.server.tableUpdateNotifications.listen((remoteUpdates) {
      notifyUpdates(remoteUpdates.updates.toSet());
    });
    server.server.done.whenComplete(() {
      forwardToServer.cancel();
      forwardToLocal.cancel();
    });

    return DriftBridgeServer(
      networkInterface,
      serialize: true,
      server: server,
    );
  }

  /// Creates a short-lived server to run the [computation] with a drift
  /// database.
  ///
  /// Essentially, this is a variant of running a computation over a network for
  /// computations that also need to share a drift database between them. As
  /// drift databases are stateful objects, they can't be send over the network
  /// without special setup.
  ///
  /// This method will extract the underlying database connection of `this`
  /// database into a form that can be serialized over the network. Then, a
  /// server will be created to invoke [computation]. The [connect] function is
  /// responsible for creating an instance of your database class from the
  /// low-level connection.
  ///
  /// As an example, consider a database class:
  ///
  /// ```dart
  /// class MyDatabase extends $MyDatabase {
  ///   MyDatabase(QueryExecutor executor): super(executor);
  /// }
  /// ```
  ///
  /// [networkWithDatabase] can then be used to access an instance of
  /// `MyDatabase` on a client, even though `MyDatabase` is not generally
  /// sharable over the network:
  ///
  /// ```dart
  /// Future<void> loadBulkData(MyDatabase db, NetworkInterface networkInterface) async {
  ///   await db.networkWithDatabase(
  ///     networkInterface: networkInterface,
  ///     connect: MyDatabase.new,
  ///     computation: (db) async {
  ///       // This computation has access to a second `db` that is internally
  ///       // linked to the original database.
  ///       final data = await fetchRowsFromNetwork();
  ///       await db.batch((batch) {
  ///         // More expensive work like inserting data
  ///       });
  ///     },
  ///   );
  /// }
  /// ```
  ///
  /// Note that with the recommended setup of `NativeDatabase.createOnServer`,
  /// drift will already use a server to run your SQL statements. Using
  /// [networkWithDatabase] is beneficial when an expensive work unit needs
  /// to use the database, or when creating the SQL statements itself is
  /// expensive.
  @experimental
  Future<Ret> networkWithDatabase<Ret>({
    required FutureOr<Ret> Function(DB) computation,
    required DB Function(DatabaseConnection) connect,
    required DriftBridgeInterface networkInterface,
  }) async {
    final server = await host(networkInterface);
    final connResult = await server.connect();
    if (connResult.isError) {
      throw connResult.error!;
    }
    final database = connect(connResult.value!);
    try {
      return await computation(database);
    } finally {
      await database.close();
    }
  }
}
