/// Formatting utilities (MYR currency, dates, phones — Malaysian context).
class Formatters {
  Formatters._();

  /// Formats an integer amount as Malaysian Ringgit.
  /// e.g. 1200 → "RM 1,200"
  static String myr(int amount) {
    final formatted = amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    return 'RM $formatted';
  }

  /// Formats a double to MYR with 2 decimal places.
  /// e.g. 1299.50 → "RM 1,299.50"
  static String myrDecimal(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return 'RM $whole.${parts[1]}';
  }

  /// Formats a Malaysian phone number for display.
  /// e.g. "60123456789" → "+60 12-345 6789"
  static String phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return raw;
    // Format as +60 XX-XXX XXXX
    return '+${digits.substring(0, 2)} ${digits.substring(2, 4)}-'
        '${digits.substring(4, 7)} ${digits.substring(7)}';
  }
}
