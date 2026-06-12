import 'package:flutter/services.dart';

class RussianPhoneInputFormatter extends TextInputFormatter {
  const RussianPhoneInputFormatter();

  static String format(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return '';
    }

    if (digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    } else if (!digits.startsWith('7')) {
      digits = '7$digits';
    }

    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    final national = digits.length > 1 ? digits.substring(1) : '';
    final formatted = StringBuffer('+7');
    if (national.isNotEmpty) {
      formatted.write(' ');
      formatted.write(_formatNationalNumber(national));
    }

    return formatted.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = format(newValue.text);
    if (text.isEmpty) {
      return const TextEditingValue();
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String _formatNationalNumber(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    if (digits.length <= 6) {
      return '${digits.substring(0, 3)} ${digits.substring(3)}';
    }
    if (digits.length <= 8) {
      return '${digits.substring(0, 3)} ${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)}-${digits.substring(6, 8)}-${digits.substring(8)}';
  }
}
