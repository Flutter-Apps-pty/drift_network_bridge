class ErrorOr<T> {
  final T? value;
  final Object? error;

  ErrorOr(this.value, this.error);

  factory ErrorOr.value(T value) => ErrorOr(value, null);
  factory ErrorOr.error(Object error) => ErrorOr(null, error);

  bool get isError => error != null;

  bool get isValue => value != null;

  T? get valueOrNull => value;

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
