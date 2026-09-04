import 'package:geonames_offline/geonames_offline.dart';

void main() {
  // Loads the bundled dataset: around 34,000 places with a population of
  // 15,000 or more, embedded in the package. Do this once and keep it.
  final geocoder = GeonamesReverseGeocoder.cities15000();
  print('Dataset: ${geocoder.datasetVersion}');

  const queries = [
    (-41.29, 174.78), // Wellington, New Zealand
    (48.86, 2.35), // central Paris: GeoNames lists arrondissements as places
    (-25.0, 135.0), // the middle of Australia: nothing close, still answered
    (-43.9, 179.9), // just west of the antimeridian
  ];
  for (final (latitude, longitude) in queries) {
    // null only for an empty dataset. No radius policy is applied for you:
    // read distanceMetres and decide what is too far.
    final hit = geocoder.nearest(latitude, longitude)!;
    final place = hit.place;
    final km = (hit.distanceMetres / 1000).toStringAsFixed(1);
    print(
      '($latitude, $longitude) -> ${place.name}, '
      '${place.admin1Name ?? '-'}, ${place.countryName} '
      '[${place.geonameId}], $km km away',
    );
  }

  // A stored id resolves again, and an id that is gone returns null rather
  // than a substitute, so a stale reference is detectable.
  print(geocoder.byId(2179537)?.name); // Wellington
  print(geocoder.byId(1)); // null

  // CC BY 4.0: show this to your users, for example on a licences screen.
  print(geocoder.attribution);
}
