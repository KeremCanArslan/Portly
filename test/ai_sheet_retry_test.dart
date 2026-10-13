// AI analiz alt-sayfalarının hata → "Tekrar Dene" sözleşmesi (3 Eylül, 6. tur).
//
// Canlı turda "AI Piyasa Etkisi" sheet'i yaklaşık 3/10 "AI analizi şu an
// üretilemedi" veriyordu (aynı istek curl'de 8/8 başarılı — yani geçici) ve
// sheet'te tekrar deneme yolu YOKTU: kullanıcı kapatıp yeniden açmak zorundaydı.
// Hisse detayındaki AI sheet'lerinde bu kalıp zaten vardı; ortak `AiSheet`
// widget'ına taşındı ve haber sheet'i de ona bağlandı.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/widgets/ai_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('yanıt null → hata mesajı + Tekrar Dene görünür', (t) async {
    await t.pumpWidget(_wrap(AiSheet(
      fetch: ({bool force = false}) async => null,
      errorMessage: 'analiz alınamadı',
      onData: (_, __) => const Text('VERİ'),
    )));
    await t.pump();

    expect(find.text('analiz alınamadı'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    expect(find.text('VERİ'), findsNothing);
  });

  testWidgets('Tekrar Dene yeniden çeker (force: true) ve veri gelirse gösterir',
      (t) async {
    var cagri = 0;
    final forceBayraklari = <bool>[];
    await t.pumpWidget(_wrap(AiSheet(
      fetch: ({bool force = false}) async {
        cagri++;
        forceBayraklari.add(force);
        return cagri == 1 ? null : {'ok': true};
      },
      errorMessage: 'analiz alınamadı',
      onData: (_, __) => const Text('VERİ'),
    )));
    await t.pump();
    expect(find.text('Tekrar Dene'), findsOneWidget);

    await t.tap(find.text('Tekrar Dene'));
    await t.pump();
    await t.pump();

    expect(cagri, 2);
    // İlk çekim normal, retry cache'i atlamalı.
    expect(forceBayraklari, [false, true]);
    expect(find.text('VERİ'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsNothing);
  });

  testWidgets('isFailure: 200 + {"error": ...} gövdesi de hata sayılır',
      (t) async {
    await t.pumpWidget(_wrap(AiSheet(
      fetch: ({bool force = false}) async =>
          {'error': 'AI analizi şu an üretilemedi'},
      isFailure: (d) => d.containsKey('error'),
      errorMessage: 'analiz alınamadı',
      onData: (_, __) => const Text('VERİ'),
    )));
    await t.pump();

    expect(find.text('analiz alınamadı'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });

  testWidgets('isFailure verilmezse dolu gövde başarıdır (eski davranış)',
      (t) async {
    await t.pumpWidget(_wrap(AiSheet(
      fetch: ({bool force = false}) async => {'error': 'yine de göster'},
      errorMessage: 'analiz alınamadı',
      onData: (_, __) => const Text('VERİ'),
    )));
    await t.pump();

    expect(find.text('VERİ'), findsOneWidget);
  });

  testWidgets('yanıt beklenirken spinner var, hata metni yok', (t) async {
    await t.pumpWidget(_wrap(AiSheet(
      fetch: ({bool force = false}) =>
          Future.delayed(const Duration(seconds: 3), () => {'ok': true}),
      errorMessage: 'analiz alınamadı',
      onData: (_, __) => const Text('VERİ'),
    )));
    await t.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('analiz alınamadı'), findsNothing);

    await t.pump(const Duration(seconds: 4));
    expect(find.text('VERİ'), findsOneWidget);
  });
}
