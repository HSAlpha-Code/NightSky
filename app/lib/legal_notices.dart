import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter automatically adds package notices; these cover our bundled data.
void registerDataLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'd3-celestial (Olaf Frohn)': 'assets/legal/d3-celestial-BSD.txt',
      'OpenNGC (Mattia Verga)': 'assets/legal/OpenNGC-CC-BY-SA-4.0.txt',
      'NightSky': 'assets/legal/NightSky-MIT.txt',
      'AndroidX WorkManager (Android Open Source Project)':
          'assets/legal/AndroidX-Apache-2.0.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
}
