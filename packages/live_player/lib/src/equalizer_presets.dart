/// 10 standard audio equalizer center frequencies in Hz.
abstract final class AudioEqualizerConsts {
  /// The 10 center frequencies in Hz.
  static const frequencies = [
    '31',
    '62',
    '125',
    '250',
    '500',
    '1000',
    '2000',
    '4000',
    '8000',
    '16000',
  ];

  /// Human readable frequency labels.
  static const frequencyLabels = [
    '31Hz',
    '62Hz',
    '125Hz',
    '250Hz',
    '500Hz',
    '1kHz',
    '2kHz',
    '4kHz',
    '8kHz',
    '16kHz',
  ];

  /// Standard equalizer presets.
  static const Map<String, Map<String, double>> presets = {
    'off': {},
    'vocal': {
      '31': -2.0,
      '62': -1.0,
      '125': 0.0,
      '250': 1.0,
      '500': 2.0,
      '1000': 3.5,
      '2000': 4.0,
      '4000': 2.5,
      '8000': 1.0,
      '16000': 0.0,
    },
    'bass_boost': {
      '31': 5.0,
      '62': 4.5,
      '125': 3.0,
      '250': 1.5,
      '500': 0.0,
      '1000': 0.0,
      '2000': 0.0,
      '4000': 0.0,
      '8000': -1.0,
      '16000': -2.0,
    },
    'treble_boost': {
      '31': -2.0,
      '62': -1.0,
      '125': 0.0,
      '250': 0.0,
      '500': 0.5,
      '1000': 1.0,
      '2000': 2.5,
      '4000': 4.0,
      '8000': 5.0,
      '16000': 5.5,
    },
    'cinema': {
      '31': 3.5,
      '62': 2.5,
      '125': 1.0,
      '250': 0.0,
      '500': -2.0,
      '1000': -1.0,
      '2000': 1.5,
      '4000': 3.0,
      '8000': 2.5,
      '16000': 2.0,
    },
  };

  /// Resolves the effective 10-band gains for [preset] and optional [customBands].
  static Map<String, double> resolveBands(String preset, [Map<String, Object?>? customBands]) {
    if (preset == 'custom' && customBands != null && customBands.isNotEmpty) {
      return {
        for (final f in frequencies)
          if (customBands[f] case final num val) f: val.toDouble(),
      };
    }
    return presets[preset] ?? const {};
  }
}
