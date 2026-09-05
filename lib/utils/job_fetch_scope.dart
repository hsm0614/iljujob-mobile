class JobFetchScope {
  final double? latitude;
  final double? longitude;
  final double? radiusKm;

  const JobFetchScope({this.latitude, this.longitude, this.radiusKm});

  factory JobFetchScope.fromSelection({
    required double latitude,
    required double longitude,
    required double radiusKm,
    required bool nationwide,
  }) {
    final hasLocation = latitude != 0.0 && longitude != 0.0;
    if (nationwide || !hasLocation) return const JobFetchScope();

    return JobFetchScope(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
    );
  }
}
