import 'dart:async';

/// Retryable cloud-claim upload with bounded exponential backoff, session
/// generation guards, and teardown cancellation — extracted from BeaconService
/// so the retry / rotation / teardown behavior is unit-testable without the
/// BLE + Supabase platform stack (reviewer #11).
///
/// The BeaconService owns the token and location; this only owns "get the
/// current claim uploaded, retrying transient failures, and report the
/// cloud-sync state after every attempt."
class ClaimManager {
  ClaimManager({required Future<void> Function() upload}) : _upload = upload;

  /// Uploads the CURRENT claim. Throws on failure (any exception → retry).
  final Future<void> Function() _upload;

  /// Emits the cloud-sync result after every attempt (success or failure).
  void Function(bool cloudSynced)? onState;

  /// 2, 4, 8, 16, 32 s — then stop retrying until the next rotation.
  static const int maxRetries = 5;

  int _generation = 0;
  int _attempt = 0;
  Timer? _retry;

  bool get hasPendingRetry => _retry != null;
  int get attemptCount => _attempt;

  /// A new token (rotation) supersedes any in-flight retry. Returns the new
  /// generation the caller passes to [attempt].
  int newSession() {
    _retry?.cancel();
    _retry = null;
    _attempt = 0;
    return ++_generation;
  }

  /// Teardown: cancel pending retries AND supersede any in-flight attempt
  /// (the generation bump makes a resuming attempt return without firing).
  void cancel() {
    _retry?.cancel();
    _retry = null;
    _attempt = 0;
    _generation++;
  }

  Future<void> attempt(int gen) async {
    if (gen != _generation) return;
    try {
      await _upload();
      if (gen != _generation) return; // superseded mid-flight
      _retry?.cancel();
      _retry = null;
      _attempt = 0;
      onState?.call(true);
    } catch (_) {
      if (gen != _generation) return;
      onState?.call(false);
      // The timer that triggered this attempt has fired; it is no longer
      // pending unless we reschedule below (otherwise hasPendingRetry lies).
      _retry = null;
      if (_attempt < maxRetries) {
        final delay = Duration(seconds: 2 << _attempt);
        _attempt++;
        _retry = Timer(delay, () {
          if (gen != _generation) return;
          unawaited(attempt(gen));
        });
      }
    }
  }
}
