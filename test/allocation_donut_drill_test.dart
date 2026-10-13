import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/widgets/allocation_donut.dart';

/// "Diğer" gibi toplayıcı dilimlerin İÇİNİ açan drill-down.
///
/// Tasarım sözleşmesi: `breakdowns` verilmediğinde donut'un davranışı
/// BİREBİR eskisi gibi kalmalı (Hisseler/Borsa görünümleri bunu kullanmıyor).
/// Verildiğinde ise dilime dokunmak aynı donut'ta alt kalemleri gösterir,
/// merkeze dokunmak geri döner.

const _items = [
  (label: 'Diğer', value: 450.0),
  (label: 'Altın', value: 300.0),
  (label: 'Savunma', value: 250.0),
];

final _breakdowns = <String, List<({String label, double value})>>{
  'Diğer': const [
    (label: 'SPY', value: 200.0),
    (label: 'LTL', value: 150.0),
    (label: 'MRT', value: 100.0),
  ],
};

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Donut'un çizim yüzeyi (Stack'i dolduran CustomPaint).
RenderBox _canvasOf(WidgetTester tester) => tester.renderObject<RenderBox>(
      find
          .descendant(
              of: find.byType(AllocationDonut),
              matching: find.byType(CustomPaint))
          .first,
    );

Offset _centerOf(WidgetTester tester) {
  final box = _canvasOf(tester);
  return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
}

/// `startPct`'ten başlayan `sweepPct` genişliğindeki dilimin ORTASINDA,
/// halka bandının üstüne düşen global nokta. Yarıçap AllocationDonut._layout
/// ile aynı formülden türetilir (geniş yerleşim: gutter 132, kalınlık 0.42).
Offset _sliceCenterOf(WidgetTester tester, double startPct, double sweepPct) {
  final box = _canvasOf(tester);
  final w = box.size.width;
  final h = box.size.height;
  final outerR = math.min(w / 2 - 132.0, h / 2 - 18.0);
  final safeR = outerR.isFinite && outerR > 24 ? outerR : 24.0;
  final ringR = safeR - (safeR * 0.42) / 2; // halka bandının orta yarıçapı
  final mid = (startPct + sweepPct / 2) / 100 * 2 * math.pi - math.pi / 2;
  return _centerOf(tester) +
      Offset(math.cos(mid) * ringR, math.sin(mid) * ringR);
}

void main() {
  testWidgets('breakdowns verilmezse davranış değişmez — dokunma yalnız vurgular',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        _wrap(const AllocationDonut(items: _items, centerUnit: 'sektör')));
    await tester.pump();

    expect(find.text('TOPLAM'), findsOneWidget);
    expect(find.text('3 sektör'), findsOneWidget);

    // "Diğer" dilimine dokun (0-45%): içeri GİRMEMELİ, sadece seçmeli.
    await tester.tapAt(_sliceCenterOf(tester, 0, 45));
    await tester.pump();

    expect(find.text('‹ DİĞER'), findsNothing);
    expect(find.text('SPY'), findsNothing);
  });

  testWidgets('dilime dokununca içi açılır, merkeze dokununca geri döner',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(AllocationDonut(
      items: _items,
      centerUnit: 'sektör',
      breakdowns: _breakdowns,
    )));
    await tester.pump();

    // Üst seviye: alt kalemler görünmüyor.
    expect(find.text('SPY'), findsNothing);

    await tester.tapAt(_sliceCenterOf(tester, 0, 45));
    await tester.pumpAndSettle();

    // İçerideyiz: merkez artık hangi dilimde olduğumuzu ve birimi söylüyor.
    expect(find.text('‹ DİĞER'), findsOneWidget);
    expect(find.text('3 varlık'), findsOneWidget);
    // Alt kalemler lejantta görünür (SPY hem lejant hem lider etiketi olabilir).
    expect(find.text('SPY'), findsWidgets);
    expect(find.text('LTL'), findsWidgets);
    expect(find.text('MRT'), findsWidgets);
    // Toplam artık dilimin toplamı (200+150+100), portföyün değil.
    expect(find.text('₺450'), findsOneWidget);

    // Merkeze dokun → geri.
    await tester.tapAt(_centerOf(tester));
    await tester.pumpAndSettle();

    expect(find.text('TOPLAM'), findsOneWidget);
    expect(find.text('3 sektör'), findsOneWidget);
    expect(find.text('SPY'), findsNothing);
  });

  testWidgets('alt kırılımı olmayan dilim içeri girmez', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(AllocationDonut(
      items: _items,
      centerUnit: 'sektör',
      breakdowns: _breakdowns,
    )));
    await tester.pump();

    // "Altın" dilimi (45%-75%): kırılımı yok → içeri girmemeli.
    await tester.tapAt(_sliceCenterOf(tester, 45, 30));
    await tester.pumpAndSettle();

    expect(find.text('‹ ALTIN'), findsNothing);
    expect(find.text('SPY'), findsNothing);
  });

  testWidgets('tek kalemli kırılım açılmaz (gösterecek bir şey yok)',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(AllocationDonut(
      items: _items,
      centerUnit: 'sektör',
      breakdowns: const {
        'Diğer': [(label: 'SPY', value: 450.0)],
      },
    )));
    await tester.pump();

    await tester.tapAt(_sliceCenterOf(tester, 0, 45));
    await tester.pumpAndSettle();

    expect(find.text('‹ DİĞER'), findsNothing);
  });
}
