import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/shared/russian_phone_input_formatter.dart';

void main() {
  const formatter = RussianPhoneInputFormatter();

  String apply(String input) {
    return formatter
        .formatEditUpdate(
          const TextEditingValue(),
          TextEditingValue(text: input),
        )
        .text;
  }

  test('formats Russian phone numbers from common inputs', () {
    expect(apply('7'), '+7');
    expect(apply('8'), '+7');
    expect(apply('932'), '+7 932');
    expect(apply('89321234567'), '+7 932 123-45-67');
    expect(apply('+7 (932) 123 45 67'), '+7 932 123-45-67');
  });

  test('limits input to Russian country code and ten national digits', () {
    expect(apply('932123456789999'), '+7 932 123-45-67');
  });
}
