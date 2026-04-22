enum FontScale {
  normal(1.0, 'Default'),
  large(1.3, 'Large'),
  extraLarge(1.6, 'Largest');

  const FontScale(this.value, this.label);
  final double value;
  final String label;
}
