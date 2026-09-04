// Command-line front end for the generator. Run with
// `dart run geonames_offline:generate --help`.

import 'dart:io';

import 'package:geonames_offline/src/generator.dart';

const _usage = '''
Builds a geonames_offline dataset from GeoNames export files.

Usage: dart run geonames_offline:generate [options]

  --cities <file>          cities15000.txt, cities1000.txt, or any file in
                           the same format (required)
  --admin1 <file>          admin1CodesASCII.txt (required)
  --country-info <file>    countryInfo.txt (required)
  --output <file>          where to write the dataset (required)
  --countries NZ,AU        keep only these ISO 3166-1 alpha-2 countries
  --dataset-version <s>    override the derived dataset version string
  --help                   show this text

Fetch the inputs with tool/fetch_geonames.sh. Options may also be written as
--name=value.
''';

void main(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      stdout.write(_usage);
      return;
    }
    if (!arg.startsWith('--')) return _usageError('Unexpected argument "$arg"');
    final eq = arg.indexOf('=');
    final String name;
    final String value;
    if (eq >= 0) {
      name = arg.substring(2, eq);
      value = arg.substring(eq + 1);
    } else {
      name = arg.substring(2);
      if (i + 1 >= args.length) return _usageError('Missing value for --$name');
      value = args[++i];
    }
    if (!_known.contains(name)) return _usageError('Unknown option --$name');
    options[name] = value;
  }
  for (final required in ['cities', 'admin1', 'country-info', 'output']) {
    if (!options.containsKey(required)) {
      return _usageError('--$required is required');
    }
  }

  final citiesPath = options['cities']!;
  final countries = options['countries']
      ?.split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toSet();
  try {
    final result = generateDataset(
      citiesTsv: File(citiesPath).readAsStringSync(),
      admin1CodesTsv: File(options['admin1']!).readAsStringSync(),
      countryInfoTsv: File(options['country-info']!).readAsStringSync(),
      sourceName: _basenameWithoutExtension(citiesPath),
      countries: countries,
      datasetVersion: options['dataset-version'],
    );
    final output = File(options['output']!);
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(result.bytes);
    stdout.writeln(
      'Wrote ${output.path}: ${result.bytes.length} bytes, '
      '${result.placeCount} places, version "${result.datasetVersion}"',
    );
  } on FileSystemException catch (e) {
    stderr.writeln('${e.message}: ${e.path}');
    exitCode = 66;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 65;
  }
}

const _known = {
  'cities',
  'admin1',
  'country-info',
  'output',
  'countries',
  'dataset-version',
};

void _usageError(String message) {
  stderr
    ..writeln(message)
    ..writeln()
    ..write(_usage);
  exitCode = 64;
}

String _basenameWithoutExtension(String path) {
  final base = path.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
