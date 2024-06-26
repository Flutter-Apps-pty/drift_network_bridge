import 'package:drift/drift.dart';
// ignore: implementation_imports
import 'package:drift/src/remote/protocol.dart';

class NetworkDriftProtocol extends DriftProtocol {
  const NetworkDriftProtocol();
  static const _tag_BigInt = 'bigint';
  static const _tag_Datetime = 'datetime';
  dynamic _encodeDbValue(dynamic variable) {
    if (variable is List<int> && variable is! Uint8List) {
      return Uint8List.fromList(variable);
    } else if (variable is BigInt) {
      return [_tag_BigInt, variable.toString()];
    } else if (variable is DateTime) {
      return [_tag_Datetime, variable.toIso8601String()];
    } else {
      return variable;
    }
  }

  Object? _decodeDbValue(Object? wire) {
    if (wire is List) {
      if (wire.length == 2 && wire[0] == _tag_BigInt) {
        return BigInt.parse(wire[1].toString());
      }
      if (wire.length == 2 && wire[0] == _tag_Datetime) {
        return DateTime.parse(wire[1].toString());
      }

      return Uint8List.fromList(wire.cast());
    }
    return wire;
  }
}
