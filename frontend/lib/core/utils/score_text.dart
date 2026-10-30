String scoreText(double value) {
  final percent = value.clamp(0.0, 1.0) * 100;
  if (percent > 0 && percent < 0.005) return '<0,01 %';
  if (value < 1 && percent >= 99.995) return '99,99 %';
  return '${percent.toStringAsFixed(2).replaceAll('.', ',')} %';
}
