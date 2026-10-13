import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/widgets/holdings_allocation_card.dart';

class _FakeProvider extends PortfolioProvider {
  final List<dynamic> _h;
  _FakeProvider(this._h);
  @override
  List<dynamic> get myHoldings => _h;
}

void main() {
  testWidgets('donut leader labels: render, two-sided, no overlap',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final holdings = [
      {'symbol': 'GC=F', 'total_value_try': 414000.0}, // Altın 51.5
      {'symbol': 'LMT', 'total_value_try': 117000.0},
      {'symbol': 'NVDA', 'total_value_try': 91000.0},
      {'symbol': 'AAPL', 'total_value_try': 68000.0},
      {'symbol': 'TSLA', 'total_value_try': 57000.0},
      {'symbol': 'CEG', 'total_value_try': 24000.0},
      {'symbol': 'TUPRS.IS', 'total_value_try': 13000.0},
      {'symbol': 'KO', 'total_value_try': 11000.0},
      {'symbol': 'ASELS.IS', 'total_value_try': 4000.0},
      {'symbol': 'HYPE32196-USD', 'total_value_try': 2400.0},
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ChangeNotifierProvider<PortfolioProvider>.value(
          value: _FakeProvider(holdings),
          child: const Scaffold(
            body: SingleChildScrollView(child: HoldingsAllocationCard()),
          ),
        ),
      ),
    );
    await tester.pump();

    // Lider etiketleri = iki span'lı (sym + pct) Text.rich. Lejantın
    // düz "%" Text'i (children yok) ve uzun konsantrasyon notu hariç.
    final richLabels = <(Rect, String)>[];
    final letter = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]');
    for (final e in find.byType(RichText).evaluate()) {
      final rt = e.widget as RichText;
      final s = rt.text.toPlainText();
      // Lider etiketi: harf VAR + "%" VAR + kısa. Lejant "%" (harf yok),
      // lejant ad (% yok), konsantrasyon notu (uzun) elenir.
      if (!s.contains('%') || s.length > 16 || !letter.hasMatch(s)) {
        continue;
      }
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.hasSize) continue;
      final pos = ro.localToGlobal(Offset.zero);
      richLabels.add((pos & ro.size, s));
    }

    // En az 8 etiket görünür (10 pozisyondan <%0.6 olanlar hariç).
    expect(richLabels.length, greaterThanOrEqualTo(8),
        reason: 'Yeterli lider etiketi render olmadı: $richLabels');

    // Hepsi tuval içinde, pozitif boyutlu.
    for (final (rect, txt) in richLabels) {
      expect(rect.width, greaterThan(0), reason: 'sıfır genişlik: $txt');
      expect(rect.left, greaterThan(-80), reason: 'taşma sol: $txt @$rect');
      expect(rect.right, lessThan(1280), reason: 'taşma sağ: $txt @$rect');
    }

    // İki yanlı: hem solda hem sağda etiket olmalı (Altın %51 sağda
    // tek başına; küçükler solda).
    const midX = 600.0;
    final left = richLabels.where((r) => r.$1.center.dx < midX).toList();
    final right = richLabels.where((r) => r.$1.center.dx >= midX).toList();
    expect(left, isNotEmpty, reason: 'sol yanda etiket yok');
    expect(right, isNotEmpty, reason: 'sağ yanda etiket yok');

    // Hiçbir iki etiket GERÇEKTEN (hem yatay hem dikey) örtüşmemeli.
    for (int i = 0; i < richLabels.length; i++) {
      for (int j = i + 1; j < richLabels.length; j++) {
        final a = richLabels[i], b = richLabels[j];
        final overlap = a.$1.inflate(-1).overlaps(b.$1.inflate(-1));
        expect(overlap, isFalse,
            reason: 'etiket çakışması: "${a.$2}" ${a.$1} ile '
                '"${b.$2}" ${b.$1}');
      }
    }
  });

  testWidgets('lider çizgileri GERÇEKTEN çiziliyor (piksel kanıtı)',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final holdings = [
      {'symbol': 'GC=F', 'total_value_try': 414000.0},
      {'symbol': 'LMT', 'total_value_try': 117000.0},
      {'symbol': 'NVDA', 'total_value_try': 91000.0},
      {'symbol': 'AAPL', 'total_value_try': 68000.0},
      {'symbol': 'TSLA', 'total_value_try': 57000.0},
      {'symbol': 'CEG', 'total_value_try': 24000.0},
      {'symbol': 'KO', 'total_value_try': 11000.0},
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ChangeNotifierProvider<PortfolioProvider>.value(
            value: _FakeProvider(holdings),
            child: const RepaintBoundary(
              child: SingleChildScrollView(child: HoldingsAllocationCard()),
            ),
          ),
        ),
      ),
    );
    // ⚠️ pumpAndSettle KULLANMA: _FakeProvider, PortfolioProvider() ctor'u
    // üzerinden _init()'te gerçek loadMarketData/loadNewsData (AĞ) tetikliyor →
    // cold-start backend + retry/timer yüzünden "settle" ~7 dk sürüp tam suite
    // zaman aşımına düşüyordu (izolede geçer, suite'te fail = flaky). Sınırlı
    // pump donut'u (giriş animasyonu dahil) çizer, ağı/timer'ı BEKLEMEZ.
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // toImage GERÇEK motor async'i gerektirir → runAsync ŞART. FakeAsync test
    // zone'unda doğrudan await edilirse Future asla tamamlanmaz → 10 dk timeout
    // (bu testin ASIL takılma sebebiydi, pumpAndSettle değil). Yalnız görüntü
    // yakalama runAsync'te; pump/expect dışarıda kalır.
    late final List<int> bytes;
    late final int iw, ih;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      final img = await boundary.toImage(pixelRatio: 1.0);
      final bd = await img.toByteData(format: ImageByteFormat.rawRgba);
      expect(bd, isNotNull);
      bytes = bd!.buffer.asUint8List();
      iw = img.width;
      ih = img.height;
      img.dispose();
    });

    // Donut'un dışı (kart kenarına yakın bant) — burada SADECE lider
    // çizgileri/noktaları ve etiket olabilir. Etiketler beyazımsı;
    // lider çizgileri canlı palet rengi. "Canlı renkli" (kanallar
    // arası fark büyük, koyu değil) piksel sayısını say.
    int vivid = 0;
    for (int y = 0; y < ih; y++) {
      for (int x = 0; x < iw; x++) {
        final i = (y * iw + x) * 4;
        final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        // koyu zemin değil + gri/beyaz metin değil (kanal farkı yüksek)
        if (mx > 90 && (mx - mn) > 55) vivid++;
      }
    }
    // Dilim arc'ları da canlı ama lider çizgileri+noktaları eklenince
    // bu eşik rahat aşılır; "hiç lider çizilmiyor" senaryosu yakalanır.
    expect(vivid, greaterThan(800),
        reason: 'Donut+lider canlı piksel sayısı çok düşük ($vivid) — '
            'lider çizgileri çizilmiyor olabilir');
  });
}
