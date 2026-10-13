// TEFAS yatırım fonu sembollerinin (TLY.FON) gösterimi.
//
// Bağlam: fonun Yahoo karşılığı yok; backend fonu ".FON" soneğiyle saklıyor.
// Sonek arayüzde ".IS" gibi ele alınmazsa fon $ ile gösteriliyor, kullanıcıya
// "TLY.FON" diye ham sembol çıkıyor ve birim pay değeri (1,096196) 2 basamağa
// yuvarlanınca maliyetle çelişik görünüyordu.

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/utils/symbol_display.dart';

void main() {
  test('fon sembolü tanınır', () {
    expect(SymbolDisplay.isFund('TLY.FON'), isTrue);
    expect(SymbolDisplay.isFund('THYAO.IS'), isFalse);
    expect(SymbolDisplay.isFund('URA'), isFalse); // aynı kod ABD ETF'i de olabilir
  });

  test('fon ₺ ile kote edilir', () {
    expect(SymbolDisplay.currencyOf('TLY.FON'), '₺');
    expect(SymbolDisplay.currencyOf('AAPL'), '\$');
  });

  test('sonek kullanıcıya gösterilmez', () {
    expect(SymbolDisplay.compact('TLY.FON'), 'TLY');
    expect(SymbolDisplay.secondaryLabel('TLY.FON'), 'TLY · Fon');
    // Portföy satırı ve sinyal kartı başlığı label() kullanıyor — o da
    // kırpmalı (canlıda "TLY.FON" görünüyordu).
    expect(SymbolDisplay.label('TLY.FON'), 'TLY');
    expect(SymbolDisplay.label('LTL.FON'), 'LTL');
  });

  test('.IS davranışı DEĞİŞMEDİ (eski ve bilinçli)', () {
    // Haritada olmayan BIST kodu sonekiyle kalır; fon düzeltmesi buraya
    // sızmamalı.
    expect(SymbolDisplay.label('KARCL.IS'), 'KARCL.IS');
    expect(SymbolDisplay.label('THYAO.IS'), 'Türk Hava Yolları');
    expect(SymbolDisplay.label('AAPL'), 'AAPL');
  });

  test('borsa dağılımında ayrı grup', () {
    expect(SymbolDisplay.exchangeOf('TLY.FON'), 'Fon');
    expect(SymbolDisplay.exchangeOf('THYAO.IS'), 'BIST');
  });

  test('birim pay değeri hassasiyeti korunur', () {
    // Fon: küçük değerde 6, orta değerde 4, büyük değerde 2 basamak.
    expect(SymbolDisplay.priceDecimals('TLY.FON', 0.048123), 6);
    expect(SymbolDisplay.priceDecimals('TLY.FON', 1.096196), 4);
    expect(SymbolDisplay.priceDecimals('TLY.FON', 9293.93), 2);
    // Hisse her zaman 2 — kuruş altı anlamı yok.
    expect(SymbolDisplay.priceDecimals('THYAO.IS', 1.096196), 2);
  });

  test('haber sorgusu fon bağlamıyla üretilir', () {
    expect(SymbolDisplay.newsQuery('TLY.FON'), 'tr|TLY yatırım fonu');
  });
}
