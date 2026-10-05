/// Mihomo filters commonly use a leading inline case-insensitive flag, which
/// Dart expresses as a RegExp option instead.
RegExp chainFilter(String pattern) {
  final ignoreCase = pattern.startsWith('(?i)');
  return RegExp(
    ignoreCase ? pattern.substring(4) : pattern,
    caseSensitive: !ignoreCase,
  );
}
