/// Converts absolute portfolio values into percentage change from the first
/// finite, non-zero value so accounts of different sizes can share one scale.
List<double> scalePortfolioSeriesForComparison(Iterable<double> values) {
  final source = values.toList(growable: false);
  double? baseline;
  for (final value in source) {
    if (value.isFinite && value.abs() > 1e-9) {
      baseline = value;
      break;
    }
  }
  if (baseline == null) {
    return List<double>.filled(source.length, 0, growable: false);
  }
  return [
    for (final value in source)
      value.isFinite ? ((value / baseline) - 1) * 100 : 0,
  ];
}
