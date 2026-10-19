class Formatters {
  Formatters._();

  static String formatOrderNumber(String orderNumber) {
    final n = orderNumber.trim();
    if (n.isEmpty) return '—';
    return n;
  }

  static String myr(int amount) {
    final formatted = amount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    return 'RM $formatted';
  }

  static String myrDecimal(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return 'RM $whole.${parts[1]}';
  }

  static String phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return raw;
    return '+${digits.substring(0, 2)} ${digits.substring(2, 4)}-'
        '${digits.substring(4, 7)} ${digits.substring(7)}';
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String shortDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')} '
        '${_months[d.month - 1]} ${d.year}';
  }

  static String shortDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${shortDate(d)} · $hh:$mm';
  }

  static String monthShort(int month) => _months[month - 1];
}
