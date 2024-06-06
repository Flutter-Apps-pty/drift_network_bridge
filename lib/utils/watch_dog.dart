import 'dart:async';

class Watchdog {
  Watchdog({this.timeout, this.onTimeout});

  Duration? timeout;
  Function? onTimeout;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;

  Duration get remainingTime {
    print('timeout!.inMilliseconds: ${timeout?.inMilliseconds}');
    print('_stopwatch.elapsedMilliseconds: ${_stopwatch.elapsedMilliseconds}');
    return timeout == null
        ? Duration.zero
        : Duration(
            milliseconds:
                timeout!.inMilliseconds - _stopwatch.elapsedMilliseconds);
  }

  void start({Duration? timeout, Function()? onTimeout}) {
    this.timeout = timeout ?? this.timeout;
    this.onTimeout = onTimeout ?? this.onTimeout;

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _stopwatch.reset();
    _stopwatch.start();
    _timer = Timer(timeout ?? Duration(seconds: 30), () {
      onTimeout?.call();
    });
  }

  bool get isRunning {
    return _timer?.isActive ?? false;
  }

  void pat() {
    if (isRunning) {
      _startTimer();
    }
  }

  void stop() {
    _stopwatch.stop();
    _timer?.cancel();
  }
}
