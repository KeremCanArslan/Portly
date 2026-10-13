/// Tek kaynak para biçimi. Türkçe yerel: '.' binlik, ',' ondalık.
/// 137526.54 → "137.526,54".  -4086.2 → "−4.086,20".
/// Bağımsız (import yok) — app_theme.MoneyText bunu kullanır.
String formatMoney(double v, {int decimals = 2}) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(decimals);
  final dot = s.indexOf('.');
  final intPart = dot >= 0 ? s.substring(0, dot) : s;
  final decPart = dot >= 0 ? s.substring(dot + 1) : '';
  final b = StringBuffer();
  final n = intPart.length;
  for (int i = 0; i < n; i++) {
    b.write(intPart[i]);
    final rem = n - i - 1;
    if (rem > 0 && rem % 3 == 0) b.write('.');
  }
  final out = decimals > 0 ? '${b.toString()},$decPart' : b.toString();
  return neg ? '−$out' : out;
}

/// Yüzde biçimi — Türkçe ondalık (virgül). 5.17 → "5,17", -3.7 → "−3,70".
/// '%' işaretini ÇAĞIRAN ekler (yer/biçim ekrana göre değişebilir).
/// Para ile aynı ondalık ayracı kullanılır → tutarlı görünüm.
String formatPct(double v, {int decimals = 2}) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(decimals);
  final out = s.replaceAll('.', ',');
  return neg ? '−$out' : out;
}

/// Pay/lot adedi — en fazla `maxDecimals` ondalık, sondaki sıfırlar
/// atılır, Türkçe virgül. 1.2 → "1,2", 3 → "3", 0.71060 → "0,7106".
String formatQty(num q, {int maxDecimals = 4}) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  var s = q.toStringAsFixed(maxDecimals);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

/// İşaretli yüzde: kazançta '+', zararda '−'. "+1,70" / "−5,17".
String formatPctSigned(double v, {int decimals = 2}) {
  final s = formatPct(v, decimals: decimals);
  return v >= 0 ? '+$s' : s; // negatifte zaten '−' var
}
