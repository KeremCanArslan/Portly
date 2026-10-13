// Onboarding turu (45. tur) akış testi — ilk-açılış tanıtımının "doğru iş"
// olduğunu kanıtlar: 4 tanıtım sayfası, "Atla" → onDone, "İleri" sayfayı
// ilerletir (onDone ÇAĞIRMAZ), son sayfada buton "Başla"ya döner ve dokununca
// onDone çağrılır. Tema AppTheme.dark() ile kurulur (AppColorsExt.of(context)
// için). OnboardingScreen provider/ağ kullanmaz → pumpAndSettle güvenli.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/screens/onboarding_screen.dart';
import 'package:portly/theme/app_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, VoidCallback onDone) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: OnboardingScreen(onDone: onDone),
    ));
    await tester.pumpAndSettle();
  }

  // 4 sayfalık tur → sona ulaşmak için 3 kez "İleri".
  Future<void> goToLast(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('ilk sayfa: hoş geldin başlığı + Atla + İleri görünür, Başla yok',
      (tester) async {
    await pump(tester, () {});
    expect(find.text("Portly'ye Hoş Geldin"), findsOneWidget);
    expect(find.text('Atla'), findsOneWidget);
    expect(find.text('İleri'), findsOneWidget);
    expect(find.text('Başla'), findsNothing);
  });

  testWidgets('Atla → onDone bir kez çağrılır', (tester) async {
    var done = 0;
    await pump(tester, () => done++);
    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('İleri son sayfaya ilerletir (Başla belirir, İleri kalkar), onDone çağrılmaz',
      (tester) async {
    var done = 0;
    await pump(tester, () => done++);
    await goToLast(tester);
    expect(find.text('Haberler, AI Koç & Akademi'), findsOneWidget); // 4. sayfa içeriği
    expect(find.text('Başla'), findsOneWidget);
    expect(find.text('İleri'), findsNothing);
    expect(done, 0); // yalnız sayfa ilerledi; tur bitmedi
  });

  testWidgets('son sayfada Başla → onDone bir kez çağrılır', (tester) async {
    var done = 0;
    await pump(tester, () => done++);
    await goToLast(tester);
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
