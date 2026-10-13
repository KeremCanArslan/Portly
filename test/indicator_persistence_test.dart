import 'package:flutter_test/flutter_test.dart';
import 'package:portly/widgets/price_chart.dart';

// Indikatör seçimi SharedPreferences'a enum ADI (Indicator.name) listesi
// olarak yazılıp okunur (oturumlar arası + zaman dilimi değişiminde kalıcı).
// Bu tur, o serileştirme SÖZLEŞMESİNİ kilitler: adlar benzersiz olmalı ki
// round-trip kayıpsız olsun; ad→Indicator araması her değer için çalışmalı.
void main() {
  test('Indicator.name değerleri benzersiz (kayıpsız round-trip)', () {
    final names = Indicator.values.map((e) => e.name).toList();
    expect(names.toSet().length, names.length,
        reason: 'çakışan enum adı kalıcılığı bozar: $names');
  });

  test('kaydedilen adlar geri Indicator\'a eşlenir (yükleme yolu)', () {
    // Disk yolu: her aktif gösterge .name ile yazılır; okurken ad→enum eşlenir.
    final saved = Indicator.values.map((e) => e.name).toList();
    final restored = <Indicator>{};
    for (final s in saved) {
      for (final ind in Indicator.values) {
        if (ind.name == s) restored.add(ind);
      }
    }
    expect(restored, Indicator.values.toSet(),
        reason: 'tüm göstergeler geri yüklenmeli');
  });

  test('bilinmeyen/eski ad sessizce atlanır (enum değişse de çökme yok)', () {
    final saved = ['volume', 'rsi', 'eski_kaldirilmis_gosterge'];
    final restored = <Indicator>{};
    for (final s in saved) {
      for (final ind in Indicator.values) {
        if (ind.name == s) restored.add(ind);
      }
    }
    expect(restored, {Indicator.volume, Indicator.rsi});
  });

  // Grafik tipi (Çizgi/Mum/Heikin) de aynı şekilde ChartType.name ile kalıcı.
  test('ChartType.name round-trip (mum seçimi timeframe/oturumda kalır)', () {
    for (final t in ChartType.values) {
      ChartType? back;
      for (final cand in ChartType.values) {
        if (cand.name == t.name) back = cand;
      }
      expect(back, t);
    }
    // Bilinmeyen tip → eşleşme yok (varsayılanda kalınır, çökme yok).
    ChartType? unknown;
    for (final cand in ChartType.values) {
      if (cand.name == 'eski_tip') unknown = cand;
    }
    expect(unknown, isNull);
  });
}
