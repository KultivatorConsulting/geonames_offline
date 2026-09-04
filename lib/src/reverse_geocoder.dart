/// A populated place.
///
/// Returned by both lookups on [ReverseGeocoder]. Every value is GeoNames'
/// own, returned unmodified. In particular the administrative hierarchy is not
/// normalised: what a first-order division *is* varies by country — a state,
/// a region, a province, a prefecture — and any universal vocabulary would be
/// lossy and wrong somewhere. Consumers that need a friendlier label map it
/// themselves, with knowledge of their own audience.
final class GeoPlace {
  /// Creates a place.
  ///
  /// This is a plain value type and performs no validation: the fields mean
  /// whatever the dataset that produced them says they mean.
  const GeoPlace({
    required this.countryCode,
    required this.admin1Code,
    required this.geonameId,
    required this.name,
    required this.admin1Name,
    required this.countryName,
    required this.latitude,
    required this.longitude,
  });

  /// ISO 3166-1 alpha-2 country code, e.g. `NZ`.
  final String countryCode;

  /// GeoNames `admin1` code, verbatim, e.g. `G2`.
  ///
  /// `null` when GeoNames records no first-order division for the place.
  final String? admin1Code;

  /// The GeoNames identifier, e.g. `2179537` for Wellington, New Zealand.
  ///
  /// Stable enough to store, with one caveat: GeoNames retires, merges and
  /// splits entries between releases, so an id persisted today may be absent
  /// from a later dataset. [ReverseGeocoder.byId] returns `null` for such an
  /// id rather than substituting a nearest match, so that a dangling reference
  /// is detectable.
  final int geonameId;

  /// Display name of the place itself, e.g. `Wellington`.
  final String name;

  /// Display name of the first-order administrative division, if any,
  /// e.g. `Wellington` (the region).
  final String? admin1Name;

  /// Display name of the country, e.g. `New Zealand`.
  final String countryName;

  /// Latitude of the place in decimal degrees, as GeoNames records it.
  final double latitude;

  /// Longitude of the place in decimal degrees, as GeoNames records it.
  final double longitude;

  @override
  String toString() =>
      'GeoPlace($geonameId $name, $admin1Name, $countryName [$countryCode] '
      '@ $latitude, $longitude)';
}

/// The answer to a [ReverseGeocoder.nearest] query: a place, and how far it
/// is from the point that was asked about.
///
/// The distance lives here rather than on [GeoPlace] because only a query has
/// a point to measure from; a place looked up by id has none.
final class NearestPlace {
  /// Creates a result.
  const NearestPlace({required this.place, required this.distanceMetres});

  /// The nearest place.
  final GeoPlace place;

  /// Great-circle distance from the query point to [place], in metres.
  final double distanceMetres;

  @override
  String toString() => 'NearestPlace($place, $distanceMetres m)';
}

/// Resolves coordinates to the nearest populated place, offline.
///
/// Implementations never touch the network: every lookup is answered from a
/// dataset held in memory. The caller supplies the coordinates; this package
/// has no opinion about how they were obtained.
abstract class ReverseGeocoder {
  /// The nearest populated place to the point, or `null` if the dataset holds
  /// none at all.
  ///
  /// Applies no radius policy: a point in the middle of an ocean will return
  /// the nearest coastal city, hundreds of kilometres away, and that is
  /// correct behaviour. Callers decide what is too far by reading
  /// [NearestPlace.distanceMetres].
  NearestPlace? nearest(double latitude, double longitude);

  /// Looks up a previously stored identifier.
  ///
  /// Returns `null` when the id is not in this dataset — never a nearest-match
  /// substitute. GeoNames retires, merges and splits entries between releases,
  /// so a stored [GeoPlace.geonameId] will eventually dangle; a silent
  /// substitution would turn that stale reference into a confidently wrong
  /// one. Making the dangling case visible is this package's obligation, and
  /// deciding what to do about it is the caller's.
  GeoPlace? byId(int geonameId);

  /// Identifies the dataset in use, independently of the package version.
  ///
  /// GeoNames regenerates its exports daily, so the data changes far more
  /// often than the code. This value changes when the data does, and a
  /// consumer that built its own dataset with the generator sees its own
  /// value here rather than the package's.
  String get datasetVersion;

  /// The attribution text a consumer must display.
  ///
  /// The data is GeoNames, licensed under CC BY 4.0, which requires attribution
  /// to reach the users of an application that ships this package — not merely
  /// the readers of this repository. Render this string where the application
  /// shows its licences.
  String get attribution;
}
