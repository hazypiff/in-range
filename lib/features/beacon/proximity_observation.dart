/// Source of a single proximity observation.
///
/// The estimator needs to know how a sample was produced because advert RSSI,
/// connected RSSI, and UWB distance are not interchangeable: they have
/// different statistical properties, different cadences, and different coverage.
/// Mixing them silently would train a model on apples-and-oranges data.
enum ProximitySource {
  /// BLE advert RSSI — current baseline. Coarse and sparse when locked.
  advertRssi,

  /// BLE connected-RSSI sample from a persistent GATT link (W5).
  connectedRssi,

  /// Nearby Interaction (UWB) distance estimate (W6).
  nearbyInteraction,

  /// GPS was used only as a far-away veto / candidate gate.
  gpsGate,

  /// WiFi venue fingerprint overlap score.
  wifiVenue,

  /// The current connected BSSID matched the peer's connected BSSID.
  bssidMatch,
}

/// One source-tagged proximity observation.
///
/// This envelope lets the estimator and trainer distinguish advert RSSI,
/// connected RSSI, and UWB distance instead of treating a denser RSSI stream
/// as a more precise version of the same advert signal.
class ProximityObservation {
  const ProximityObservation({
    required this.source,
    this.rssi,
    this.distanceM,
    this.horizontalAccuracyM,
    this.localState,
    this.linkState,
    this.tokenSlot,
  });

  final ProximitySource source;

  /// RSSI in dBm, when the source is a BLE radio observation.
  final int? rssi;

  /// Estimated distance in metres, when the source is UWB or a calibrated
  /// ranging source.
  final double? distanceM;

  /// GPS or NI horizontal accuracy, depending on source.
  final double? horizontalAccuracyM;

  /// Human-readable local app/screen state, e.g. "fg", "bg", "locked",
  /// "live_activity".
  final String? localState;

  /// Human-readable link state for connected sources, e.g. "discovered",
  /// "connecting", "connected", "subscribed".
  final String? linkState;

  /// Which token slot / rotation window this observation belongs to, for
  /// debugging token-rotation edge cases.
  final String? tokenSlot;
}
