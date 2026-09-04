// Measures how long a dataset takes to decode, cold (first call, JIT still
// compiling) and warm. Usage: dart run tool/bench_load.dart [dataset.gnof]
// With no argument it measures the bundled dataset, including its base64
// decoding.

import 'dart:io';

import 'package:geonames_offline/src/data/cities15000.dart';
import 'package:geonames_offline/src/format.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'bundled cities15000';
  final bytes = args.isNotEmpty
      ? File(args.first).readAsBytesSync()
      : cities15000DatasetBytes();
  final watch = Stopwatch()..start();
  var d = decodeDataset(bytes);
  final cold = watch.elapsedMicroseconds;
  const runs = 20;
  watch.reset();
  for (var i = 0; i < runs; i++) {
    d = decodeDataset(bytes);
  }
  final warm = watch.elapsedMicroseconds / runs;
  stdout.writeln(
    '$path: ${bytes.length} bytes, ${d.length} places, '
    'version "${d.datasetVersion}"',
  );
  stdout.writeln(
    'decode: cold ${(cold / 1000).toStringAsFixed(1)} ms, '
    'warm ${(warm / 1000).toStringAsFixed(1)} ms (mean of $runs)',
  );
}
