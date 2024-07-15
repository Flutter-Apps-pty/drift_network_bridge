/// A class that represents either a value of type T or an error.
/// This can be used to handle scenarios where an operation might return a value or an error.
class ErrorOr<T> {
  /// The value of type T, if present.
  final T? value;

  /// The error object, if an error occurred.
  final Object? error;

  /// Constructs an ErrorOr instance with either a value or an error.
  ErrorOr(this.value, this.error);

  /// Creates an ErrorOr instance representing a successful result with a value.
  factory ErrorOr.value(T value) => ErrorOr(value, null);

  /// Creates an ErrorOr instance representing an error result.
  factory ErrorOr.error(Object error) => ErrorOr(null, error);

  /// Returns true if this instance represents an error.
  bool get isError => error != null;

  /// Returns true if this instance represents a value.
  bool get isValue => value != null;

  /// Returns the value if present, or null if this instance represents an error.
  T? get valueOrNull => value;

  /// Returns the value if present, or throws the error if this instance represents an error.
  T get valueOrThrow {
    if (isError) {
      throw error!;
    }
    return value!;
  }

  @override
  String toString() {
    if (isError) {
      return 'ErrorOr.error($error)';
    } else {
      return 'ErrorOr.value($value)';
    }
  }
}
