import 'package:drift/drift.dart';
// ignore: implementation_imports
import 'package:drift/src/remote/protocol.dart';
import 'package:postgres/postgres.dart' show TypeRegistry, TypedValue;
// ignore: implementation_imports
import 'package:postgres/src/types/type_registry.dart';

class NetworkDriftProtocol {
  const NetworkDriftProtocol();
  static const _tag_Request = 0;
  static const _tag_Response_success = 1;
  static const _tag_Response_error = 2;
  static const _tag_Response_cancelled = 3;

  static const _tag_NoArgsRequest_terminateAll = 0;

  static const _tag_ExecuteQuery = 3;
  static const _tag_ExecuteBatchedStatement = 4;
  static const _tag_RunTransactionAction = 5;
  static const _tag_EnsureOpen = 6;
  static const _tag_RunBeforeOpen = 7;
  static const _tag_NotifyTablesUpdated = 8;
  static const _tag_DirectValue = 10;
  static const _tag_SelectResult = 11;
  static const _tag_RequestCancellation = 12;
  static const _tag_ServerInfo = 13;

  static const _tag_BigInt = 'bigint';
  static const _tag_DateTime = 'dateTime';
  static const _tag_TypedValue = 'typedValue';

  Object? serialize(Message message) {
    if (message is Request) {
      return [
        _tag_Request,
        message.id,
        encodePayload(message.payload),
      ];
    } else if (message is ErrorResponse) {
      return [
        _tag_Response_error,
        message.requestId,
        message.error.toString(),
        message.stackTrace?.toString(),
      ];
    } else if (message is SuccessResponse) {
      return [
        _tag_Response_success,
        message.requestId,
        encodePayload(message.response),
      ];
    } else if (message is CancelledResponse) {
      return [_tag_Response_cancelled, message.requestId];
    } else {
      return null;
    }
  }

  Message deserialize(Object message) {
    if (message is! List) throw const FormatException('Cannot read message');

    final tag = message[0];
    final id = message[1] as int;

    switch (tag) {
      case _tag_Request:
        return Request(id, decodePayload(message[2]) as RequestPayload?);
      case _tag_Response_error:
        final stringTrace = message[3] as String?;

        return ErrorResponse(id, message[2] as Object,
            stringTrace != null ? StackTrace.fromString(stringTrace) : null);
      case _tag_Response_success:
        return SuccessResponse(
            id, decodePayload(message[2]) as ResponsePayload?);
      case _tag_Response_cancelled:
        return CancelledResponse(id);
    }

    throw const FormatException('Unknown tag');
  }

  dynamic encodePayload(dynamic payload) {
    if (payload == null) return payload;

    if (payload is NoArgsRequest) {
      return payload.index;
    } else if (payload is ExecuteQuery) {
      return [
        _tag_ExecuteQuery,
        payload.method.index,
        payload.sql,
        [for (final arg in payload.args) _encodeDbValue(arg)],
        payload.executorId,
      ];
    } else if (payload is ExecuteBatchedStatement) {
      return [
        _tag_ExecuteBatchedStatement,
        payload.stmts.statements,
        for (final arg in payload.stmts.arguments)
          [
            arg.statementIndex,
            for (final value in arg.arguments) _encodeDbValue(value),
          ],
        payload.executorId,
      ];
    } else if (payload is RunNestedExecutorControl) {
      return [
        _tag_RunTransactionAction,
        payload.control.index,
        payload.executorId,
      ];
    } else if (payload is EnsureOpen) {
      return [_tag_EnsureOpen, payload.schemaVersion, payload.executorId];
    } else if (payload is ServerInfo) {
      return [
        _tag_ServerInfo,
        payload.dialect.name,
      ];
    } else if (payload is RunBeforeOpen) {
      return [
        _tag_RunBeforeOpen,
        payload.details.versionBefore,
        payload.details.versionNow,
        payload.createdExecutor,
      ];
    } else if (payload is NotifyTablesUpdated) {
      return [
        _tag_NotifyTablesUpdated,
        for (final update in payload.updates)
          [
            update.table,
            update.kind?.index,
          ]
      ];
    } else if (payload is SelectResult) {
      // We can't necessary transport maps, so encode as list
      final rows = payload.rows;
      if (rows.isEmpty) {
        return const [_tag_SelectResult];
      } else {
        // Encode by first sending column names, followed by row data
        final result = <Object?>[_tag_SelectResult];

        final columns = rows.first.keys.toList();
        result
          ..add(columns.length)
          ..addAll(columns);

        result.add(rows.length);
        for (final row in rows) {
          for (final value in row.values) {
            result.add(_encodeDbValue(value));
          }
        }
        return result;
      }
    } else if (payload is RequestCancellation) {
      return [_tag_RequestCancellation, payload.originalRequestId];
    } else if (payload is PrimitiveResponsePayload) {
      return switch (payload.message) {
        final bool boolean => boolean,
        final int integer => [_tag_DirectValue, integer],
        _ => throw UnsupportedError('Unknown primitive response'),
      };
    }
  }

