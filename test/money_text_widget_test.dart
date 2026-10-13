// MoneyText widget testi — para gösteriminin KALICI KURAL'a uygun render'ı.
// MoneyText hem düz Text hem (dimDecimals) Text.rich üretir; ikisi de altta
// RichText'tir → toPlainText() ile birleşik metni doğrularız. Tema
// AppTheme.dark() ile kurulur (AppColorsExt.of(context) için gerekli).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/theme/app_theme.dart';

Future<String> _render(WidgetTester tester, Widget money) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: Center(child: money)),
  ));
  await tester.pump();
  final rt = tester.widget<RichText>(
    find.descendant(
      of: find.byType(MoneyText),
      matching: find.byType(RichText),
    ).first,
  );
  return rt.text.toPlainText();
}

void main() {
  const minus = '−';

  testWidgets('varsayılan: ₺ öneki + Türkçe biçim', (tester) async {
    expect(await _render(tester, const MoneyText(1234.5)), '₺1.234,50');
  });

  testWidgets('negatif U+2212 (ASCII tire değil)', (tester) async {
    final s = await _render(tester, const MoneyText(-4086.2));
    expect(s, '₺${minus}4.086,20');
    expect(s.contains('-'), isFalse);
  });

  testWidgets('decimals:0 + farklı para birimi', (tester) async {
    expect(
      await _render(tester, const MoneyText(1000, currency: r'$', decimals: 0)),
      r'$1.000',
    );
  });

  testWidgets('prefix "+" işaretli gösterim', (tester) async {
    expect(await _render(tester, const MoneyText(50, prefix: '+')), '+₺50,00');
  });

  testWidgets('dimDecimals: span bölünür ama birleşik metin aynı', (tester) async {
    expect(
      await _render(tester, const MoneyText(1234.5, dimDecimals: true)),
      '₺1.234,50',
    );
  });
}
