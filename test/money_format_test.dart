// Para/yüzde/adet biçimleme — tek kaynak (lib/utils/money.dart) birim testleri.
// KALICI KURAL: para gösterimi MoneyText/formatMoney üzerinden, Türkçe yerel
// ('.' binlik, ',' ondalık) ve negatifte U+2212 MINUS SIGN (ASCII '-' DEĞİL).
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/utils/money.dart';

void main() {
  const minus = '−'; // U+2212 — ASCII tire ('-') ile karıştırma

  group('formatMoney — Türkçe yerel', () {
    test('binlik ayracı + 2 ondalık', () {
      expect(formatMoney(137526.54), '137.526,54');
      expect(formatMoney(1234.5), '1.234,50');
      expect(formatMoney(999.99), '999,99');
      expect(formatMoney(1000000), '1.000.000,00');
    });
    test('sıfır', () {
      expect(formatMoney(0), '0,00');
    });
    test('negatif U+2212 işareti (ASCII tire değil)', () {
      expect(formatMoney(-4086.2), '${minus}4.086,20');
      expect(formatMoney(-5), '${minus}5,00');
      expect(formatMoney(-4086.2).contains('-'), isFalse); // ASCII tire YOK
    });
    test('decimals: 0 → ondalık yok, yuvarlar', () {
      expect(formatMoney(1000, decimals: 0), '1.000');
      expect(formatMoney(1234.99, decimals: 0), '1.235');
    });
  });

  group('formatPct', () {
    test('virgül ondalık', () {
      expect(formatPct(5.17), '5,17');
      expect(formatPct(0), '0,00');
    });
    test('negatif U+2212', () {
      expect(formatPct(-3.7), '${minus}3,70');
    });
  });

  group('formatQty — sondaki sıfırlar atılır', () {
    test('tam sayı → ondalık yok', () {
      expect(formatQty(3), '3');
      expect(formatQty(3.0), '3');
    });
    test('kesirli → trailing-zero strip + virgül', () {
      expect(formatQty(1.2), '1,2');
      expect(formatQty(0.71060), '0,7106');
    });
  });

  group('formatPctSigned — kazançta +, zararda −', () {
    test('pozitif/sıfır → + öneki', () {
      expect(formatPctSigned(1.7), '+1,70');
      expect(formatPctSigned(0), '+0,00');
    });
    test('negatif → zaten U+2212', () {
      expect(formatPctSigned(-5.17), '${minus}5,17');
    });
  });
}