  dynamic decodePayload(dynamic encoded) {
    if (encoded == null) {
      return null;
    }
    if (encoded is bool) {
      return PrimitiveResponsePayload.bool(encoded);
    }
    int tag;
    List? fullMessage;

    if (encoded is int) {
      tag = encoded;
    } else {
      fullMessage = encoded as List;
      tag = fullMessage[0] as int;
    }

    int readInt(int index) => fullMessage![index] as int;
    int? readNullableInt(int index) => fullMessage![index] as int?;

    switch (tag) {
      case _tag_NoArgsRequest_terminateAll:
        return NoArgsRequest.terminateAll;
      case _tag_ExecuteQuery:
        final method = StatementMethod.values[readInt(1)];
        final sql = fullMessage![2] as String;
        final args = (fullMessage[3] as List).map(_decodeDbValue).toList();
        final executorId = readNullableInt(4);
        return ExecuteQuery(method, sql, args, executorId);
      case _tag_ExecuteBatchedStatement:
        final sql = (fullMessage![1] as List).cast<String>();
        final args = <ArgumentsForBatchedStatement>[];

        for (var i = 2; i < fullMessage.length - 1; i++) {
          final list = fullMessage[i] as List;
          args.add(ArgumentsForBatchedStatement(
              list[0] as int, list.skip(1).toList()));
        }

        final executorId = fullMessage.last as int?;
        return ExecuteBatchedStatement(
            BatchedStatements(sql, args), executorId);
      case _tag_RunTransactionAction:
        final control = NestedExecutorControl.values[readInt(1)];
        return RunNestedExecutorControl(control, readNullableInt(2));
      case _tag_EnsureOpen:
        return EnsureOpen(readInt(1), readNullableInt(2));
      case _tag_ServerInfo:
        return ServerInfo(SqlDialect.values.byName(fullMessage![1] as String));
      case _tag_RunBeforeOpen:
        return RunBeforeOpen(
          OpeningDetails(readNullableInt(1), readInt(2)),
          readInt(3),
        );
      case _tag_NotifyTablesUpdated:
        final updates = <TableUpdate>[];
        for (var i = 1; i < fullMessage!.length; i++) {
          final encodedUpdate = fullMessage[i] as List;
          final kindIndex = encodedUpdate[1] as int?;

          updates.add(
            TableUpdate(encodedUpdate[0] as String,
                kind: kindIndex == null ? null : UpdateKind.values[kindIndex]),
          );
        }
        return NotifyTablesUpdated(updates);
      case _tag_SelectResult:
        if (fullMessage!.length == 1) {
          // Empty result set, no data
          return const SelectResult([]);
        }

        final columnCount = readInt(1);
        final columns = fullMessage.sublist(2, 2 + columnCount).cast<String>();
        final rows = readInt(2 + columnCount);

        final result = <Map<String, Object?>>[];
        for (var i = 0; i < rows; i++) {
          final rowOffset = 3 + columnCount + i * columnCount;

          result.add({
            for (var c = 0; c < columnCount; c++)
              columns[c]: _decodeDbValue(fullMessage[rowOffset + c])
          });
        }
        return SelectResult(result);
      case _tag_RequestCancellation:
        return RequestCancellation(readInt(1));
      case _tag_DirectValue:
        return PrimitiveResponsePayload.int(castInt(encoded[1]));
    }

    throw ArgumentError.value(tag, 'tag', 'Tag was unknown');
  }

  dynamic _encodeDbValue(dynamic variable) {
    if (variable is List<int> && variable is! Uint8List) {
      return Uint8List.fromList(variable);
    } else if (variable is BigInt) {
      return [_tag_BigInt, variable.toString()];
    } else if (variable is DateTime) {
      return [_tag_DateTime, variable.toIso8601String()];
    } else if (variable is TypedValue) {
      return [
        _tag_TypedValue,
        variable.type.oid,
        _encodeDbValue(variable.value)
      ];
    } else {
      return variable;
    }
  }

  Object? _decodeDbValue(Object? wire) {
    if (wire is List) {
      if (wire.length == 2 && wire[0] == _tag_BigInt) {
        return BigInt.parse(wire[1].toString());
      }
      if (wire.length == 2 && wire[0] == _tag_DateTime) {
        return DateTime.parse(wire[1].toString());
      }
      if (wire.length == 3 && wire[0] == _tag_TypedValue) {
        // Create a Type instance based on the OID
        TypeRegistry registry = TypeRegistry();
        final type = registry.resolveOid(wire[1] as int);
        return TypedValue(type, _decodeDbValue(wire[2]));
      }

      return Uint8List.fromList(wire.cast());
    }
    return wire;
  }
}
