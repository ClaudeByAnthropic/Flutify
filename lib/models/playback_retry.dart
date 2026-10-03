/// One visible retry, first while waiting and then while opening the source.
class PlaybackRetry {
  static const int limit = 10;
  final int attempt;
  final Duration delay;
  final bool waiting;

  const PlaybackRetry(this.attempt, this.delay, {this.waiting = true});
}
