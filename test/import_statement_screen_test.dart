// Ekstre içe aktarma ekranı — ağsız akış testi.
//
// Ekranın "doğru iş" olduğunu kanıtlar: dosya seçilmeden hiçbir şey
// kaydedilmez (giriş ekranı yükleme butonu + nasıl-alınır adımlarını gösterir,
// alt bar YOKTUR), mobilde web-only yükleme butonu gizlenir ve yerine
// açıklama çıkar. Ekran provider/ağ çağrısı yapmadan çizilebildiği için
// pumpAndSettle güvenli.
//
// Önizleme sonrası davranış (mod seçimi, satır işaretleme, aktarım) gerçek
// PDF + backend gerektirdiğinden orada değil `backend/tests/
// test_statement_import.py` içinde kilitlenir; burada UI'ın kayıtsız
// başlangıç sözleşmesi doğrulanır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/screens/import_statement_screen.dart';
import 'package:portly/theme/app_theme.dart';

void main() {
  _parseNumTests();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const ImportStatementScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('giriş ekranı Midas adımlarını gösterir', (tester) async {
    await pump(tester);

    expect(find.text('Ekstreden İçe Aktar'), findsOneWidget);
    expect(find.text('Midas ekstresi nasıl alınır'), findsOneWidget);
    expect(find.text('Profil ve Ayarlar → Belgeler → Ekstreler'),
        findsOneWidget);
  });

  testWidgets('dosya seçilmeden aktarım çubuğu görünmez', (tester) async {
    await pump(tester);

    // Alt bar yalnız parse sonrası çıkar — kullanıcı yanlışlıkla boş
    // aktarım tetikleyemez.
    expect(find.textContaining('Aktar ('), findsNothing);
    expect(find.textContaining('aktarılacak'), findsNothing);
  });

  testWidgets('önizleme öncesi mod seçici yok', (tester) async {
    await pump(tester);

    expect(find.textContaining('Portföy Özeti ('), findsNothing);
    expect(find.textContaining('İşlem Geçmişi ('), findsNothing);
  });

  testWidgets('web dışında yükleme butonu yerine açıklama çıkar',
      (tester) async {
    // Test ortamı kIsWeb=false → dart:html yok, buton gizli olmalı.
    await pump(tester);

    expect(find.text('Ekstre Yükle (PDF)'), findsNothing);
    expect(
      find.textContaining('yalnız web sürümünde'),
      findsOneWidget,
    );
  });
}

// Düzenleme alanları Türkçe biçim gösterdiği için (formatMoney "1.234,56",
// formatQty "0,802980132") geri okuyucu bu biçimi çözebilmeli; çözemezse
// kullanıcının düzelttiği maliyet sessizce eski değerine dönerdi.
void _parseNumTests() {
  group('düzenleme alanı sayı okuma', () {
    for (final c in <(String, double?)>[
      ('1.234,56', 1234.56),
      ('362,40', 362.40),
      ('0,802980132', 0.802980132),
      ('45', 45.0),
      ('4.91', 4.91), // kullanıcı nokta ile yazarsa ondalık kabul edilir
      ('', null),
      ('abc', null),
    ]) {
      test('${c.$1} → ${c.$2}', () {
        expect(parseEditedNumber(c.$1), c.$2);
      });
    }
  });
}
