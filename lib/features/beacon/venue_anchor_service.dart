/// One venue anchor: a coarse circular region plus, when known, the hashed
/// BSSID of the network seen there (docs/SUBTLE_TRACKING_ARCHITECTURE.md).
///
/// The hashed BSSID is corroboration metadata for Dart-side venue matching —
/// a platform region (CLCircularRegion) is pure geometry, so it is NOT part
/// of the region descriptor handed to native. On a region wake the native
/// coordinator reports the region's [id] and Dart maps it back to this anchor
/// for BSSID corroboration.
class VenueAnchor {
  const VenueAnchor({
    required this.id,
    required this.lat,
    required this.lon,
    required this.radiusM,
    this.hashedBssid,
  });

  /// Stable identifier. Carried into the native region's `identifier`, so a
  /// region-enter/exit event maps back to this anchor.
  final String id;

  /// Coarse center. Anchors are venue-scale (hot venues, learned locals,
  /// manual test anchors) — never a precise user fix.
  final double lat;
  final double lon;

  /// Region radius in metres. Clamped to
  /// [VenueAnchorService.minRadiusM]..[VenueAnchorService.maxRadiusM] on upsert.
  final double radiusM;

  /// HMAC-SHA256 of the venue's BSSID with the rotating device salt, 12 hex
  /// chars — the same form as the Android venue matcher (Fingerprint.hashed),
  /// so client anchors and server reports are comparable. Null when no network
  /// was seen at the venue.
  final String? hashedBssid;
}

/// Maintains the local set of venue anchors and converts it into platform
/// region descriptors for the native SubtleWakeCoordinator (tier 3 of the
/// subtle-tracking architecture: wakes on entering/leaving a venue anchor).
///
/// Deliberately platform-free, like RssiUploader: the interesting behavior is
/// the capacity/eviction and clamping rules, and that is testable without a
/// method channel. The owner wires [onChanged] to the native push.
class VenueAnchorService {
  VenueAnchorService({this.maxAnchors = 20});

  /// iOS hard-caps region monitoring at 20 regions per app; registering a
  /// 21st silently fails. Keep the cap explicit and evict, rather than
  /// believing a registration the OS ignored.
  final int maxAnchors;

  /// Below ~100 m, entry/exit events get unreliable at GPS/cell-fix
  /// granularity — a venue anchor is not a room-level fence.
  static const double minRadiusM = 100;

  /// CLLocationManager refuses to monitor regions larger than its maximum
  /// region-monitoring distance (~2 km on current iOS).
  static const double maxRadiusM = 2000;

  /// Insertion-ordered: the first key is the oldest anchor and therefore the
  /// eviction candidate when the cap is reached.
  final Map<String, VenueAnchor> _anchors = {};

  /// Emitted after every mutation with the FULL descriptor list, so the owner
  /// can push a consistent snapshot to the native coordinator (region
  /// registration is a replace-all, not a delta protocol).
  void Function(List<Map<String, Object>> descriptors)? onChanged;

  List<VenueAnchor> get anchors => List.unmodifiable(_anchors.values);

  VenueAnchor? anchorById(String id) => _anchors[id];

  /// Adds or replaces an anchor. Returns false when the anchor is rejected
  /// (blank id, non-finite/out-of-range coordinates, non-positive radius).
  /// Radius is clamped rather than rejected: a server-supplied 5 km venue
  /// should degrade to the largest monitorable region, not vanish.
  ///
  /// At capacity a NEW id evicts the oldest anchor; replacing an existing id
  /// never evicts.
  bool upsert(VenueAnchor anchor) {
    if (anchor.id.trim().isEmpty) return false;
    if (!anchor.lat.isFinite || anchor.lat.abs() > 90) return false;
    if (!anchor.lon.isFinite || anchor.lon.abs() > 180) return false;
    if (!anchor.radiusM.isFinite || anchor.radiusM <= 0) return false;

    final clamped = VenueAnchor(
      id: anchor.id,
      lat: anchor.lat,
      lon: anchor.lon,
      radiusM: anchor.radiusM.clamp(minRadiusM, maxRadiusM),
      hashedBssid: anchor.hashedBssid,
    );

    if (!_anchors.containsKey(anchor.id) &&
        _anchors.length >= maxAnchors) {
      _anchors.remove(_anchors.keys.first);
    }
    _anchors[anchor.id] = clamped;
    _emit();
    return true;
  }

  bool remove(String id) {
    if (_anchors.remove(id) == null) return false;
    _emit();
    return true;
  }

  void clear() {
    if (_anchors.isEmpty) return;
    _anchors.clear();
    _emit();
  }

  /// What the native coordinator needs to build one CLCircularRegion per
  /// anchor (keys per SubtleWakeCoordinator.swift's `updateRegions`). The
  /// hashed BSSID is deliberately excluded: it is not a region property, and
  /// keeping it out of the payload keeps the native side from ever treating
  /// a network identifier as a location.
  List<Map<String, Object>> regionDescriptors() => [
        for (final a in _anchors.values)
          {
            'id': a.id,
            'lat': a.lat,
            'lon': a.lon,
            'radius': a.radiusM,
            'onEnter': true,
            'onExit': true,
          },
      ];

  void _emit() => onChanged?.call(regionDescriptors());
}
