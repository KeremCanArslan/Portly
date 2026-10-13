import 'dart:math' as math;
import 'dart:async';
import 'package:portly/utils/money.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerScaleEvent, GestureBinding;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/utils/indicators.dart';
import 'package:portly/widgets/horizontal_wheel_scroll.dart';
import 'package:portly/services/api_service.dart';

enum ChartType { line, candle, heikinAshi }

/// Çizim/etkileşim aracı — trader'ın TradingView'da en çok kullandıkları.
enum ChartTool {
  cursor,
  measure,
  hline,
  trend,
  fib,
  rect,
  alert,
  hray, // yatay ışın (bir noktadan sağa uzanan yatay çizgi)
  vline, // dikey çizgi (bir bara/zamana sabit, tam yükseklik)
  note, // metin/not (bir noktaya bağlı etiket)
  channel, // paralel kanal (3 nokta: ana çizgi + offset)
  position, // pozisyon (Long/Short risk-ödül kutusu)
}

/// Painter → state geometri köprüsü. Painter her paint'te doldurur;
/// jest işleyiciler ekran (x,y) ↔ (bar index, fiyat) dönüşümü için okur.
/// Tutamaç hit-test'i ve hassas çizim/düzenleme bunu kullanır.
class _ChartGeo {
  double left = 0, right = 0, top = 0, h = 1;
  double minY = 0, maxY = 1;
  bool log = false;
  ChartType type = ChartType.line;
  int visStart = 0, visEnd = 1;

  double _sc(double v) => log ? math.log(math.max(v, 1e-9)) : v;
  double _unsc(double s) => log ? math.exp(s) : s;

  bool get ready => right > left && h > 0 && visEnd > visStart;
  int get _n => visEnd - visStart;

  double priceAt(double y) {
    final a = _sc(minY), b = _sc(maxY);
    final t = 1 - (y - top) / h;
    return _unsc(a + t * (b - a));
  }

  double yOf(double price) {
    final a = _sc(minY), b = _sc(maxY);
    final t = (b - a) == 0 ? 0.0 : (_sc(price) - a) / (b - a);
    return top + h * (1 - t);
  }

  double xOf(int absIdx) {
    final i = absIdx - visStart;
    final w = right - left;
    return type == ChartType.line
        ? left + w * (i / math.max(1, _n - 1))
        : left + (w / _n) * (i + 0.5);
  }

  int idxAt(double x) {
    final w = right - left;
    final r = ((x - left) / w).clamp(0.0, 1.0);
    final local = (r * (_n - 1)).round().clamp(0, _n - 1);
    return visStart + local;
  }
}

/// Düzenlenmekte olan çizim tutamacı.
class _Edit {
  final ChartTool kind;
  final int index; // listedeki konum (hline/trend/fib/rect)
  final int end; // 0=A 1=B (measure'da 0=A 1=B)
  _Edit(this.kind, this.index, this.end);
}

class NewsMarker {
  final int index; // veri noktası indeksi
  final double sentimentScore;
  const NewsMarker(this.index, this.sentimentScore);
}

class PriceLine {
  final double price;
  final Color color;
  final String label; // örn. "SL", "TP"
  const PriceLine({
    required this.price,
    required this.color,
    required this.label,
  });
}

/// Aktif edilebilen teknik göstergeler. Renkler data-viz → ayırt edici palet.
enum Indicator {
  ma20('MA 20', _kAmber, false),
  ma50('MA 50', _kBlue, false),
  ma200('MA 200', _kRed, false),
  ema20('EMA 20', _kPurple, false),
  boll('Bollinger (20,2)', _kCyan, false),
  vwap('VWAP', _kGold, false),
  rsi('RSI (14)', _kBlue, true),
  macd('MACD (12,26,9)', _kPurple, true),
  volume('Hacim', _kNeutral, true);

  final String label;
  final int colorValue;
  final bool isPanel; // true → alt panel, false → fiyat üzeri overlay
  const Indicator(this.label, this.colorValue, this.isPanel);
  Color get color => Color(colorValue);
}

const int _kAmber = 0xFFFFB74D;
const int _kBlue = 0xFF42A5F5;
const int _kRed = 0xFFE57373;
const int _kPurple = 0xFFBA68C8;
const int _kCyan = 0xFF4DD0E1;
const int _kGold = 0xFFFFD54F;
const int _kNeutral = 0xFF90A4AE;
const int _kSignal = 0xFFFF7043;
const Color _kGreen = Color(0xFF26A69A);
const Color _kRedC = Color(0xFFEF5350);

class PriceChart extends StatefulWidget {
  final List<Map<String, dynamic>>
      data; // {date, open, high, low, close, volume}
  final String currency;
  final List<NewsMarker> newsMarkers;
  final List<PriceLine> priceLines;
  final double height;
  // Verilirse "Alarm" aracı görünür: kullanıcı bir fiyata dokununca çağrılır.
  final void Function(double price)? onCreateAlert;
  // Pro (tam ekran) modda ekstra dikey alan + araçlar daha rahat.
  final bool pro;
  // Grafiğin köşesinde gösterilecek sembol/zaman dilimi etiketi (kullanıcı
  // "hangi zaman dilimine bakıyorum bilmiyorum" dedi).
  final String? symbolLabel;
  final String? timeframeLabel;
  // Verilirse çizimler bu sembol anahtarıyla kullanıcı hesabına KAYDEDİLİR/
  // YÜKLENİR (stock_detail/pro_chart). null → kalıcılık kapalı (örn. quiz).
  final String? symbol;

  const PriceChart({
    super.key,
    required this.data,
    required this.currency,
    this.newsMarkers = const [],
    this.priceLines = const [],
    this.height = 320,
    this.onCreateAlert,
    this.pro = false,
    this.symbolLabel,
    this.timeframeLabel,
    this.symbol,
  });

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  // Grafik tipi (Çizgi/Mum/Heikin). KALICI — indikatörlerle aynı gerekçe:
  // timeframe değişince State yok olup eskiden Çizgi'ye sıfırlanıyordu
  // (kullanıcı "muma aldıysam mum kalsın" dedi). Statik = anlık, prefs = oturum.
  static ChartType? _sessionType;
  static const String _chartTypePrefsKey = 'chart_type_v1';
  ChartType _type = ChartType.line;
  // Full-seri indikatör memo'su — yalnız data değişince yenilenir.
  late _SeriesCache _series;
  // Aktif göstergeler. KALICI: kullanıcının seçimi (a) zaman dilimi değişiminde
  // ve (b) oturumlar arasında korunur. Zaman dilimi değişince pro_chart_screen
  // PriceChart'ı spinner'la değiştirip State'i yok ediyor → eskiden seçim
  // sıfırlanıyordu. _sessionActive (statik) = aynı oturumda ANINDA geri yükle
  // (async flash yok); SharedPreferences = oturumlar arası. Boş set = kullanıcı
  // hepsini kapattı (varsayılana DÖNME).
  static Set<Indicator>? _sessionActive;
  static const String _indicatorPrefsKey = 'chart_indicators_v1';
  final Set<Indicator> _active = {};
  int? _hoverIndex;
  // Görünür aralık — zoom için
  int? _visibleStart;
  int? _visibleEnd;
  Offset? _hoverPos;
  int _scaleStartCount = 0;
  // Dikey fiyat-ekseni zoom'u (1 = otomatik sığdır; >1 mumlar büyür).
  double _priceScale = 1.0;
  double _priceOffset = 0.0; // skala-uzayı dikey pan
  bool _axisDrag =
      false; // sağ fiyat ekseni şeridinde dikey sürükleme (fiyat zoom)
  bool _timeAxisDrag =
      false; // alt zaman ekseni şeridinde yatay sürükleme (zaman zoom)

  // Mıknatıs (snap). Açıkken crosshair + çizim noktaları en yakın muma
  // (O/H/L/C) yapışır; kapalıyken serbest. Kullanıcı isteği: TradingView gibi
  // aç/kapa. KALICI (statik + prefs).
  static bool? _sessionSnap;
  static const String _snapPrefsKey = 'chart_snap_v1';
  bool _snap = false; // varsayılan serbest (kullanıcı zorla snap istemiyor)

  // Mum + arka plan renk özelleştirmesi. int ARGB; null = tema varsayılanı.
  // Statik = oturum içi anlık; prefs = oturumlar arası. Kerem 'acil' dedi.
  static int? _sessionUp, _sessionDown, _sessionBg;
  static const String _colorUpKey = 'chart_color_up_v1';
  static const String _colorDownKey = 'chart_color_down_v1';
  static const String _colorBgKey = 'chart_color_bg_v1';
  int? _upColor, _downColor, _bgColor;

  // Painter geometrisi (hit-test / hassas çizim için)
  final _ChartGeo _geo = _ChartGeo();
  _Edit? _edit; // sürüklenen tutamaç
  // Pan (zaman kaydırma) durumu
  bool _panning = false;
  Offset? _panStart;
  int _panBaseStart = 0, _panBaseEnd = 0;
  double _panBaseOffset = 0.0;
  static const double _hitR = 20.0; // tutamaç yakalama yarıçapı (px)

  @override
  void initState() {
    super.initState();
    _series = _SeriesCache.from(widget.data);
    // Indikatör seçimi + grafik tipini geri yükle. Statik bellek varsa (aynı
    // oturumda timeframe değişimi) ANINDA kullan; yoksa varsayılanla başla ve
    // diskten (önceki oturum) async yükle.
    if (_sessionActive != null) {
      _active.addAll(_sessionActive!);
    } else {
      _active.add(Indicator.volume); // ilk açılış varsayılanı
    }
    if (_sessionType != null) {
      _type = _sessionType!;
    }
    if (_sessionSnap != null) {
      _snap = _sessionSnap!;
    }
    _upColor = _sessionUp;
    _downColor = _sessionDown;
    _bgColor = _sessionBg;
    if (_sessionActive == null ||
        _sessionType == null ||
        _sessionSnap == null) {
      _loadChartPrefs(); // ilk açılış → diskten oku
    }
    _maybeLoadDrawings(); // hesaba kayıtlı çizimleri yükle (varsa, async)
  }

  @override
  void dispose() {
    // Bekleyen kayıt varsa (debounce dolmadan ekran kapandı) hemen gönder.
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      _flushSave();
    }
    _saveDebounce?.cancel();
    super.dispose();
  }

  // Diskteki indikatör seçimi + grafik tipini yükle (önceki oturum). Bulursa
  // ilgili state'i değiştirir + statik belleği doldurur. enum adı eşlenir;
  // bilinmeyen ad atlanır (enum değişse de çökmesin).
  Future<void> _loadChartPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      Set<Indicator>? restored;
      final saved = p.getStringList(_indicatorPrefsKey);
      if (saved != null) {
        restored = <Indicator>{};
        for (final s in saved) {
          for (final ind in Indicator.values) {
            if (ind.name == s) restored.add(ind);
          }
        }
        _sessionActive = restored;
      }
      ChartType? type;
      final savedType = p.getString(_chartTypePrefsKey);
      if (savedType != null) {
        for (final t in ChartType.values) {
          if (t.name == savedType) type = t;
        }
        if (type != null) _sessionType = type;
      }
      final savedSnap = p.getBool(_snapPrefsKey);
      if (savedSnap != null) _sessionSnap = savedSnap;
      // Renkler (yoksa null = tema varsayılanı kalır).
      final up = p.getInt(_colorUpKey);
      final down = p.getInt(_colorDownKey);
      final bg = p.getInt(_colorBgKey);
      _sessionUp = up;
      _sessionDown = down;
      _sessionBg = bg;
      // Statikleri çöz: disk boşsa mevcut varsayılanı işaretle ki sonraki
      // timeframe değişimleri diski TEKRAR okumasın (tek-sefer yükleme).
      _sessionActive ??= Set.of(_active);
      _sessionType ??= _type;
      _sessionSnap ??= _snap;
      if (!mounted) return;
      setState(() {
        if (restored != null) {
          _active
            ..clear()
            ..addAll(restored);
        }
        if (type != null) _type = type;
        if (savedSnap != null) _snap = savedSnap;
        _upColor = up;
        _downColor = down;
        _bgColor = bg;
      });
    } catch (_) {/* cache okunamadı — varsayılanda kal */}
  }

  // Indikatör seçimini hem statik belleğe (anlık) hem diske (kalıcı) yaz.
  void _persistIndicators() {
    _sessionActive = Set.of(_active);
    final names = _active.map((e) => e.name).toList();
    SharedPreferences.getInstance()
        .then((p) => p.setStringList(_indicatorPrefsKey, names))
        .catchError((_) => false);
  }

  // Grafik tipini hem statik belleğe hem diske yaz.
  void _persistChartType() {
    _sessionType = _type;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_chartTypePrefsKey, _type.name))
        .catchError((_) => false);
  }

  // Mıknatıs durumunu kalıcı yaz.
  void _persistSnap() {
    _sessionSnap = _snap;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_snapPrefsKey, _snap))
        .catchError((_) => false);
  }

  // Renkleri kalıcı yaz (null → ilgili anahtarı sil = tema varsayılanı).
  void _persistColors() {
    _sessionUp = _upColor;
    _sessionDown = _downColor;
    _sessionBg = _bgColor;
    SharedPreferences.getInstance().then((p) {
      _upColor == null
          ? p.remove(_colorUpKey)
          : p.setInt(_colorUpKey, _upColor!);
      _downColor == null
          ? p.remove(_colorDownKey)
          : p.setInt(_colorDownKey, _downColor!);
      _bgColor == null
          ? p.remove(_colorBgKey)
          : p.setInt(_colorBgKey, _bgColor!);
    }).catchError((_) {});
  }

  @override
  void didUpdateWidget(PriceChart old) {
    super.didUpdateWidget(old);
    // Yalnız veri seti değişince yeniden hesapla (zaman dilimi değişimi vb.).
    // Zoom/pan/hover aynı `data` referansını korur → memo yeniden kullanılır.
    if (!identical(old.data, widget.data) ||
        old.data.length != widget.data.length) {
      _series = _SeriesCache.from(widget.data);
      // Gerçek zaman dilimi değişimi mi, yoksa 30sn'lik SESSİZ yenileme mi?
      // (timeframeLabel tf değişince değişir; yenilemede aynı kalır.) Ayrım
      // kritik: tf değişiminde index-bazlı pencereyi sıfırlamalıyız (eski
      // index'ler yeni veride taşar), ama yenilemede pencereyi KORUMALIYIZ
      // (kullanıcının zoom'u 30sn'de bir kaçmasın).
      final tfChanged = old.timeframeLabel != widget.timeframeLabel;
      _remapDrawings(old.data); // çizimleri timestamp ile yeni timeframe'e taşı
      _remapReplay(old.data); // backtest playhead'ini de taşı (tf değişimi
      // modu KAPATMASIN — kullanıcı şikâyeti)
      if (tfChanged) {
        // Görünür pencereyi yeni tf'in varsayılanına bırak (getter'lar null'da
        // _effLen'e göre hesaplar → yeni veride güvenli, mantıklı çerçeve).
        _visibleStart = null;
        _visibleEnd = null;
      }
    }
    _maybeLoadDrawings(); // veri hazır olunca yükle (cold-start retry dahil)
  }

  // Çizimler bar-INDEX'e bağlı → timeframe değişince eski index yanlış bara
  // denk gelip çizim KAYIYORDU. Çözüm: eski barın timestamp'ini al, yeni
  // veride aynı zamana en yakın barın index'ine yeniden eşle. Böylece
  // trend/fib/rect/ölçüm her timeframe'de doğru zaman+fiyat noktasında kalır
  // (hLines zaten fiyat-bazlı, dokunulmaz). Tuple şekli değişmez → painter/
  // hit-test/edit katmanları aynı kalır. Yalnız veri değişiminde, çizim başına
  // O(n) çalışır (pan/zoom/hover'da DEĞİL) → FPS'e etkisi yok.
  void _remapDrawings(List<Map<String, dynamic>> oldData) {
    if (oldData.isEmpty || widget.data.isEmpty) return;
    if (!_hasDrawings && _pendStart == null && _pendChannel == null) return;
    int map(int oldIdx) {
      if (oldIdx < 0 || oldIdx >= oldData.length) {
        return oldIdx.clamp(0, widget.data.length - 1);
      }
      final ts = (oldData[oldIdx]['timestamp'] as num?)?.toInt();
      if (ts == null) return oldIdx.clamp(0, widget.data.length - 1);
      int best = 0, bestDiff = -1;
      for (int i = 0; i < widget.data.length; i++) {
        final t = (widget.data[i]['timestamp'] as num?)?.toInt();
        if (t == null) continue;
        final d = (t - ts).abs();
        if (bestDiff < 0 || d < bestDiff) {
          bestDiff = d;
          best = i;
          if (d == 0) break;
        }
      }
      return best;
    }

    for (int i = 0; i < _trends.length; i++) {
      final t = _trends[i];
      _trends[i] = (map(t.$1), t.$2, map(t.$3), t.$4);
    }
    for (int i = 0; i < _fibs.length; i++) {
      final f = _fibs[i];
      _fibs[i] = (map(f.$1), f.$2, map(f.$3), f.$4);
    }
    for (int i = 0; i < _rects.length; i++) {
      final r = _rects[i];
      _rects[i] = (map(r.$1), r.$2, map(r.$3), r.$4);
    }
    for (int i = 0; i < _hrays.length; i++) {
      final r = _hrays[i];
      _hrays[i] = (map(r.$1), r.$2);
    }
    for (int i = 0; i < _vlines.length; i++) {
      _vlines[i] = map(_vlines[i]);
    }
    for (int i = 0; i < _notes.length; i++) {
      final nt = _notes[i];
      _notes[i] = (map(nt.$1), nt.$2, nt.$3);
    }
    for (int i = 0; i < _channels.length; i++) {
      final ch = _channels[i];
      _channels[i] = (map(ch.$1), ch.$2, map(ch.$3), ch.$4, ch.$5);
    }
    if (_pendChannel != null) {
      final ch = _pendChannel!;
      _pendChannel = (map(ch.$1), ch.$2, map(ch.$3), ch.$4);
    }
    for (int i = 0; i < _positions.length; i++) {
      final ps = _positions[i];
      _positions[i] = (map(ps.$1), ps.$2, map(ps.$3), ps.$4, ps.$5);
    }
    if (_measA != null) _measA = (map(_measA!.$1), _measA!.$2);
    if (_measB != null) _measB = (map(_measB!.$1), _measB!.$2);
    if (_pendStart != null) _pendStart = (map(_pendStart!.$1), _pendStart!.$2);
  }

  // Replay (backtest) playhead'i de bar-INDEX'e bağlı. Önceden timeframe
  // değişimi replay'i KAPATIYORDU (ekran chart'ı spinner'la unmount edip
  // State'i yok ediyordu). Artık chart mounted kalıyor → playhead'in
  // timestamp'ini yeni veride en yakın bara eşle: backtest aynı ZAMAN
  // noktasında devam eder, tf değiştirmek modu kapatmaz. Yeni veri daha
  // kısaysa [8, n] aralığına clamp'lenir.
  void _remapReplay(List<Map<String, dynamic>> oldData) {
    final len = _replayLen;
    if (len == null) return; // replay kapalı — dokunma
    final n = widget.data.length;
    if (n < 8) {
      _replayLen = null; // yeni veri çok kısa → replay'i güvenle kapat
      return;
    }
    if (oldData.isEmpty) {
      _replayLen = len.clamp(8, n);
      return;
    }
    final oldIdx = (len - 1).clamp(0, oldData.length - 1); // görünen son bar
    final ts = (oldData[oldIdx]['timestamp'] as num?)?.toInt();
    if (ts == null) {
      _replayLen = len.clamp(8, n);
      return;
    }
    int best = 0, bestDiff = -1;
    for (int i = 0; i < n; i++) {
      final t = (widget.data[i]['timestamp'] as num?)?.toInt();
      if (t == null) continue;
      final d = (t - ts).abs();
      if (bestDiff < 0 || d < bestDiff) {
        bestDiff = d;
        best = i;
        if (d == 0) break;
      }
    }
    _replayLen = (best + 1).clamp(8, n);
  }

  void _priceZoomBy(double dy) {
    setState(() {
      // Yukarı sürükle (dy<0) → yakınlaş (mumlar büyür).
      _priceScale = (_priceScale * (1 - dy * 0.004)).clamp(0.30, 12.0);
    });
  }

  // Alt zaman ekseni şeridinde YATAY sürükleme → zaman ölçeğini sıkıştır/genişlet
  // (TradingView). Sağ fiyat ekseninin dikey zoom'unun aynası; sağ kenarı (en
  // güncel mum) SABİT tutar. _priceZoomBy ile aynı 0.004 hassasiyeti → tutarlı
  // his. Sağa sürükle (dx>0) → yakınlaş (az bar); sola → uzaklaş (çok bar).
  void _timeZoomByDrag(double dx) {
    final n = _effLen;
    if (n < 8) return;
    final start = _start, end = _end;
    final count = end - start;
    final newCount = (count * (1 - dx * 0.004)).round().clamp(8, n);
    if (newCount == count) return;
    var newEnd = end;
    var newStart = newEnd - newCount;
    if (newStart < 0) {
      newStart = 0;
      newEnd = newCount;
    }
    if (newEnd > n) {
      newEnd = n;
      newStart = n - newCount;
    }
    setState(() {
      _visibleStart = newStart;
      _visibleEnd = newEnd;
    });
  }

  // ── Çizim araçları (bar close'una snap'li, fiyat sabitli) ──
  ChartTool _tool = ChartTool.cursor;
  bool _logScale = false;
  final List<double> _hLines = []; // yatay destek/direnç fiyatları
  final List<(int, double, int, double)> _trends = []; // idxA,pA,idxB,pB
  final List<(int, double, int, double)> _fibs = [];
  final List<(int, double, int, double)> _rects = [];
  final List<(int, double)> _hrays = []; // yatay ışın: (başlangıç idx, fiyat)
  final List<int> _vlines = []; // dikey çizgi: bar index
  final List<(int, double, String)> _notes =
      []; // metin/not: (idx, fiyat, metin)
  // paralel kanal: (idxA, pA, idxB, pB, offset) — offset = paralel çizgiye dik
  // (fiyat) mesafe.
  final List<(int, double, int, double, double)> _channels = [];
  (
    int,
    double,
    int,
    double
  )? _pendChannel; // kanal: ana çizgi (A,B), offset bekliyor
  // pozisyon (Long/Short R:R): (idxA, giriş, idxB, hedef, stop)
  final List<(int, double, int, double, double)> _positions = [];

  // ── Çizim kalıcılığı (hesaba kaydet) ──
  // widget.symbol verilmişse çizimler kullanıcı hesabına backend'e yazılır/
  // okunur. payload TIMESTAMP-bazlı saklanır (bar-index DEĞİL — index veri
  // penceresine bağlı, kayar); yüklerken _indexForTs ile en-yakın bara eşlenir.
  bool _drawingsLoaded = false; // bu sembol için (başarıyla) yüklendi mi
  bool _drawingsLoading = false; // eşzamanlı GET koruması
  bool _editDirty = false; // pan ile çizim düzenlendi → onScaleEnd'de kaydet
  Timer? _saveDebounce; // ardışık mutasyonları tek PUT'a topla
  (int, double)? _pendStart; // 2-noktalı araçlar için ilk nokta
  (int, double)? _measA;
  (int, double)? _measB;

  // ── Bar replay (backtest) — _replayLen kadar bar görünür ──
  int? _replayLen;
  bool get _replay => _replayLen != null;
  int get _effLen => _replayLen ?? widget.data.length;

  bool get _hasDrawings =>
      _hLines.isNotEmpty ||
      _trends.isNotEmpty ||
      _fibs.isNotEmpty ||
      _rects.isNotEmpty ||
      _hrays.isNotEmpty ||
      _vlines.isNotEmpty ||
      _notes.isNotEmpty ||
      _channels.isNotEmpty ||
      _positions.isNotEmpty ||
      _measA != null;

  /// 2-noktalı araç ortada mı (ipucu için).
  bool get _awaitingSecond =>
      _pendStart != null || (_measA != null && _measB == null);

  void _clearDrawings() {
    setState(() {
      _hLines.clear();
      _trends.clear();
      _fibs.clear();
      _rects.clear();
      _hrays.clear();
      _vlines.clear();
      _notes.clear();
      _channels.clear();
      _positions.clear();
      _pendChannel = null;
      _pendStart = null;
      _measA = null;
      _measB = null;
    });
    _scheduleSave();
  }

  // ════════════ Çizim kalıcılığı: yükle / serialize / kaydet ════════════

  // Bir bar index'inin timestamp'i (kaydet: index→zaman). Sınır dışı → clamp.
  int? _tsAt(int idx) {
    final d = widget.data;
    if (d.isEmpty) return null;
    final i = idx.clamp(0, d.length - 1);
    return (d[i]['timestamp'] as num?)?.toInt();
  }

  // Bir timestamp'e en yakın bar index'i (yükle: zaman→index). _remapDrawings
  // ile aynı en-yakın eşleme.
  int _indexForTs(int ts) {
    final d = widget.data;
    int best = 0, bestDiff = -1;
    for (int i = 0; i < d.length; i++) {
      final t = (d[i]['timestamp'] as num?)?.toInt();
      if (t == null) continue;
      final diff = (t - ts).abs();
      if (bestDiff < 0 || diff < bestDiff) {
        bestDiff = diff;
        best = i;
        if (diff == 0) break;
      }
    }
    return best;
  }

  // Backend'den bu sembolün çizimlerini bir kez yükle (async, render'ı bloklamaz).
  // Başarısızsa (cold-start) _drawingsLoaded false kalır → sonraki veri
  // güncellemesinde (didUpdateWidget) tekrar denenir. Yükleme bitmeden kaydetme
  // KAPALI (_scheduleSave guard'ı) → boş seti yazıp kayıtlıları silmeyiz.
  Future<void> _maybeLoadDrawings() async {
    final sym = widget.symbol;
    if (_drawingsLoaded ||
        _drawingsLoading ||
        sym == null ||
        sym.isEmpty ||
        widget.data.isEmpty) {
      return;
    }
    _drawingsLoading = true;
    Map<String, dynamic>? payload;
    try {
      payload = await ApiService().getChartDrawings(sym);
    } catch (_) {/* sessiz */}
    _drawingsLoading = false;
    if (payload == null) return; // hata → retry'a açık
    _drawingsLoaded = true; // başarı (boş olsa bile) → tek sefer + kaydetmeyi aç
    if (!mounted || payload.isEmpty) return;
    // Kullanıcı yükleme bitmeden çizdiyse (cold-start yarışı) onun işini EZME.
    if (_hasDrawings) return;
    final loaded = payload; // closure için non-null sabit
    setState(() => _deserializeInto(loaded));
  }

  // payload (timestamp-bazlı) → çizim listelerine doldur. Bozuk/eksik alanlar
  // atlanır (şema değişse de çökmez). Yalnız yüklemede bir kez koşar.
  void _deserializeInto(Map<String, dynamic> p) {
    num? asNum(dynamic x) => x is num ? x : null;
    final hl = p['hlines'];
    if (hl is List) {
      for (final v in hl) {
        final d = asNum(v);
        if (d != null) _hLines.add(d.toDouble());
      }
    }
    void readTwo(String key, List<(int, double, int, double)> into) {
      final xs = p[key];
      if (xs is! List) return;
      for (final e in xs) {
        if (e is! Map) continue;
        final ta = asNum(e['ta']),
            pa = asNum(e['pa']),
            tb = asNum(e['tb']),
            pb = asNum(e['pb']);
        if (ta == null || pa == null || tb == null || pb == null) continue;
        into.add((_indexForTs(ta.toInt()), pa.toDouble(),
            _indexForTs(tb.toInt()), pb.toDouble()));
      }
    }

    readTwo('trends', _trends);
    readTwo('fibs', _fibs);
    readTwo('rects', _rects);
    final hr = p['hrays'];
    if (hr is List) {
      for (final e in hr) {
        if (e is! Map) continue;
        final t = asNum(e['t']), pp = asNum(e['p']);
        if (t != null && pp != null) {
          _hrays.add((_indexForTs(t.toInt()), pp.toDouble()));
        }
      }
    }
    final vl = p['vlines'];
    if (vl is List) {
      for (final v in vl) {
        final t = asNum(v);
        if (t != null) _vlines.add(_indexForTs(t.toInt()));
      }
    }
    final nt = p['notes'];
    if (nt is List) {
      for (final e in nt) {
        if (e is! Map) continue;
        final t = asNum(e['t']), pp = asNum(e['p']);
        final tx = e['text'];
        if (t != null && pp != null && tx is String) {
          _notes.add((_indexForTs(t.toInt()), pp.toDouble(), tx));
        }
      }
    }
    final ch = p['channels'];
    if (ch is List) {
      for (final e in ch) {
        if (e is! Map) continue;
        final ta = asNum(e['ta']),
            pa = asNum(e['pa']),
            tb = asNum(e['tb']),
            pb = asNum(e['pb']),
            off = asNum(e['off']);
        if (ta != null &&
            pa != null &&
            tb != null &&
            pb != null &&
            off != null) {
          _channels.add((_indexForTs(ta.toInt()), pa.toDouble(),
              _indexForTs(tb.toInt()), pb.toDouble(), off.toDouble()));
        }
      }
    }
    final ps = p['positions'];
    if (ps is List) {
      for (final e in ps) {
        if (e is! Map) continue;
        final ta = asNum(e['ta']),
            en = asNum(e['entry']),
            tb = asNum(e['tb']),
            tg = asNum(e['target']),
            st = asNum(e['stop']);
        if (ta != null &&
            en != null &&
            tb != null &&
            tg != null &&
            st != null) {
          _positions.add((_indexForTs(ta.toInt()), en.toDouble(),
              _indexForTs(tb.toInt()), tg.toDouble(), st.toDouble()));
        }
      }
    }
  }

  // Çizim listelerini timestamp-bazlı payload'a çevir (kaydet). Timestamp'i
  // bulunamayan (geçersiz index) çizimler atlanır. Measure (ölçüm) transient →
  // dahil edilmez.
  Map<String, dynamic> _serializeDrawings() {
    List<Map<String, dynamic>> twoPt(List<(int, double, int, double)> xs) {
      final out = <Map<String, dynamic>>[];
      for (final t in xs) {
        final ta = _tsAt(t.$1), tb = _tsAt(t.$3);
        if (ta == null || tb == null) continue;
        out.add({'ta': ta, 'pa': t.$2, 'tb': tb, 'pb': t.$4});
      }
      return out;
    }

    final hrays = <Map<String, dynamic>>[];
    for (final r in _hrays) {
      final t = _tsAt(r.$1);
      if (t != null) hrays.add({'t': t, 'p': r.$2});
    }
    final vlines = <int>[];
    for (final v in _vlines) {
      final t = _tsAt(v);
      if (t != null) vlines.add(t);
    }
    final notes = <Map<String, dynamic>>[];
    for (final nt in _notes) {
      final t = _tsAt(nt.$1);
      if (t != null) notes.add({'t': t, 'p': nt.$2, 'text': nt.$3});
    }
    final channels = <Map<String, dynamic>>[];
    for (final ch in _channels) {
      final ta = _tsAt(ch.$1), tb = _tsAt(ch.$3);
      if (ta == null || tb == null) continue;
      channels
          .add({'ta': ta, 'pa': ch.$2, 'tb': tb, 'pb': ch.$4, 'off': ch.$5});
    }
    final positions = <Map<String, dynamic>>[];
    for (final ps in _positions) {
      final ta = _tsAt(ps.$1), tb = _tsAt(ps.$3);
      if (ta == null || tb == null) continue;
      positions.add(
          {'ta': ta, 'entry': ps.$2, 'tb': tb, 'target': ps.$4, 'stop': ps.$5});
    }
    return {
      'v': 1,
      'hlines': List<double>.from(_hLines),
      'trends': twoPt(_trends),
      'fibs': twoPt(_fibs),
      'rects': twoPt(_rects),
      'hrays': hrays,
      'vlines': vlines,
      'notes': notes,
      'channels': channels,
      'positions': positions,
    };
  }

  // Mutasyon sonrası çağrılır: ardışık değişiklikleri ~800ms'de tek PUT'a topla.
  // symbol yoksa (quiz) veya yükleme henüz bitmediyse no-op (kayıtlıları ezme).
  void _scheduleSave() {
    if (widget.symbol == null || !_drawingsLoaded) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _flushSave);
  }

  void _flushSave() {
    final sym = widget.symbol;
    if (sym == null) return;
    ApiService().saveChartDrawings(sym, _serializeDrawings()); // fire-and-forget
  }

  /// Mıknatıs açıkken bir fiyatı o barın en yakın O/H/L/C değerine yapıştırır.
  double _snapPriceToOHLC(int idx, double raw) {
    if (idx < 0 || idx >= widget.data.length) return raw;
    final d = widget.data[idx];
    double? best;
    double bestDist = double.infinity;
    for (final k in const ['open', 'high', 'low', 'close']) {
      final v = (d[k] as num?)?.toDouble();
      if (v == null) continue;
      final dist = (v - raw).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = v;
      }
    }
    return best ?? raw;
  }

  /// Tap → bar index (x'e snap) + fiyat. Mıknatıs açıksa en yakın muma (O/H/L/C)
  /// yapışır; kapalıysa imlecin tam y'sindeki serbest fiyat. geo yoksa kapanış.
  (int, double)? _pointAt(Offset pos, double width) {
    final n = _effLen;
    if (n == 0) return null;
    if (_geo.ready) {
      final idx = _geo.idxAt(pos.dx).clamp(0, n - 1);
      var price = _geo.priceAt(pos.dy.clamp(_geo.top, _geo.top + _geo.h));
      if (_snap) price = _snapPriceToOHLC(idx, price);
      return (idx, price);
    }
    const leftPad = 50.0;
    const rightPad = 56.0;
    final chartW = width - leftPad - rightPad;
    if (chartW <= 0) return null;
    final ratio = ((pos.dx - leftPad) / chartW).clamp(0.0, 1.0);
    final vis = _visibleCount;
    final local = (ratio * (vis - 1)).round().clamp(0, vis - 1);
    final idx = (_start + local).clamp(0, n - 1);
    final price = (widget.data[idx]['close'] as num?)?.toDouble() ?? 0;
    return (idx, price);
  }

  /// Tutamaç hit-test — dokunulan noktaya yakın çizim ucu var mı?
  _Edit? _hitTest(Offset pos) {
    if (!_geo.ready) return null;
    bool near(double x, double y) => (Offset(x, y) - pos).distance <= _hitR;
    // Uç tutamaçları (trend/fib/rect/measure)
    for (int i = 0; i < _trends.length; i++) {
      final t = _trends[i];
      if (near(_geo.xOf(t.$1), _geo.yOf(t.$2))) {
        return _Edit(ChartTool.trend, i, 0);
      }
      if (near(_geo.xOf(t.$3), _geo.yOf(t.$4))) {
        return _Edit(ChartTool.trend, i, 1);
      }
    }
    for (int i = 0; i < _fibs.length; i++) {
      final f = _fibs[i];
      if (near(_geo.xOf(f.$1), _geo.yOf(f.$2))) {
        return _Edit(ChartTool.fib, i, 0);
      }
      if (near(_geo.xOf(f.$3), _geo.yOf(f.$4))) {
        return _Edit(ChartTool.fib, i, 1);
      }
    }
    for (int i = 0; i < _rects.length; i++) {
      final r = _rects[i];
      if (near(_geo.xOf(r.$1), _geo.yOf(r.$2))) {
        return _Edit(ChartTool.rect, i, 0);
      }
      if (near(_geo.xOf(r.$3), _geo.yOf(r.$4))) {
        return _Edit(ChartTool.rect, i, 1);
      }
    }
    if (_measA != null && near(_geo.xOf(_measA!.$1), _geo.yOf(_measA!.$2))) {
      return _Edit(ChartTool.measure, 0, 0);
    }
    if (_measB != null && near(_geo.xOf(_measB!.$1), _geo.yOf(_measB!.$2))) {
      return _Edit(ChartTool.measure, 0, 1);
    }
    // Yatay çizgi — çizginin y'sine yakınsa (her x)
    for (int i = 0; i < _hLines.length; i++) {
      if ((_geo.yOf(_hLines[i]) - pos.dy).abs() <= 12) {
        return _Edit(ChartTool.hline, i, 0);
      }
    }
    // Yatay ışın — başlangıç tutamacı veya gövde (yalnız x ≥ başlangıç)
    for (int i = 0; i < _hrays.length; i++) {
      final r = _hrays[i];
      final sx = _geo.xOf(r.$1);
      final y = _geo.yOf(r.$2);
      if (near(sx, y)) return _Edit(ChartTool.hray, i, 0);
      if (pos.dx >= sx - 4 && (y - pos.dy).abs() <= 10) {
        return _Edit(ChartTool.hray, i, 0);
      }
    }
    // Dikey çizgi — x'e yakınsa (her y)
    for (int i = 0; i < _vlines.length; i++) {
      if ((_geo.xOf(_vlines[i]) - pos.dx).abs() <= 8) {
        return _Edit(ChartTool.vline, i, 0);
      }
    }
    // Not — anchor noktasına yakınsa
    for (int i = 0; i < _notes.length; i++) {
      final nt = _notes[i];
      if (near(_geo.xOf(nt.$1), _geo.yOf(nt.$2))) {
        return _Edit(ChartTool.note, i, 0);
      }
    }
    // Paralel kanal — A(0), B(1), offset(2) tutamaçları
    for (int i = 0; i < _channels.length; i++) {
      final ch = _channels[i];
      if (near(_geo.xOf(ch.$1), _geo.yOf(ch.$2))) {
        return _Edit(ChartTool.channel, i, 0);
      }
      if (near(_geo.xOf(ch.$3), _geo.yOf(ch.$4))) {
        return _Edit(ChartTool.channel, i, 1);
      }
      if (near(_geo.xOf(ch.$1), _geo.yOf(ch.$2 + ch.$5))) {
        return _Edit(ChartTool.channel, i, 2);
      }
    }
    // Pozisyon — giriş(0, sol), hedef(1, sağ), stop(2, sağ) tutamaçları
    for (int i = 0; i < _positions.length; i++) {
      final ps = _positions[i];
      if (near(_geo.xOf(ps.$1), _geo.yOf(ps.$2))) {
        return _Edit(ChartTool.position, i, 0);
      }
      if (near(_geo.xOf(ps.$3), _geo.yOf(ps.$4))) {
        return _Edit(ChartTool.position, i, 1);
      }
      if (near(_geo.xOf(ps.$3), _geo.yOf(ps.$5))) {
        return _Edit(ChartTool.position, i, 2);
      }
    }
    return null;
  }

  void _applyEdit(Offset pos) {
    final e = _edit;
    if (e == null) return;
    final p = _pointAt(pos, 0);
    if (p == null) return;
    _editDirty = true; // sürükleme bitince (onScaleEnd) kaydedilecek
    setState(() {
      switch (e.kind) {
        case ChartTool.hline:
          _hLines[e.index] = p.$2;
        case ChartTool.trend:
          final t = _trends[e.index];
          _trends[e.index] =
              e.end == 0 ? (p.$1, p.$2, t.$3, t.$4) : (t.$1, t.$2, p.$1, p.$2);
        case ChartTool.fib:
          final f = _fibs[e.index];
          _fibs[e.index] =
              e.end == 0 ? (p.$1, p.$2, f.$3, f.$4) : (f.$1, f.$2, p.$1, p.$2);
        case ChartTool.rect:
          final r = _rects[e.index];
          _rects[e.index] =
              e.end == 0 ? (p.$1, p.$2, r.$3, r.$4) : (r.$1, r.$2, p.$1, p.$2);
        case ChartTool.measure:
          if (e.end == 0) {
            _measA = p;
          } else {
            _measB = p;
          }
        case ChartTool.hray:
          _hrays[e.index] = (p.$1, p.$2);
        case ChartTool.vline:
          _vlines[e.index] = p.$1;
        case ChartTool.note:
          _notes[e.index] = (p.$1, p.$2, _notes[e.index].$3); // metni koru
        case ChartTool.channel:
          final ch = _channels[e.index];
          if (e.end == 0) {
            _channels[e.index] = (p.$1, p.$2, ch.$3, ch.$4, ch.$5);
          } else if (e.end == 1) {
            _channels[e.index] = (ch.$1, ch.$2, p.$1, p.$2, ch.$5);
          } else {
            // offset tutamacı A hizasında → yeni offset = sürüklenen fiyat - pA
            _channels[e.index] = (ch.$1, ch.$2, ch.$3, ch.$4, p.$2 - ch.$2);
          }
        case ChartTool.position:
          final ps = _positions[e.index];
          if (e.end == 0) {
            _positions[e.index] = (p.$1, p.$2, ps.$3, ps.$4, ps.$5); // giriş
          } else if (e.end == 1) {
            _positions[e.index] = (ps.$1, ps.$2, p.$1, p.$2, ps.$5); // hedef
          } else {
            _positions[e.index] = (ps.$1, ps.$2, ps.$3, ps.$4, p.$2); // stop
          }
        default:
          break;
      }
    });
  }

  void _deleteAt(Offset pos) {
    final e = _hitTest(pos);
    if (e == null) return;
    setState(() {
      switch (e.kind) {
        case ChartTool.hline:
          _hLines.removeAt(e.index);
        case ChartTool.trend:
          _trends.removeAt(e.index);
        case ChartTool.fib:
          _fibs.removeAt(e.index);
        case ChartTool.rect:
          _rects.removeAt(e.index);
        case ChartTool.measure:
          _measA = null;
          _measB = null;
        case ChartTool.hray:
          _hrays.removeAt(e.index);
        case ChartTool.vline:
          _vlines.removeAt(e.index);
        case ChartTool.note:
          _notes.removeAt(e.index);
        case ChartTool.channel:
          _channels.removeAt(e.index);
        case ChartTool.position:
          _positions.removeAt(e.index);
        default:
          break;
      }
    });
    _scheduleSave();
  }

  /// Tek parmak yatay sürükleme → zaman penceresini kaydır (TradingView pan).
  void _panBy(Offset cur, double width) {
    if (_panStart == null) return;
    final dx = cur.dx - _panStart!.dx;
    final dy = cur.dy - _panStart!.dy;
    final n = _effLen;
    final w = (_geo.ready ? _geo.right - _geo.left : width - 106);
    final count = _panBaseEnd - _panBaseStart;
    final barsPerPx = count / (w <= 0 ? 1 : w);
    var ns = (_panBaseStart - dx * barsPerPx).round();
    var ne = ns + count;
    if (ns < 0) {
      ns = 0;
      ne = count;
    }
    if (ne > n) {
      ne = n;
      ns = n - count;
    }
    // Dikey: fiyat görünümünü kaydır (skala-uzayında)
    double off = _panBaseOffset;
    if (_geo.ready && _priceScale != 1.0) {
      final a = _geo._sc(_geo.minY), b = _geo._sc(_geo.maxY);
      off = _panBaseOffset + dy * (b - a) / _geo.h;
    }
    setState(() {
      _visibleStart = ns;
      _visibleEnd = ne;
      _priceOffset = off;
    });
  }

  // Bir trend çizgisinin (idxA,pA)-(idxB,pB) belirli bir x-index'teki fiyatı.
  double _priceOnLine(int ia, double pa, int ib, double pb, int at) {
    if (ib == ia) return pa;
    return pa + (pb - pa) * (at - ia) / (ib - ia);
  }

  void _placeToolPoint(Offset pos, double width) {
    final p = _pointAt(pos, width);
    if (p == null) return;
    final toolWas = _tool; // setState içinde cursor'a dönmeden önceki araç
    // Not aracı: tıklama → metin girişi (dialog). Async olduğu için aşağıdaki
    // sync setState switch'inden ÖNCE dallanır.
    if (_tool == ChartTool.note) {
      _promptNote(p);
      return;
    }
    var completed = false; // çizim tamamlandı mı → otomatik imlece dön
    void twoPoint(List<(int, double, int, double)> into) {
      if (_pendStart == null) {
        _pendStart = p;
      } else {
        into.add((_pendStart!.$1, _pendStart!.$2, p.$1, p.$2));
        _pendStart = null;
        completed = true; // 2. nokta kondu → tamam
      }
    }

    setState(() {
      switch (_tool) {
        case ChartTool.hline:
          _hLines.add(p.$2);
          completed = true;
        case ChartTool.measure:
          if (_measA == null || _measB != null) {
            _measA = p;
            _measB = null;
          } else {
            _measB = p;
            completed = true;
          }
        case ChartTool.trend:
          twoPoint(_trends);
        case ChartTool.fib:
          twoPoint(_fibs);
        case ChartTool.rect:
          twoPoint(_rects);
        case ChartTool.alert:
          widget.onCreateAlert?.call(p.$2);
          completed = true;
        case ChartTool.hray:
          _hrays.add((p.$1, p.$2));
          completed = true;
        case ChartTool.vline:
          _vlines.add(p.$1);
          completed = true;
        case ChartTool.note:
          break; // yukarıda _promptNote ile ele alındı (async)
        case ChartTool.channel:
          // 3 nokta: A → B (ana çizgi) → offset (paralel çizgi mesafesi)
          if (_pendStart == null && _pendChannel == null) {
            _pendStart = p; // A
          } else if (_pendChannel == null) {
            _pendChannel = (_pendStart!.$1, _pendStart!.$2, p.$1, p.$2); // A,B
            _pendStart = null;
          } else {
            final ch = _pendChannel!;
            final lineP = _priceOnLine(ch.$1, ch.$2, ch.$3, ch.$4, p.$1);
            _channels.add((ch.$1, ch.$2, ch.$3, ch.$4, p.$2 - lineP));
            _pendChannel = null;
            completed = true;
          }
        case ChartTool.position:
          // 2 nokta: giriş → hedef. Stop simetrik (1:1) başlar; kullanıcı
          // tutamaçla ayarlar.
          if (_pendStart == null) {
            _pendStart = p; // giriş
          } else {
            final entry = _pendStart!.$2;
            final stop = entry - (p.$2 - entry);
            _positions.add((_pendStart!.$1, entry, p.$1, p.$2, stop));
            _pendStart = null;
            completed = true;
          }
        case ChartTool.cursor:
          break;
      }
      // TradingView gibi: çizim tamamlanınca otomatik İMLECE dön → kullanıcı
      // grafikte hemen serbest hareket eder (pan/zoom), yanlışlıkla üst üste
      // çizim yapmaz. Çok-noktalı araçta yalnız SON nokta sonrası döner.
      if (completed) _tool = ChartTool.cursor;
    });
    // Kalıcı bir çizim tamamlandıysa kaydet (alarm = çizim değil; measure transient).
    if (completed &&
        toolWas != ChartTool.alert &&
        toolWas != ChartTool.measure) {
      _scheduleSave();
    }
  }

  // Not aracı: tıklanan noktaya bağlı kısa bir metin al, sonra not olarak ekle.
  Future<void> _promptNote((int, double) at) async {
    final ctrl = TextEditingController();
    final c = AppColorsExt.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Not ekle',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          cursorColor: c.textPrimary,
          style: TextStyle(color: c.textPrimary),
          decoration: const InputDecoration(hintText: 'Not metni…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Vazgeç', style: TextStyle(color: c.textMuted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('Ekle', style: TextStyle(color: c.warmAccent))),
        ],
      ),
    );
    if (!mounted) return;
    final t = (text ?? '').trim();
    setState(() {
      if (t.isNotEmpty) _notes.add((at.$1, at.$2, t));
      _tool = ChartTool.cursor; // her durumda imlece dön
    });
    if (t.isNotEmpty) _scheduleSave();
  }

  // ── Bar replay kontrolleri ──
  void _toggleReplay() {
    setState(() {
      if (_replay) {
        _replayLen = null;
      } else {
        // Görünür sağ kenardan başla
        _replayLen = _end.clamp(8, widget.data.length);
        _visibleStart = null;
        _visibleEnd = null;
      }
    });
  }

  void _replayStep(int delta) {
    if (!_replay) return;
    setState(() {
      _replayLen = (_replayLen! + delta).clamp(8, widget.data.length);
      _visibleStart = null;
      _visibleEnd = null;
    });
  }

  // Replay'i belirli bir uzunluğa atla (ör. en başa = 8). Tek tek
  // ileri/geri basmak yerine hızlı sıçrama.
  void _replayJumpTo(int len) {
    if (!_replay) return;
    setState(() {
      _replayLen = len.clamp(8, widget.data.length);
      _visibleStart = null;
      _visibleEnd = null;
    });
  }

  // Rastgele bir noktaya atla — "körlemesine" backtest pratiği için
  // (sonucu bilmeden ileri sar, tahminini test et).
  void _replayRandom() {
    if (!_replay) return;
    final n = widget.data.length;
    if (n < 12) return;
    setState(() {
      _replayLen = 8 + math.Random().nextInt(n - 8);
      _visibleStart = null;
      _visibleEnd = null;
    });
  }

  // Bir barın tarihini güvenli oku (epoch timestamp varsa onu kullan,
  // yoksa 'date' string'ini parse et). İkisi de yoksa null.
  DateTime? _barDate(int i) {
    if (i < 0 || i >= widget.data.length) return null;
    final ts = (widget.data[i]['timestamp'] as num?)?.toInt();
    if (ts != null) return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final ds = widget.data[i]['date'] as String?;
    return ds == null ? null : DateTime.tryParse(ds);
  }

  // Replay'i seçilen takvim tarihine atla — tarih seçici → o güne en yakın
  // (>=) barı bul → o uzunluğa sıçra. Tek tek ◀▶ basmadan belirli bir
  // döneme git.
  Future<void> _replayJumpToDate() async {
    if (!_replay) return;
    final n = widget.data.length;
    final first = _barDate(0);
    final last = _barDate(n - 1);
    if (first == null || last == null) return;
    final fd = DateTime(first.year, first.month, first.day);
    final ld = DateTime(last.year, last.month, last.day);
    final curIdx = ((_replayLen ?? n) - 1).clamp(0, n - 1);
    final cur = _barDate(curIdx) ?? last;
    var init = DateTime(cur.year, cur.month, cur.day);
    if (init.isBefore(fd)) init = fd;
    if (init.isAfter(ld)) init = ld;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: fd,
      lastDate: ld,
      helpText: 'Replay tarihini seç',
    );
    if (picked == null || !mounted) return;
    final target = DateTime(picked.year, picked.month, picked.day);
    int idx = n - 1;
    for (int i = 0; i < n; i++) {
      final d = _barDate(i);
      if (d != null && !d.isBefore(target)) {
        idx = i;
        break;
      }
    }
    _replayJumpTo(idx + 1);
  }

  // TradingView gibi: varsayılan son ~160 barı göster, geçmiş için uzaklaş.
  // Yüzlerce intraday barını tek ekrana sıkıştırıp mumları ezmez.
  static const int _defaultWindow = 160;
  int get _start => _visibleStart ?? math.max(0, _effLen - _defaultWindow);
  int get _end => _visibleEnd ?? (_effLen == 0 ? 0 : _effLen);
  int get _visibleCount => math.max(2, _end - _start);

  void _zoom(double scrollDeltaY, double localX, double width) {
    final n = _effLen;
    if (n < 4) return;
    final start = _start;
    final end = _end;
    final count = end - start;
    final factor = scrollDeltaY > 0 ? 1.18 : 1 / 1.18;
    final newCount = (count * factor).round().clamp(8, n);
    if (newCount == count) return;
    const leftPad = 50.0;
    const rightPad = 12.0;
    final chartW = width - leftPad - rightPad;
    final ratio = ((localX - leftPad) / chartW).clamp(0.0, 1.0);
    final hoveredIndex = start + (count * ratio).round();
    var newStart = (hoveredIndex - (newCount * ratio)).round();
    var newEnd = newStart + newCount;
    if (newStart < 0) {
      newStart = 0;
      newEnd = newCount;
    }
    if (newEnd > n) {
      newEnd = n;
      newStart = n - newCount;
    }
    setState(() {
      _visibleStart = newStart;
      _visibleEnd = newEnd;
    });
  }

  // Toolbar zoom +/- (kullanıcı "alt zoom in/out bozulmuş" dedi → tekerlek/
  // pinch'e bağlı kalmadan GÜVENİLİR buton). Görünür aralığın MERKEZİ etrafında
  // daralt (factor<1 = yakınlaş) / genişlet (factor>1 = uzaklaş).
  void _zoomCentered(double factor) {
    final n = _effLen;
    if (n < 8) return;
    final start = _start, end = _end;
    final count = end - start;
    final newCount = (count * factor).round().clamp(8, n);
    if (newCount == count) return;
    final center = start + count ~/ 2;
    var newStart = center - newCount ~/ 2;
    var newEnd = newStart + newCount;
    if (newStart < 0) {
      newStart = 0;
      newEnd = newCount;
    }
    if (newEnd > n) {
      newEnd = n;
      newStart = n - newCount;
    }
    setState(() {
      _visibleStart = newStart;
      _visibleEnd = newEnd;
    });
  }

  void _pinchZoom(double scale, double focalX, double width) {
    if (_scaleStartCount == 0 || scale == 1) return;
    final n = _effLen;
    if (n < 4) return;
    var newCount = (_scaleStartCount / scale).round().clamp(8, n);
    if (newCount == _visibleCount) return;
    const leftPad = 50.0;
    const rightPad = 56.0;
    final chartW = width - leftPad - rightPad;
    final ratio = ((focalX - leftPad) / chartW).clamp(0.0, 1.0);
    final start = _start;
    final end = _end;
    final hoveredIndex = start + ((end - start) * ratio).round();
    var newStart = (hoveredIndex - (newCount * ratio)).round();
    var newEnd = newStart + newCount;
    if (newStart < 0) {
      newStart = 0;
      newEnd = newCount;
    }
    if (newEnd > n) {
      newEnd = n;
      newStart = n - newCount;
    }
    setState(() {
      _visibleStart = newStart;
      _visibleEnd = newEnd;
    });
  }

  void _resetZoom() {
    setState(() {
      _visibleStart = null;
      _visibleEnd = null;
      _priceScale = 1.0;
      _priceOffset = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColorsExt.of(context);
    if (widget.data.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child:
              Text('Grafik verisi yok', style: TextStyle(color: cx.textMuted)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(),
        if (_tool != ChartTool.cursor || _replay) ...[
          const SizedBox(height: 8),
          _buildHintBar(),
        ],
        const SizedBox(height: 10),
        Container(
          height: widget.height,
          // CustomPaint varsayılan olarak kırpmaz; dikey fiyat-zoom (sağ
          // eksen sürüklemesi) mumları panel dışına taşırınca toolbar'ın
          // üstüne taşıyordu. Kutuyu kırp → zoom'da mumlar panelde kalır.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // Özel arka plan rengi (kullanıcı seçtiyse) → yoksa tema yüzeyi.
            color: _bgColor != null ? Color(_bgColor!) : cx.surface,
            borderRadius: BorderRadius.circular(16),
            // Grafik çerçevesi (Task #6): kullanıcı "çerçeveye ihtiyacı var" dedi.
            border: Border.all(color: cx.divider, width: 1),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    return Listener(
                      onPointerSignal: (signal) {
                        if (signal is PointerScrollEvent) {
                          // Resolver'a kaydet → olayı TÜKET; böylece tekerlek olayı
                          // ebeveyn scroll'a GİTMEZ. (Masaüstünde imleç grafik
                          // üstündeyken tekerlek hem sayfayı hem chartı kaydırıyordu.)
                          GestureBinding.instance.pointerSignalResolver
                              .register(signal, (e) {
                            final ev = e as PointerScrollEvent;
                            // Sağ fiyat-ekseni şeridinde tekerlek → dikey fiyat zoom
                            if (ev.localPosition.dx > c.maxWidth - 56) {
                              _priceZoomBy(ev.scrollDelta.dy);
                            } else {
                              _zoom(ev.scrollDelta.dy, ev.localPosition.dx,
                                  c.maxWidth);
                            }
                          });
                        }
                        if (signal is PointerScaleEvent) {
                          final delta = signal.scale > 1 ? -50.0 : 50.0;
                          _zoom(delta, signal.localPosition.dx, c.maxWidth);
                        }
                      },
                      onPointerHover: (event) {
                        _setHover(event.localPosition, c.maxWidth);
                      },
                      onPointerDown: (event) {
                        final pos = event.localPosition;
                        if (_tool != ChartTool.cursor) {
                          _placeToolPoint(pos, c.maxWidth);
                          return;
                        }
                        // Sağ eksen şeridinde → dikey fiyat zoom
                        _axisDrag = pos.dx > c.maxWidth - 56;
                        if (_axisDrag) return;
                        // Alt zaman ekseni şeridinde → yatay zaman zoom (sağ
                        // fiyat ekseninin aynası; sağ-alt köşede sağ eksen önce).
                        _timeAxisDrag = pos.dy > c.maxHeight - 28;
                        if (_timeAxisDrag) return;
                        // Bir çizim tutamacına mı dokunuldu? → düzenle
                        final hit = _hitTest(pos);
                        if (hit != null) {
                          _edit = hit;
                          return;
                        }
                        // Aksi halde pan adayı + anlık crosshair (kısa dokunuş okuma)
                        _edit = null;
                        _panning = false;
                        _panStart = pos;
                        _panBaseStart = _start;
                        _panBaseEnd = _end;
                        _panBaseOffset = _priceOffset;
                        _setHover(pos, c.maxWidth);
                      },
                      child: GestureDetector(
                        onScaleStart: (d) {
                          _scaleStartCount = _visibleCount;
                        },
                        onScaleUpdate: (d) {
                          final pos = d.localFocalPoint;
                          if (d.pointerCount >= 2) {
                            _axisDrag = false;
                            _timeAxisDrag = false;
                            _edit = null;
                            _panning = false;
                            _pinchZoom(d.scale, pos.dx, c.maxWidth);
                            return;
                          }
                          if (_edit != null) {
                            _applyEdit(pos);
                            return;
                          }
                          if (_axisDrag) {
                            _priceZoomBy(d.focalPointDelta.dy);
                            return;
                          }
                          if (_timeAxisDrag) {
                            _timeZoomByDrag(d.focalPointDelta.dx);
                            return;
                          }
                          // Pan vs kısa-dokunuş-crosshair ayrımı (eşik 8px)
                          _panStart ??= pos;
                          final moved = (pos - _panStart!).distance;
                          if (!_panning && moved > 8) {
                            _panning = true;
                            setState(() {
                              _hoverIndex = null;
                              _hoverPos = null;
                            });
                          }
                          if (_panning) {
                            _panBy(pos, c.maxWidth);
                          } else {
                            _setHover(pos, c.maxWidth);
                          }
                        },
                        onScaleEnd: (_) {
                          _axisDrag = false;
                          _timeAxisDrag = false;
                          _edit = null;
                          _panning = false;
                          _panStart = null;
                          if (_editDirty) {
                            _editDirty = false;
                            _scheduleSave(); // çizim düzenlemesi bitti → kaydet
                          }
                          setState(() {
                            _hoverIndex = null;
                            _hoverPos = null;
                          });
                        },
                        onLongPressStart: (d) => _deleteAt(d.localPosition),
                        // Masaüstü: çizime sağ tık → o çizimi sil (tek silme).
                        onSecondaryTapDown: (d) => _deleteAt(d.localPosition),
                        onDoubleTap: _resetZoom,
                        child: MouseRegion(
                          onExit: (_) => setState(() {
                            _hoverIndex = null;
                            _hoverPos = null;
                          }),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(c.maxWidth, widget.height),
                              painter: _ChartPainter(
                                data: widget.data,
                                type: _type,
                                active: _active.toList(),
                                currency: widget.currency,
                                newsMarkers: widget.newsMarkers,
                                priceLines: widget.priceLines,
                                hoverIndex: _hoverIndex,
                                hoverPos: _hoverPos,
                                visibleStart: _start,
                                visibleEnd: _end,
                                gridColor: cx.divider,
                                axisColor: cx.textMuted,
                                lineColor: cx.textPrimary,
                                panelBg: cx.surfaceAlt,
                                upColor: _upColor != null
                                    ? Color(_upColor!)
                                    : _kGreen,
                                downColor: _downColor != null
                                    ? Color(_downColor!)
                                    : _kRedC,
                                tool: _tool,
                                hLines: _hLines,
                                trends: _trends,
                                measA: _measA,
                                measB: _measB,
                                accentColor: cx.warmAccent,
                                logScale: _logScale,
                                fibs: _fibs,
                                rects: _rects,
                                hrays: _hrays,
                                vlines: _vlines,
                                notes: _notes,
                                channels: _channels,
                                pendChannel: _pendChannel,
                                positions: _positions,
                                pendStart: _pendStart,
                                priceScale: _priceScale,
                                priceOffset: _priceOffset,
                                geo: _geo,
                                editing: _edit,
                                s: _series,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Sol-üst köşe: sembol + zaman dilimi etiketi (kullanıcı isteği).
              if (widget.symbolLabel != null || widget.timeframeLabel != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: IgnorePointer(child: _cornerLabel()),
                ),
            ],
          ),
        ),
        if (_active.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildLegend(),
        ],
      ],
    );
  }

  Widget _buildToolbar() {
    final c = AppColorsExt.of(context);
    // Yatay kaydırılır → dar telefonda taşmaz, tüm araçlar erişilebilir.
    return HorizontalWheelScroll(
      builder: (ctrl) => SingleChildScrollView(
        controller: ctrl,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _typeButton(ChartType.line, 'Çizgi', Icons.show_chart),
                  _typeButton(ChartType.candle, 'Mum', Icons.candlestick_chart),
                  _typeButton(ChartType.heikinAshi, 'Heikin', Icons.bar_chart),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ── Çizim araçları (TradingView sol araç çubuğu mantığı) ──
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _toolButton(ChartTool.cursor, Icons.near_me, 'İmleç'),
                  _toolButton(
                      ChartTool.hline, Icons.horizontal_rule, 'Yatay çizgi'),
                  _toolButton(
                      ChartTool.hray, Icons.arrow_right_alt, 'Yatay ışın'),
                  _toolButton(
                      ChartTool.vline, Icons.border_vertical, 'Dikey çizgi'),
                  _toolButton(ChartTool.note, Icons.text_fields, 'Not'),
                  _toolButton(ChartTool.channel, Icons.stacked_line_chart,
                      'Paralel kanal'),
                  _toolButton(
                      ChartTool.position, Icons.swap_vert, 'Pozisyon (R:R)'),
                  _toolButton(
                      ChartTool.trend, Icons.trending_up, 'Trend çizgisi'),
                  _toolButton(
                      ChartTool.fib, Icons.signal_cellular_alt, 'Fibonacci'),
                  _toolButton(
                      ChartTool.rect, Icons.crop_square, 'Dikdörtgen/Zon'),
                  _toolButton(ChartTool.measure, Icons.straighten, 'Ölç'),
                  if (widget.onCreateAlert != null)
                    _toolButton(ChartTool.alert,
                        Icons.notifications_active_outlined, 'Alarm kur'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Mıknatıs (snap) — açıkken çizim en yakın muma (O/H/L/C) yapışır.
            Tooltip(
              message:
                  _snap ? 'Mıknatıs açık (muma yapışır)' : 'Mıknatıs kapalı',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _snap = !_snap);
                    _persistSnap();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _snap ? c.warmAccentSoft : c.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_snap ? Icons.gps_fixed : Icons.gps_off,
                        size: 15, color: _snap ? c.warmAccent : c.textMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Log / Lineer fiyat skalası
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _logScale = !_logScale),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _logScale ? c.warmAccentSoft : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_logScale ? 'LOG' : 'LIN',
                      style: TextStyle(
                          color: _logScale ? c.warmAccent : c.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Zoom +/- (güvenilir buton; tekerlek/pinch'e bağlı değil).
            Tooltip(
              message: 'Uzaklaş',
              child: _pillBtn(Icons.zoom_out, () => _zoomCentered(1.4)),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Yakınlaş',
              child: _pillBtn(Icons.zoom_in, () => _zoomCentered(1 / 1.4)),
            ),
            const SizedBox(width: 8),
            // Bar replay (backtest) — aç/kapat + adımla
            _pillBtn(_replay ? Icons.stop_circle_outlined : Icons.replay,
                _toggleReplay),
            if (_replay) ...[
              const SizedBox(width: 6),
              _pillBtn(Icons.first_page, () => _replayJumpTo(8)), // en başa
              const SizedBox(width: 6),
              _pillBtn(Icons.keyboard_double_arrow_left,
                  () => _replayStep(-10)), // 10 geri
              const SizedBox(width: 6),
              _pillBtn(Icons.chevron_left, () => _replayStep(-1)),
              const SizedBox(width: 6),
              _pillBtn(Icons.chevron_right, () => _replayStep(1)),
              const SizedBox(width: 6),
              _pillBtn(Icons.keyboard_double_arrow_right,
                  () => _replayStep(10)), // 10 ileri
              const SizedBox(width: 6),
              _pillBtn(Icons.event_outlined,
                  () => _replayJumpToDate()), // tarihe git
              const SizedBox(width: 6),
              _pillBtn(Icons.casino_outlined, _replayRandom), // rastgele
            ],
            if (_hasDrawings) ...[
              const SizedBox(width: 8),
              // Tek çizim silmek için ona UZUN BAS (clear-all değil). Bu buton
              // TÜMÜNÜ temizler → karışmasın diye net etiket (kullanıcı "her şeyi
              // siliyor" dedi).
              Tooltip(
                message: 'Tüm çizimleri temizle (tek silme: çizime uzun bas)',
                child: _pillBtn(Icons.delete_sweep_outlined, _clearDrawings),
              ),
            ],
            if (_visibleStart != null || _visibleEnd != null) ...[
              const SizedBox(width: 8),
              _pillBtn(Icons.fit_screen, _resetZoom),
            ],
            const SizedBox(width: 8),
            // Mum + arka plan renk özelleştirmesi (Kerem 'acil' dedi).
            Tooltip(
              message: 'Renkler (mum + arka plan)',
              child: _pillBtn(Icons.palette_outlined, _openChartSettingsSheet),
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _openIndicatorSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.warmAccentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune, size: 14, color: c.warmAccent),
                      const SizedBox(width: 6),
                      Text('Göstergeler',
                          style: TextStyle(
                              color: c.warmAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1)),
                      if (_active.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.warmAccent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('${_active.length}',
                              style: TextStyle(
                                color: c.surface,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              )),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Grafiğin sol-üst köşesindeki sembol + zaman dilimi etiketi (kullanıcı
  // "hangi zaman dilimine bakıyorum bilmiyorum" dedi). Canvas yerine widget →
  // html-renderer'da metin sessizce kaybolmaz (memory: canvas metni güvenilmez).
  Widget _cornerLabel() {
    final c = AppColorsExt.of(context);
    final parts = <String>[
      if (widget.symbolLabel != null) widget.symbolLabel!,
      if (widget.timeframeLabel != null) widget.timeframeLabel!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.surfaceAlt.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(parts.join('  ·  '),
          style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2)),
    );
  }

  Widget _pillBtn(IconData icon, VoidCallback onTap) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.warmAccentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: c.warmAccent),
        ),
      ),
    );
  }

  Widget _toolButton(ChartTool tool, IconData icon, String tip) {
    final c = AppColorsExt.of(context);
    final selected = _tool == tool;
    return Tooltip(
      message: tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() {
            _tool = tool;
            if (tool == ChartTool.cursor) {
              _pendStart = null;
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.warmAccentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon,
                size: 15, color: selected ? c.warmAccent : c.textMuted),
          ),
        ),
      ),
    );
  }

  /// Aktif araç/replay için bağlamsal yönerge — çizimi kolaylaştırır.
  Widget _buildHintBar() {
    final c = AppColorsExt.of(context);
    String msg;
    if (_replay) {
      msg =
          'Replay: ${_replayLen ?? 0}/${widget.data.length} bar  ·  ◀ ▶ ile adımla, geleceği gizli';
    } else {
      switch (_tool) {
        case ChartTool.hline:
          msg = 'Bir bara dokun → o fiyatta yatay destek/direnç';
        case ChartTool.trend:
          msg = _awaitingSecond
              ? 'İkinci noktaya dokun (B)'
              : 'İlk noktaya dokun (A)';
        case ChartTool.fib:
          msg = _awaitingSecond
              ? 'Bitiş noktasına dokun → Fibonacci seviyeleri'
              : 'Başlangıç (swing) noktasına dokun';
        case ChartTool.rect:
          msg = _awaitingSecond
              ? 'Karşı köşeye dokun → bölge'
              : 'Bir köşeye dokun';
        case ChartTool.measure:
          msg = _awaitingSecond
              ? 'Bitiş barına dokun → Δ% ve bar sayısı'
              : 'Başlangıç barına dokun';
        case ChartTool.alert:
          msg = 'Bir fiyata dokun → o seviyeye alarm kur';
        case ChartTool.hray:
          msg = 'Bir noktaya dokun → o fiyattan SAĞA uzanan yatay ışın';
        case ChartTool.vline:
          msg = 'Bir bara dokun → o zamanda dikey çizgi';
        case ChartTool.note:
          msg = 'Bir noktaya dokun → metin/not ekle';
        case ChartTool.channel:
          msg = _pendChannel != null
              ? 'Üçüncü noktaya dokun → kanal genişliği'
              : _awaitingSecond
                  ? 'İkinci noktaya dokun (ana çizgi B)'
                  : 'İlk noktaya dokun (ana çizgi A)';
        case ChartTool.position:
          msg = _awaitingSecond
              ? 'Hedef fiyata dokun → risk/ödül kutusu'
              : 'Giriş noktasına dokun';
        case ChartTool.cursor:
          msg = '';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.warmAccentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(_replay ? Icons.fast_rewind : Icons.touch_app,
              size: 14, color: c.warmAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    color: c.warmAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1)),
          ),
        ],
      ),
    );
  }

  // Kompakt (Kerem: "bu kadar yer kaplamayı hak etmiyor"): yalnız SEÇİLİ tip
  // etiketli, diğerleri sadece ikon (+ tooltip). Yer ~yarıya iner.
  Widget _typeButton(ChartType type, String label, IconData icon) {
    final c = AppColorsExt.of(context);
    final selected = _type == type;
    return Tooltip(
      message: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() => _type = type);
            _persistChartType(); // tip seçimini kalıcı yap (timeframe + oturum)
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
                horizontal: selected ? 10 : 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.warmAccentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 14, color: selected ? c.warmAccent : c.textMuted),
                if (selected) ...[
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          color: c.warmAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Aktif göstergelerin renkli swatch'lı kompakt lejantı.
  Widget _buildLegend() {
    final c = AppColorsExt.of(context);
    final ordered = Indicator.values.where(_active.contains);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: ordered.map((ind) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 3,
              decoration: BoxDecoration(
                color: ind.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            Text(ind.label, style: TextStyle(color: c.textMuted, fontSize: 10)),
          ],
        );
      }).toList(),
    );
  }

  // Mum + arka plan renk özelleştirme paneli (Kerem 'acil' dedi). Renk
  // tekerleği yok — data-ink: birkaç net preset. Seçim ANINDA uygulanır + kalıcı.
  void _openChartSettingsSheet() {
    const defUp = 0xFF26A69A; // varsayılan yükseliş
    const defDown = 0xFFEF5350; // varsayılan düşüş
    const candleSwatches = <int>[
      0xFF26A69A,
      0xFF2962FF,
      0xFF00BCD4,
      0xFFECEFF1,
      0xFFFFB300,
      0xFFEF5350,
      0xFFEC407A,
      0xFFAB47BC,
    ];
    const bgSwatches = <int>[
      0xFF000000,
      0xFF0A0E14,
      0xFF0D1B2A,
      0xFF121212,
      0xFF161A1E,
    ];
    showIOSBottomSheet(
      context: context,
      title: 'Grafik Renkleri',
      child: StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = AppColorsExt.of(ctx);
          Widget swatch(int? value, int? current, VoidCallback onTap,
              {bool isDefault = false}) {
            final selected = value == current;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  onTap();
                  _persistColors();
                  setState(() {});
                  setSheet(() {});
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDefault ? c.surfaceAlt : Color(value!),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? c.warmAccent : c.divider,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: isDefault
                      ? Icon(Icons.format_color_reset,
                          size: 15, color: c.textMuted)
                      : null,
                ),
              ),
            );
          }

          Widget section(String label, List<Widget> swatches) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: swatches),
                  const SizedBox(height: 22),
                ],
              );

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section('Yükseliş mumu', [
                  for (final s in candleSwatches)
                    swatch(s, _upColor ?? defUp, () => _upColor = s),
                ]),
                section('Düşüş mumu', [
                  for (final s in candleSwatches)
                    swatch(s, _downColor ?? defDown, () => _downColor = s),
                ]),
                section('Arka plan', [
                  swatch(null, _bgColor, () => _bgColor = null,
                      isDefault: true),
                  for (final s in bgSwatches)
                    swatch(s, _bgColor, () => _bgColor = s),
                ]),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _upColor = null;
                      _downColor = null;
                      _bgColor = null;
                      _persistColors();
                      setState(() {});
                      setSheet(() {});
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Varsayılana sıfırla',
                          style: TextStyle(
                              color: c.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openIndicatorSheet() {
    showIOSBottomSheet(
      context: context,
      title: 'Göstergeler',
      child: StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = AppColorsExt.of(ctx);
          void toggle(Indicator ind) {
            setSheet(() {});
            setState(() {
              if (_active.contains(ind)) {
                _active.remove(ind);
              } else {
                _active.add(ind);
              }
            });
            _persistIndicators(); // seçimi kalıcı yap (timeframe + oturum)
          }

          Widget row(Indicator ind) {
            final on = _active.contains(ind);
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => toggle(ind),
                child: Container(
                  color: Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ind.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(ind.label,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1)),
                      ),
                      Switch.adaptive(
                        value: on,
                        onChanged: (_) => toggle(ind),
                        activeColor: c.warmAccent,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final overlays = Indicator.values.where((i) => !i.isPanel).toList();
          final panels = Indicator.values.where((i) => i.isPanel).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IOSSectionHeader(label: 'Fiyat Üzeri'),
                const SizedBox(height: 6),
                IOSGroupedCard(
                  dividerInset: 44,
                  children: overlays.map(row).toList(),
                ),
                const SizedBox(height: 20),
                const IOSSectionHeader(label: 'Alt Panel'),
                const SizedBox(height: 6),
                IOSGroupedCard(
                  dividerInset: 44,
                  children: panels.map(row).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Göstergeler backtest ve teknik analiz içindir. RSI ve MACD ayrı panellerde, MA/EMA/Bollinger/VWAP fiyat grafiğinde gösterilir.',
                  style:
                      TextStyle(color: c.textSubtle, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Crosshair konumu + snap'li bar indexi TEK setState'te güncellenir.
  // Eskiden çağıranlar ayrıca `setState(_hoverPos)` yapıyordu → her mouse
  // pikselinde iki rebuild. Değişiklik yoksa erken çıkar (gereksiz repaint
  // yok).
  void _setHover(Offset pos, double width) {
    final n = widget.data.length;
    if (n == 0) return;
    // Hangi bar? (geo varsa hassas). Crosshair bu bara SNAP'lenir.
    int idx;
    double crossY = pos.dy;
    // Çizim aracı aktifken crosshair önizlemesi, yerleştirilecek noktayla
    // BİREBİR eşleşmeli (WYSIWYG): mıknatıs kapalı → serbest y, açık → muma
    // yapışık. İmleç (okuma) modunda kapanışa snap + bar-bazlı repaint (FPS).
    final drawing = _tool != ChartTool.cursor;
    if (_geo.ready) {
      idx = _geo.idxAt(pos.dx).clamp(0, n - 1);
      if (drawing && !_snap) {
        crossY = pos.dy.clamp(_geo.top, _geo.top + _geo.h); // serbest önizleme
      } else if (drawing && _snap) {
        final p = _snapPriceToOHLC(idx, _geo.priceAt(pos.dy));
        crossY = _geo.yOf(p);
      } else {
        final close = (widget.data[idx]['close'] as num?)?.toDouble();
        if (close != null) crossY = _geo.yOf(close); // yatay çizgi = kapanış
      }
    } else {
      const leftPad = 50.0;
      const rightPad = 56.0;
      final chartW = width - leftPad - rightPad;
      if (chartW <= 0) return;
      final ratio = ((pos.dx - leftPad) / chartW).clamp(0.0, 1.0);
      final visCount = _visibleCount;
      final local = (ratio * (visCount - 1)).round().clamp(0, visCount - 1);
      idx = _start + local;
    }
    // PERF (donma çözümü): okuma modunda yalnız HOVER EDİLEN BAR değişince
    // repaint (crosshair muma snap'li). Serbest çizim önizlemesinde Y de
    // önemli → o modda pos değişince repaint (kullanıcı hassas yerleştirirken
    // kabul edilebilir; tarama değil).
    final newPos = Offset(pos.dx, crossY);
    if (drawing && !_snap) {
      if (idx == _hoverIndex && _hoverPos == newPos) return;
    } else {
      if (idx == _hoverIndex) return;
    }
    setState(() {
      _hoverIndex = idx;
      _hoverPos = newPos;
    });
  }
}

// ─── Painter ───────────────────────────────────────────────────────────

class _Panel {
  final double top;
  final double height;
  const _Panel(this.top, this.height);
  double get bottom => top + height;
}

class _ChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final ChartType type;
  final List<Indicator> active;
  final String currency;
  final List<NewsMarker> newsMarkers;
  final List<PriceLine> priceLines;
  final int? hoverIndex;
  final Offset? hoverPos;
  final int visibleStart;
  final int visibleEnd;
  final Color gridColor;
  final Color axisColor;
  final Color lineColor;
  final Color panelBg;
  final Color upColor; // yükseliş mumu (özelleştirilebilir)
  final Color downColor; // düşüş mumu (özelleştirilebilir)
  final ChartTool tool;
  final List<double> hLines;
  final List<(int, double, int, double)> trends;
  final List<(int, double, int, double)> fibs;
  final List<(int, double, int, double)> rects;
  final List<(int, double)> hrays;
  final List<int> vlines;
  final List<(int, double, String)> notes;
  final List<(int, double, int, double, double)> channels;
  final (int, double, int, double)? pendChannel;
  final List<(int, double, int, double, double)> positions;
  final (int, double)? measA;
  final (int, double)? measB;
  final (int, double)? pendStart;
  final Color accentColor;
  final bool logScale;
  final double priceScale;
  final double priceOffset;
  final _ChartGeo geo;
  final _Edit? editing;
  // Full-seri kolonlar + indikatörler — data başına BİR kez hesaplanır
  // (State'te memo'lanır). Eskiden paint() her repaint'te (hover'da her
  // piksel) SMA200/Bollinger/VWAP/RSI'ı 500 nokta üstünde yeniden
  // hesaplıyordu → grafik donuyordu.
  final _SeriesCache s;

  static const double _leftPad = 50;
  static const double _rightPad = 56;
  static const double _topPad = 16;
  static const double _bottomPad = 28;
  static const double _volumeH = 56;
  static const double _rsiH = 70;
  static const double _macdH = 78;
  static const double _gap = 10;

  _ChartPainter({
    required this.data,
    required this.type,
    required this.active,
    required this.currency,
    required this.newsMarkers,
    required this.priceLines,
    required this.hoverIndex,
    required this.hoverPos,
    required this.visibleStart,
    required this.visibleEnd,
    required this.gridColor,
    required this.axisColor,
    required this.lineColor,
    required this.panelBg,
    required this.upColor,
    required this.downColor,
    required this.tool,
    required this.hLines,
    required this.trends,
    required this.fibs,
    required this.rects,
    required this.hrays,
    required this.vlines,
    required this.notes,
    required this.channels,
    required this.pendChannel,
    required this.positions,
    required this.measA,
    required this.measB,
    required this.pendStart,
    required this.accentColor,
    required this.logScale,
    required this.priceScale,
    required this.priceOffset,
    required this.geo,
    required this.editing,
    required this.s,
  });

  bool _on(Indicator i) => active.contains(i);
  List<Map<String, dynamic>> get _visible =>
      data.sublist(visibleStart, visibleEnd);

  List<double?> _slice(List<double?> full) =>
      full.sublist(visibleStart, visibleEnd);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final visData = _visible;
    if (visData.isEmpty) return;

    final ohlc = _extractOHLCFrom(visData);
    final renderOHLC =
        type == ChartType.heikinAshi ? _toHeikinAshi(ohlc) : ohlc;

    // Overlay serileri (memo'dan slice — paint'te yeniden hesap YOK)
    final overlays = <Indicator, List<double?>>{};
    if (_on(Indicator.ma20)) {
      overlays[Indicator.ma20] = _slice(s.sma20);
    }
    if (_on(Indicator.ma50)) {
      overlays[Indicator.ma50] = _slice(s.sma50);
    }
    if (_on(Indicator.ma200)) {
      overlays[Indicator.ma200] = _slice(s.sma200);
    }
    if (_on(Indicator.ema20)) {
      overlays[Indicator.ema20] = _slice(s.ema20);
    }
    List<double?>? bollU, bollL, bollM;
    if (_on(Indicator.boll)) {
      bollU = _slice(s.boll.upper);
      bollL = _slice(s.boll.lower);
      bollM = _slice(s.boll.mid);
    }
    List<double?>? vwap;
    if (_on(Indicator.vwap)) {
      vwap = _slice(s.vwap);
    }

    // Y eksen min/max (fiyat paneli) — overlay'leri de kapsa
    double minY = double.infinity, maxY = -double.infinity;
    for (final c in renderOHLC) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    void includeNullable(List<double?>? s) {
      if (s == null) return;
      for (final v in s) {
        if (v == null) continue;
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }

    overlays.values.forEach(includeNullable);
    includeNullable(bollU);
    includeNullable(bollL);
    includeNullable(vwap);
    for (final pl in priceLines) {
      if (pl.price < minY) minY = pl.price;
      if (pl.price > maxY) maxY = pl.price;
    }
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;
    if (maxY == minY) maxY = minY + 1;
    // Dikey fiyat zoom — skala uzayında merkez etrafında daralt/genişlet.
    if (priceScale != 1.0) {
      final a = _sc(minY), b = _sc(maxY);
      final mid = (a + b) / 2;
      final half = (b - a) / 2 / priceScale;
      minY = _unsc(mid - half);
      maxY = _unsc(mid + half);
    }
    // Dikey pan — skala uzayında kaydır.
    if (priceOffset != 0) {
      minY = _unsc(_sc(minY) + priceOffset);
      maxY = _unsc(_sc(maxY) + priceOffset);
    }

    // ── Panel yığını layout ──
    final chartLeft = _leftPad;
    final chartRight = size.width - _rightPad;
    final chartW = chartRight - chartLeft;
    final stackTop = _topPad;
    final stackBottom = size.height - _bottomPad;

    final hasRsi = _on(Indicator.rsi);
    final hasMacd = _on(Indicator.macd);
    final hasVol = _on(Indicator.volume);
    // İstenen alt-panel yükseklikleri. Küçük yükseklikte bunlar fiyat panelini
    // ezip ÇAKIŞMAYA yol açıyordu (kullanıcı "RSI çakışıyor" dedi). Çözüm:
    // fiyat paneline her zaman ≥%50 ayır; alt paneller sığmıyorsa ORANTILI
    // küçült → RSI/MACD/Hacim her zaman fiyatın ALTINDA ayrı bantta kalır.
    final panelCount = (hasRsi ? 1 : 0) + (hasMacd ? 1 : 0) + (hasVol ? 1 : 0);
    final gapsTotal = panelCount * _gap;
    var rsiH = _rsiH, macdH = _macdH, volH = _volumeH;
    var desiredBars =
        (hasRsi ? rsiH : 0) + (hasMacd ? macdH : 0) + (hasVol ? volH : 0);
    final totalAvail = stackBottom - stackTop;
    final maxBars = (totalAvail * 0.50) - gapsTotal; // fiyata ≥%50
    if (desiredBars > maxBars && desiredBars > 0 && maxBars > 0) {
      final scale = maxBars / desiredBars;
      rsiH *= scale;
      macdH *= scale;
      volH *= scale;
      desiredBars = maxBars;
    }
    final subTotal = panelCount > 0 ? desiredBars + gapsTotal : 0.0;

    final priceH = math.max(60.0, (stackBottom - stackTop) - subTotal);
    final pricePanel = _Panel(stackTop, priceH);
    // Geometriyi state'e köprüle (hit-test / hassas çizim için).
    geo
      ..left = chartLeft
      ..right = chartRight
      ..top = pricePanel.top
      ..h = pricePanel.height
      ..minY = minY
      ..maxY = maxY
      ..log = logScale
      ..type = type
      ..visStart = visibleStart
      ..visEnd = visibleEnd;
    double cursor = pricePanel.bottom + _gap;
    _Panel? rsiPanel, macdPanel, volPanel;
    if (hasRsi) {
      rsiPanel = _Panel(cursor, rsiH);
      cursor += rsiH + _gap;
    }
    if (hasMacd) {
      macdPanel = _Panel(cursor, macdH);
      cursor += macdH + _gap;
    }
    if (hasVol) {
      volPanel = _Panel(cursor, volH);
      cursor += volH + _gap;
    }
    final xAxisY = cursor;

    // ── Fiyat paneli ──
    _drawGrid(canvas, minY, maxY, chartLeft, pricePanel.top, chartW,
        pricePanel.height);
    _drawXLabels(canvas, visData, chartLeft, xAxisY, chartW);

    // Bollinger önce (en arkada, dolgu)
    if (bollU != null && bollL != null) {
      _drawBollinger(canvas, bollU, bollL, bollM, minY, maxY, chartLeft,
          pricePanel.top, chartW, pricePanel.height);
    }

    if (type == ChartType.line) {
      _drawLine(canvas, renderOHLC, minY, maxY, chartLeft, pricePanel.top,
          chartW, pricePanel.height);
    } else {
      _drawCandles(canvas, renderOHLC, minY, maxY, chartLeft, pricePanel.top,
          chartW, pricePanel.height);
    }

    for (final e in overlays.entries) {
      _drawSeries(canvas, e.value, e.key.color, minY, maxY, chartLeft,
          pricePanel.top, chartW, pricePanel.height);
    }
    if (vwap != null) {
      _drawSeries(canvas, vwap, Indicator.vwap.color, minY, maxY, chartLeft,
          pricePanel.top, chartW, pricePanel.height);
    }

    if (priceLines.isNotEmpty) {
      _drawPriceLines(canvas, minY, maxY, chartLeft, pricePanel.top, chartW,
          pricePanel.height);
    }
    _drawLastPriceIndicator(canvas, renderOHLC, minY, maxY, chartLeft,
        pricePanel.top, chartW, pricePanel.height);

    if (newsMarkers.isNotEmpty) {
      final filtered = newsMarkers
          .where((m) => m.index >= visibleStart && m.index < visibleEnd)
          .map((m) => NewsMarker(m.index - visibleStart, m.sentimentScore))
          .toList();
      if (filtered.isNotEmpty) {
        _drawNewsMarkers(canvas, ohlc, filtered, minY, maxY, chartLeft,
            pricePanel.top, chartW, pricePanel.height);
      }
    }

    // ── Kullanıcı çizimleri (yatay çizgi / trend / ölçüm) ──
    _drawUserDrawings(
        canvas, renderOHLC.length, minY, maxY, chartLeft, pricePanel, chartW);

    // ── Kalıcı OHLC lejantı (hover yokken son bar) — TradingView üst satırı ──
    if (hoverIndex == null) {
      _drawOhlcLegend(canvas, chartLeft, pricePanel.top);
    }

    // ── RSI paneli ──
    if (rsiPanel != null) {
      _drawRsiPanel(canvas, _slice(s.rsi14), chartLeft, rsiPanel, chartW);
    }
    // ── MACD paneli ──
    if (macdPanel != null) {
      final m = s.macd;
      _drawMacdPanel(canvas, _slice(m.macd), _slice(m.signal), _slice(m.hist),
          chartLeft, macdPanel, chartW);
    }
    // ── Hacim paneli ──
    if (volPanel != null) {
      _drawVolumeBars(canvas, visData, renderOHLC, chartLeft, volPanel.top,
          chartW, volPanel.height);
    }

    // ── Crosshair tüm panelleri kateder ──
    if (hoverIndex != null &&
        hoverIndex! >= visibleStart &&
        hoverIndex! < visibleEnd) {
      final localIdx = hoverIndex! - visibleStart;
      _drawCrosshair(
          canvas,
          localIdx,
          ohlc,
          minY,
          maxY,
          chartLeft,
          pricePanel,
          chartW,
          stackTop,
          xAxisY,
          overlays,
          vwap,
          rsiPanel != null ? _slice(s.rsi14) : null);
    }
  }

  // ── Fiyat üstü seri çizimi (MA/EMA/VWAP) ──
  void _drawSeries(Canvas canvas, List<double?> s, Color color, double minY,
      double maxY, double left, double top, double w, double h) {
    final n = s.length;
    if (n < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    bool started = false;
    for (int i = 0; i < n; i++) {
      final v = s[i];
      if (v == null) continue;
      final x = left + w * (i / (n - 1));
      final y = _mapY(v, minY, maxY, top, h);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawBollinger(
      Canvas canvas,
      List<double?> upper,
      List<double?> lower,
      List<double?>? mid,
      double minY,
      double maxY,
      double left,
      double top,
      double w,
      double h) {
    final n = upper.length;
    if (n < 2) return;
    final color = Indicator.boll.color;
    // Bant arası dolgu
    final fill = Path();
    bool started = false;
    for (int i = 0; i < n; i++) {
      final v = upper[i];
      if (v == null) continue;
      final x = left + w * (i / (n - 1));
      final y = _mapY(v, minY, maxY, top, h);
      if (!started) {
        fill.moveTo(x, y);
        started = true;
      } else {
        fill.lineTo(x, y);
      }
    }
    for (int i = n - 1; i >= 0; i--) {
      final v = lower[i];
      if (v == null) continue;
      final x = left + w * (i / (n - 1));
      fill.lineTo(x, _mapY(v, minY, maxY, top, h));
    }
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.07));
    _drawSeries(canvas, upper, color.withValues(alpha: 0.7), minY, maxY, left,
        top, w, h);
    _drawSeries(canvas, lower, color.withValues(alpha: 0.7), minY, maxY, left,
        top, w, h);
    if (mid != null) {
      _drawSeries(canvas, mid, color.withValues(alpha: 0.45), minY, maxY, left,
          top, w, h);
    }
  }

  // ── RSI alt paneli ──
  void _drawRsiPanel(
      Canvas canvas, List<double?> rsi, double left, _Panel p, double w) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(left, p.top, w, p.height), const Radius.circular(6)),
      Paint()..color = panelBg.withValues(alpha: 0.6),
    );
    // 30 / 50 / 70 kılavuzları
    for (final lvl in [30.0, 50.0, 70.0]) {
      final y = p.top + p.height * (1 - lvl / 100);
      _dashed(canvas, Offset(left, y), Offset(left + w, y),
          gridColor.withValues(alpha: lvl == 50 ? 0.5 : 1));
      _drawText(canvas, lvl.toStringAsFixed(0), Offset(left + w + 4, y - 5),
          color: axisColor, fontSize: 9);
    }
    final n = rsi.length;
    final paint = Paint()
      ..color = Indicator.rsi.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path();
    bool started = false;
    for (int i = 0; i < n; i++) {
      final v = rsi[i];
      if (v == null) continue;
      final x = left + w * (i / (n - 1));
      final y = p.top + p.height * (1 - (v.clamp(0, 100)) / 100);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    _drawText(canvas, 'RSI 14', Offset(left + 4, p.top + 3),
        color: axisColor, fontSize: 9);
  }

  // ── MACD alt paneli ──
  void _drawMacdPanel(Canvas canvas, List<double?> macd, List<double?> signal,
      List<double?> hist, double left, _Panel p, double w) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(left, p.top, w, p.height), const Radius.circular(6)),
      Paint()..color = panelBg.withValues(alpha: 0.6),
    );
    double mn = double.infinity, mx = -double.infinity;
    void inc(List<double?> s) {
      for (final v in s) {
        if (v == null) continue;
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
    }

    inc(macd);
    inc(signal);
    inc(hist);
    if (mn == double.infinity) return;
    final bound = math.max(mx.abs(), mn.abs());
    mn = -bound;
    mx = bound;
    double my(double v) =>
        p.top + p.height * (1 - (v - mn) / (mx - mn == 0 ? 1 : mx - mn));

    final zeroY = my(0);
    _dashed(canvas, Offset(left, zeroY), Offset(left + w, zeroY), gridColor);

    final n = hist.length;
    final slot = w / math.max(1, n);
    final barW = math.max(1.0, slot * 0.6);
    for (int i = 0; i < n; i++) {
      final v = hist[i];
      if (v == null) continue;
      final x = left + slot * (i + 0.5);
      final y = my(v);
      final paint = Paint()
        ..color = (v >= 0 ? upColor : downColor).withValues(alpha: 0.65);
      canvas.drawRect(
          Rect.fromLTRB(x - barW / 2, math.min(y, zeroY), x + barW / 2,
              math.max(y, zeroY)),
          paint);
    }
    _drawPanelLine(canvas, macd, Indicator.macd.color, left, w, my);
    _drawPanelLine(canvas, signal, const Color(_kSignal), left, w, my);
    _drawText(canvas, 'MACD 12,26,9', Offset(left + 4, p.top + 3),
        color: axisColor, fontSize: 9);
  }

  void _drawPanelLine(Canvas canvas, List<double?> s, Color color, double left,
      double w, double Function(double) my) {
    final n = s.length;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path();
    bool started = false;
    for (int i = 0; i < n; i++) {
      final v = s[i];
      if (v == null) continue;
      final x = left + w * (i / (n - 1));
      final y = my(v);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawVolumeBars(
      Canvas canvas,
      List<Map<String, dynamic>> visData,
      List<_Candle> renderOHLC,
      double left,
      double top,
      double w,
      double panelH) {
    final n = visData.length;
    if (n == 0) return;
    double maxVol = 0;
    for (final d in visData) {
      final v = (d['volume'] as num?)?.toDouble() ?? 0;
      if (v > maxVol) maxVol = v;
    }
    if (maxVol <= 0) return;
    final slotW = w / n;
    final barW = math.max(1.5, slotW * 0.7);
    for (int i = 0; i < n; i++) {
      final v = (visData[i]['volume'] as num?)?.toDouble() ?? 0;
      final hh = (v / maxVol) * panelH * 0.92;
      if (hh < 0.5) continue;
      final c = renderOHLC[i];
      final isUp = c.close >= c.open;
      final color = (isUp ? upColor : downColor).withValues(alpha: 0.55);
      final x = left + slotW * (i + 0.5);
      canvas.drawRect(Rect.fromLTWH(x - barW / 2, top + panelH - hh, barW, hh),
          Paint()..color = color);
    }
    _drawText(canvas, 'Vol', Offset(left + 2, top + 2),
        color: axisColor, fontSize: 8);
    _drawText(canvas, _fmtCompact(maxVol), Offset(left + w - 4, top + 2),
        color: axisColor, fontSize: 8, align: TextAlign.right);
  }

  String _fmtCompact(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  void _drawGrid(Canvas canvas, double minY, double maxY, double left,
      double top, double w, double h) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const lineCount = 4;
    for (int i = 0; i <= lineCount; i++) {
      final y = top + h * (i / lineCount);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), paint);
      final price = _priceAtY(y, minY, maxY, top, h);
      _drawText(
          canvas, '$currency${_fmtPrice(price)}', Offset(left + w + 4, y - 5),
          align: TextAlign.left, color: axisColor, fontSize: 10);
    }
  }

  void _drawXLabels(Canvas canvas, List<Map<String, dynamic>> visData,
      double left, double y, double w) {
    const count = 5;
    final n = visData.length;
    for (int i = 0; i <= count; i++) {
      final idx = ((n - 1) * (i / count)).round().clamp(0, n - 1);
      final dateStr = (visData[idx]['date'] as String?) ?? '';
      String label;
      if (dateStr.length >= 16 && dateStr.contains(' ')) {
        label = '${dateStr.substring(8, 10)} ${dateStr.substring(11, 16)}';
      } else if (dateStr.length >= 10) {
        label = dateStr.substring(5);
      } else {
        label = dateStr;
      }
      final x = left + w * (i / count);
      _drawText(canvas, label, Offset(x, y + 4),
          align: TextAlign.center, color: axisColor, fontSize: 9);
    }
  }

  void _drawLine(Canvas canvas, List<_Candle> ohlc, double minY, double maxY,
      double left, double top, double w, double h) {
    final n = ohlc.length;
    if (n < 2) return;
    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < n; i++) {
      final x = left + w * (i / (n - 1));
      final y = _mapY(ohlc[i].close, minY, maxY, top, h);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, top + h);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(left + w, top + h);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.18),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(left, top, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawCandles(Canvas canvas, List<_Candle> ohlc, double minY, double maxY,
      double left, double top, double w, double h) {
    final n = ohlc.length;
    if (n == 0) return;
    final slotWidth = w / n;
    // TradingView-tarzı: gövde slot'un ~%72'si (aralarda boşluk),
    // 1–14px arası. Düz solid renk + ince butt fitil = net, ezilmez.
    final candleWidth = math.max(1.0, math.min(14.0, slotWidth * 0.72));
    final wickWidth = slotWidth < 3 ? 1.0 : math.min(1.6, slotWidth * 0.14);
    final wickPaint = Paint()
      ..strokeWidth = wickWidth
      ..strokeCap = StrokeCap.butt;
    final bodyPaint = Paint()..isAntiAlias = slotWidth > 2.5;
    final radius = candleWidth >= 5 ? 1.0 : 0.0;

    for (int i = 0; i < n; i++) {
      final c = ohlc[i];
      final isUp = c.close >= c.open;
      final color = isUp ? upColor : downColor;
      // Yarım piksel hizalama → keskin kenar
      final x = (left + slotWidth * (i + 0.5)).roundToDouble() - 0.5;
      final yHigh = _mapY(c.high, minY, maxY, top, h);
      final yLow = _mapY(c.low, minY, maxY, top, h);
      final yOpen = _mapY(c.open, minY, maxY, top, h);
      final yClose = _mapY(c.close, minY, maxY, top, h);

      wickPaint.color = color;
      canvas.drawLine(Offset(x, yHigh), Offset(x, yLow), wickPaint);

      final bodyTop = math.min(yOpen, yClose);
      // Doji → en az 1px ince çizgi, kaybolmasın.
      final bodyHeight = math.max((yOpen - yClose).abs(), 1.0);
      bodyPaint.color = color;
      final bodyRect =
          Rect.fromLTWH(x - candleWidth / 2, bodyTop, candleWidth, bodyHeight);
      if (radius > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(bodyRect, Radius.circular(radius)),
            bodyPaint);
      } else {
        canvas.drawRect(bodyRect, bodyPaint);
      }
    }
  }

  void _drawLastPriceIndicator(Canvas canvas, List<_Candle> renderOHLC,
      double minY, double maxY, double left, double top, double w, double h) {
    if (renderOHLC.isEmpty) return;
    final lastCandle = renderOHLC.last;
    final close = lastCandle.close;
    final isUp = lastCandle.close >= lastCandle.open;
    final y = _mapY(close, minY, maxY, top, h);
    final color = isUp ? upColor : downColor;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    const dashW = 4.0;
    const gapW = 3.0;
    var x = left;
    while (x < left + w) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + dashW, left + w), y), paint);
      x += dashW + gapW;
    }
    final label = '$currency${_fmtPrice(close)}';
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    final boxW = tp.width + 8;
    final boxX = left + w + 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(boxX, y - 8, boxW, 16), const Radius.circular(3)),
        Paint()..color = color);
    tp.paint(canvas, Offset(boxX + 4, y - 7));
  }

  void _drawPriceLines(Canvas canvas, double minY, double maxY, double left,
      double top, double w, double h) {
    for (final pl in priceLines) {
      final y = _mapY(pl.price, minY, maxY, top, h);
      canvas.drawRect(Rect.fromLTWH(left, y - 6, w, 12),
          Paint()..color = pl.color.withValues(alpha: 0.08));
      final linePaint = Paint()
        ..color = pl.color
        ..strokeWidth = 1.4;
      const dashW = 6.0;
      const gapW = 4.0;
      var x = left;
      while (x < left + w) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + dashW, left + w), y), linePaint);
        x += dashW + gapW;
      }
      final label = '${pl.label}  $currency${_fmtPrice(pl.price)}';
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: pl.color, fontSize: 10, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final boxW = tp.width + 10;
      final boxX = left + w - boxW;
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(boxX, y - 9, boxW, 18), const Radius.circular(4));
      canvas.drawRRect(rect, Paint()..color = panelBg);
      canvas.drawRRect(
          rect,
          Paint()
            ..color = pl.color.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      tp.paint(canvas, Offset(boxX + 5, y - 7));
    }
  }

  void _drawNewsMarkers(
      Canvas canvas,
      List<_Candle> ohlc,
      List<NewsMarker> markers,
      double minY,
      double maxY,
      double left,
      double top,
      double w,
      double h) {
    final n = ohlc.length;
    if (n == 0) return;
    for (final m in markers) {
      if (m.index < 0 || m.index >= n) continue;
      final x = left + w * (m.index / (n - 1));
      final y = _mapY(ohlc[m.index].close, minY, maxY, top, h) - 10;
      Color color;
      if (m.sentimentScore > 0.05) {
        color = _kGreen;
      } else if (m.sentimentScore < -0.05) {
        color = _kRedC;
      } else {
        color = axisColor;
      }
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = color);
      canvas.drawCircle(
          Offset(x, y),
          4.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  void _drawCrosshair(
      Canvas canvas,
      int idx,
      List<_Candle> origOHLC,
      double minY,
      double maxY,
      double left,
      _Panel price,
      double w,
      double stackTop,
      double stackBottom,
      Map<Indicator, List<double?>> overlays,
      List<double?>? vwap,
      List<double?>? rsi) {
    final n = origOHLC.length;
    if (n == 0) return;
    final x = type == ChartType.line
        ? left + w * (idx / math.max(1, n - 1))
        : left + (w / n) * (idx + 0.5);
    // Dikey çizgi tüm panel yığınını kateder
    _dashed(canvas, Offset(x, stackTop), Offset(x, stackBottom),
        axisColor.withValues(alpha: 0.5));

    final hoverY = hoverPos?.dy.clamp(price.top, price.bottom);
    if (hoverY != null) {
      _dashed(canvas, Offset(left, hoverY), Offset(left + w, hoverY),
          axisColor.withValues(alpha: 0.5));
      final hoverPrice = _priceAtY(hoverY, minY, maxY, price.top, price.height);
      final tp = TextPainter(
        text: TextSpan(
            text: '$currency${_fmtPrice(hoverPrice)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final boxX = left + w + 2;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(boxX, hoverY - 8, tp.width + 8, 16),
              const Radius.circular(3)),
          Paint()..color = Colors.blueGrey[700]!);
      tp.paint(canvas, Offset(boxX + 4, hoverY - 7));
    }

    final dateStr = (data[visibleStart + idx]['date'] as String?) ?? '';
    final dtp = TextPainter(
      text: TextSpan(
          text: dateStr,
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dateBoxW = dtp.width + 10;
    final dateBoxX = (x - dateBoxW / 2).clamp(left, left + w - dateBoxW);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(dateBoxX, stackBottom + 2, dateBoxW, 16),
            const Radius.circular(3)),
        Paint()..color = Colors.blueGrey[700]!);
    dtp.paint(canvas, Offset(dateBoxX + 5, stackBottom + 3));

    if (hoverY != null) {
      final candleY =
          _mapY(origOHLC[idx].close, minY, maxY, price.top, price.height);
      if ((candleY - hoverY).abs() < 30) {
        canvas.drawCircle(Offset(x, candleY), 3.5, Paint()..color = lineColor);
      }
    }

    // OHLC + aktif gösterge readout kutusu
    final c = origOHLC[idx];
    final lines = <String>[dateStr];
    if (type == ChartType.line) {
      lines.add('Kapanış: $currency${_fmtPrice(c.close)}');
    } else {
      lines.add('A: $currency${_fmtPrice(c.open)}');
      lines.add('Y: $currency${_fmtPrice(c.high)}');
      lines.add('D: $currency${_fmtPrice(c.low)}');
      lines.add('K: $currency${_fmtPrice(c.close)}');
    }
    for (final e in overlays.entries) {
      final v = idx < e.value.length ? e.value[idx] : null;
      if (v != null) {
        lines.add('${e.key.label}: $currency${_fmtPrice(v)}');
      }
    }
    if (vwap != null && idx < vwap.length && vwap[idx] != null) {
      lines.add('VWAP: $currency${_fmtPrice(vwap[idx]!)}');
    }
    if (rsi != null && idx < rsi.length && rsi[idx] != null) {
      lines.add('RSI: ${rsi[idx]!.toStringAsFixed(1)}');
    }

    const lineH = 13.0;
    const padding = 8.0;
    const boxWidth = 168.0;
    final boxHeight = lines.length * lineH + padding * 2;
    var bx = left + 4;
    final by = price.top + 4;
    if (hoverPos != null && hoverPos!.dx < bx + boxWidth + 20) {
      bx = left + w - boxWidth - 4;
    }
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, boxWidth, boxHeight), const Radius.circular(6));
    canvas.drawRRect(rect, Paint()..color = const Color(0xCC1E1E1E));
    canvas.drawRRect(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    for (int i = 0; i < lines.length; i++) {
      _drawText(
          canvas, lines[i], Offset(bx + padding, by + padding + i * lineH),
          color: i == 0 ? const Color(0xFFB0BEC5) : Colors.white, fontSize: 10);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashW = 4.0;
    const gapW = 3.0;
    final total = (b - a).distance;
    final dir = (b - a) / (total == 0 ? 1 : total);
    double traveled = 0;
    while (traveled < total) {
      final s = a + dir * traveled;
      final e = a + dir * math.min(traveled + dashW, total);
      canvas.drawLine(s, e, paint);
      traveled += dashW + gapW;
    }
  }

  // ─── Yardımcılar ─────────────────────────────────────────────────

  List<_Candle> _extractOHLCFrom(List<Map<String, dynamic>> src) {
    return src.map((d) {
      final close = (d['close'] as num?)?.toDouble() ?? 0;
      return _Candle(
        open: (d['open'] as num?)?.toDouble() ?? close,
        high: (d['high'] as num?)?.toDouble() ?? close,
        low: (d['low'] as num?)?.toDouble() ?? close,
        close: close,
      );
    }).toList();
  }

  List<_Candle> _toHeikinAshi(List<_Candle> input) {
    if (input.isEmpty) return [];
    final result = <_Candle>[];
    _Candle? prev;
    for (final c in input) {
      final haClose = (c.open + c.high + c.low + c.close) / 4;
      final haOpen =
          prev == null ? (c.open + c.close) / 2 : (prev.open + prev.close) / 2;
      final haHigh = math.max(c.high, math.max(haOpen, haClose));
      final haLow = math.min(c.low, math.min(haOpen, haClose));
      final ha =
          _Candle(open: haOpen, high: haHigh, low: haLow, close: haClose);
      result.add(ha);
      prev = ha;
    }
    return result;
  }

  // Log skala: dönüşüm + ters dönüşüm. minY/maxY ham fiyat sınırları kalır.
  double _sc(double v) => logScale ? math.log(math.max(v, 1e-9)) : v;
  double _unsc(double s) => logScale ? math.exp(s) : s;

  double _mapY(double v, double minY, double maxY, double top, double h) {
    final a = _sc(minY), b = _sc(maxY);
    final t = (b - a) == 0 ? 0.0 : (_sc(v) - a) / (b - a);
    return top + h * (1 - t);
  }

  /// Ekran y'sinden fiyat (grid etiketi / crosshair için ters dönüşüm).
  double _priceAtY(double y, double minY, double maxY, double top, double h) {
    final a = _sc(minY), b = _sc(maxY);
    final t = 1 - (y - top) / h;
    return _unsc(a + t * (b - a));
  }

  double _xAny(int absIdx, double left, double w, int visN) {
    final i = absIdx - visibleStart;
    return type == ChartType.line
        ? left + w * (i / math.max(1, visN - 1))
        : left + (w / visN) * (i + 0.5);
  }

  /// Sürüklenebilir tutamaç noktası (TradingView gibi yakalanır).
  void _handle(Canvas canvas, Offset o, {bool active = false}) {
    final r = active ? 7.0 : 5.0;
    canvas.drawCircle(o, r, Paint()..color = panelBg);
    canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawCircle(o, 2, Paint()..color = accentColor);
  }

  bool _isEditing(ChartTool k, int i, int e) =>
      editing != null &&
      editing!.kind == k &&
      editing!.index == i &&
      editing!.end == e;

  /// Yatay destek/direnç, trend çizgileri ve ölçüm aracı.
  void _drawUserDrawings(Canvas canvas, int visN, double minY, double maxY,
      double left, _Panel p, double w) {
    final clip = Rect.fromLTWH(left, p.top, w, p.height);

    // Yatay çizgiler (S/R) — kesik, sol kenarda fiyat rozeti, sağda tutamaç.
    for (int i = 0; i < hLines.length; i++) {
      final price = hLines[i];
      if (price < minY || price > maxY) continue;
      final y = _mapY(price, minY, maxY, p.top, p.height);
      _dashed(canvas, Offset(left, y), Offset(left + w, y), accentColor);
      final tp = TextPainter(
        text: TextSpan(
            text: _fmtPrice(price),
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(left + 2, y - 8, tp.width + 8, 15),
              const Radius.circular(3)),
          Paint()..color = accentColor);
      tp.paint(canvas, Offset(left + 6, y - 7));
      _handle(canvas, Offset(left + w - 16, y),
          active: _isEditing(ChartTool.hline, i, 0));
    }

    canvas.save();
    canvas.clipRect(clip);

    // Trend çizgileri
    final tPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < trends.length; i++) {
      final t = trends[i];
      final ax = _xAny(t.$1, left, w, visN);
      final ay = _mapY(t.$2, minY, maxY, p.top, p.height);
      final bx = _xAny(t.$3, left, w, visN);
      final by = _mapY(t.$4, minY, maxY, p.top, p.height);
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), tPaint);
      _handle(canvas, Offset(ax, ay),
          active: _isEditing(ChartTool.trend, i, 0));
      _handle(canvas, Offset(bx, by),
          active: _isEditing(ChartTool.trend, i, 1));
    }

    // Ölçüm aracı
    if (measA != null) {
      final a = measA!;
      final ax = _xAny(a.$1, left, w, visN);
      final ay = _mapY(a.$2, minY, maxY, p.top, p.height);
      if (measB != null) {
        final b = measB!;
        final bx = _xAny(b.$1, left, w, visN);
        final by = _mapY(b.$2, minY, maxY, p.top, p.height);
        final up = b.$2 >= a.$2;
        final col = up ? _kGreen : _kRedC;
        canvas.drawRect(
            Rect.fromLTRB(math.min(ax, bx), math.min(ay, by), math.max(ax, bx),
                math.max(ay, by)),
            Paint()..color = col.withValues(alpha: 0.10));
        canvas.drawLine(
            Offset(ax, ay),
            Offset(bx, by),
            Paint()
              ..color = col
              ..strokeWidth = 1.6);
        _handle(canvas, Offset(ax, ay),
            active: _isEditing(ChartTool.measure, 0, 0));
        _handle(canvas, Offset(bx, by),
            active: _isEditing(ChartTool.measure, 0, 1));
        final dPrice = b.$2 - a.$2;
        final dPct = a.$2 == 0 ? 0.0 : dPrice / a.$2 * 100;
        final bars = (b.$1 - a.$1).abs();
        final label = '${dPrice >= 0 ? '+' : ''}${_fmtPrice(dPrice)}  '
            '${formatPctSigned(dPct, decimals: 2)}%  ·  $bars bar';
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = ((ax + bx) / 2 - tp.width / 2 - 6)
            .clamp(left, left + w - tp.width - 12);
        final ly = math.min(ay, by) - 24;
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(lx, ly, tp.width + 12, 18),
                const Radius.circular(4)),
            Paint()..color = col);
        tp.paint(canvas, Offset(lx + 6, ly + 3));
      } else {
        _handle(canvas, Offset(ax, ay),
            active: _isEditing(ChartTool.measure, 0, 0));
      }
    }

    // Dikdörtgen / bölge
    for (int ri = 0; ri < rects.length; ri++) {
      final r = rects[ri];
      final ax = _xAny(r.$1, left, w, visN);
      final ay = _mapY(r.$2, minY, maxY, p.top, p.height);
      final bx = _xAny(r.$3, left, w, visN);
      final by = _mapY(r.$4, minY, maxY, p.top, p.height);
      final rect = Rect.fromLTRB(math.min(ax, bx), math.min(ay, by),
          math.max(ax, bx), math.max(ay, by));
      canvas.drawRect(
          rect, Paint()..color = accentColor.withValues(alpha: 0.12));
      canvas.drawRect(
          rect,
          Paint()
            ..color = accentColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
      _handle(canvas, Offset(ax, ay),
          active: _isEditing(ChartTool.rect, ri, 0));
      _handle(canvas, Offset(bx, by),
          active: _isEditing(ChartTool.rect, ri, 1));
    }

    // Fibonacci retracement (0–1 arası klasik seviyeler)
    const fibLevels = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];
    for (int fi = 0; fi < fibs.length; fi++) {
      final f = fibs[fi];
      final ax = _xAny(f.$1, left, w, visN);
      final bx = _xAny(f.$3, left, w, visN);
      final lo = math.min(ax, bx);
      final hi = math.max(ax, bx);
      final pHigh = math.max(f.$2, f.$4);
      final pLow = math.min(f.$2, f.$4);
      for (final lv in fibLevels) {
        final price = pHigh - (pHigh - pLow) * lv;
        final y = _mapY(price, minY, maxY, p.top, p.height);
        _dashed(canvas, Offset(lo, y), Offset(hi, y),
            accentColor.withValues(alpha: 0.7));
        _drawText(
            canvas,
            '${formatPct(lv * 100, decimals: 1)}%  ${_fmtPrice(price)}',
            Offset(lo + 4, y - 12),
            color: accentColor,
            fontSize: 9);
      }
      final fay = _mapY(f.$2, minY, maxY, p.top, p.height);
      final fby = _mapY(f.$4, minY, maxY, p.top, p.height);
      canvas.drawLine(
          Offset(ax, fay),
          Offset(bx, fby),
          Paint()
            ..color = accentColor.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      _handle(canvas, Offset(ax, fay),
          active: _isEditing(ChartTool.fib, fi, 0));
      _handle(canvas, Offset(bx, fby),
          active: _isEditing(ChartTool.fib, fi, 1));
    }

    // Yatay ışın — başlangıç noktasından SAĞA kesik çizgi + fiyat rozeti
    for (int i = 0; i < hrays.length; i++) {
      final r = hrays[i];
      if (r.$2 < minY || r.$2 > maxY) continue;
      final sx = _xAny(r.$1, left, w, visN).clamp(left, left + w);
      final y = _mapY(r.$2, minY, maxY, p.top, p.height);
      _dashed(canvas, Offset(sx, y), Offset(left + w, y), accentColor);
      final tp = TextPainter(
        text: TextSpan(
            text: _fmtPrice(r.$2),
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(sx + 2, y - 8, tp.width + 8, 15),
              const Radius.circular(3)),
          Paint()..color = accentColor);
      tp.paint(canvas, Offset(sx + 6, y - 7));
      _handle(canvas, Offset(sx, y), active: _isEditing(ChartTool.hray, i, 0));
    }

    // Dikey çizgi — tam panel yüksekliği
    for (int i = 0; i < vlines.length; i++) {
      final x = _xAny(vlines[i], left, w, visN);
      if (x < left - 1 || x > left + w + 1) continue;
      _dashed(canvas, Offset(x, p.top), Offset(x, p.top + p.height),
          accentColor.withValues(alpha: 0.85));
      _handle(canvas, Offset(x, p.top + 14),
          active: _isEditing(ChartTool.vline, i, 0));
    }

    // Metin / Not — anchor noktasında arka planlı etiket + bağlantı noktası
    for (int i = 0; i < notes.length; i++) {
      final nt = notes[i];
      final x = _xAny(nt.$1, left, w, visN);
      final y = _mapY(nt.$2, minY, maxY, p.top, p.height);
      final tp = TextPainter(
        text: TextSpan(
            text: nt.$3,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);
      final bx = (x + 8).clamp(left, left + w - tp.width - 12);
      final by = (y - 9).clamp(p.top, p.top + p.height - 18);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, tp.width + 12, 18),
              const Radius.circular(4)),
          Paint()..color = accentColor);
      tp.paint(canvas, Offset(bx + 6, by + 3));
      _handle(canvas, Offset(x, y), active: _isEditing(ChartTool.note, i, 0));
    }

    // Paralel kanal — iki paralel çizgi + arası dolgu + A/B/offset tutamaçları
    final chPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < channels.length; i++) {
      final ch = channels[i];
      final ax = _xAny(ch.$1, left, w, visN);
      final ay = _mapY(ch.$2, minY, maxY, p.top, p.height);
      final bx = _xAny(ch.$3, left, w, visN);
      final by = _mapY(ch.$4, minY, maxY, p.top, p.height);
      final ay2 = _mapY(ch.$2 + ch.$5, minY, maxY, p.top, p.height);
      final by2 = _mapY(ch.$4 + ch.$5, minY, maxY, p.top, p.height);
      final fill = Path()
        ..moveTo(ax, ay)
        ..lineTo(bx, by)
        ..lineTo(bx, by2)
        ..lineTo(ax, ay2)
        ..close();
      canvas.drawPath(
          fill, Paint()..color = accentColor.withValues(alpha: 0.08));
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), chPaint);
      canvas.drawLine(Offset(ax, ay2), Offset(bx, by2), chPaint);
      _handle(canvas, Offset(ax, ay),
          active: _isEditing(ChartTool.channel, i, 0));
      _handle(canvas, Offset(bx, by),
          active: _isEditing(ChartTool.channel, i, 1));
      _handle(canvas, Offset(ax, ay2),
          active: _isEditing(ChartTool.channel, i, 2));
    }
    // Kanal ana çizgisi konduktan sonra offset beklenirken önizleme
    if (pendChannel != null) {
      final ch = pendChannel!;
      final ax = _xAny(ch.$1, left, w, visN);
      final ay = _mapY(ch.$2, minY, maxY, p.top, p.height);
      final bx = _xAny(ch.$3, left, w, visN);
      final by = _mapY(ch.$4, minY, maxY, p.top, p.height);
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), chPaint);
      canvas.drawCircle(Offset(ax, ay), 3, Paint()..color = accentColor);
      canvas.drawCircle(Offset(bx, by), 3, Paint()..color = accentColor);
    }

    // Pozisyon (Long/Short R:R) — yeşil ödül zonu + kırmızı risk zonu + R:R
    for (int i = 0; i < positions.length; i++) {
      final ps = positions[i];
      final ax = _xAny(ps.$1, left, w, visN);
      final bx = _xAny(ps.$3, left, w, visN);
      final lo = math.min(ax, bx), hi = math.max(ax, bx);
      final ey = _mapY(ps.$2, minY, maxY, p.top, p.height);
      final ty = _mapY(ps.$4, minY, maxY, p.top, p.height);
      final sy = _mapY(ps.$5, minY, maxY, p.top, p.height);
      canvas.drawRect(Rect.fromLTRB(lo, math.min(ey, ty), hi, math.max(ey, ty)),
          Paint()..color = _kGreen.withValues(alpha: 0.14)); // ödül
      canvas.drawRect(Rect.fromLTRB(lo, math.min(ey, sy), hi, math.max(ey, sy)),
          Paint()..color = _kRedC.withValues(alpha: 0.14)); // risk
      canvas.drawLine(
          Offset(lo, ey),
          Offset(hi, ey),
          Paint()
            ..color = accentColor
            ..strokeWidth = 1.4);
      canvas.drawLine(
          Offset(lo, ty),
          Offset(hi, ty),
          Paint()
            ..color = _kGreen
            ..strokeWidth = 1.2);
      canvas.drawLine(
          Offset(lo, sy),
          Offset(hi, sy),
          Paint()
            ..color = _kRedC
            ..strokeWidth = 1.2);
      final risk = (ps.$2 - ps.$5).abs();
      final reward = (ps.$4 - ps.$2).abs();
      final rr = risk == 0 ? 0.0 : reward / risk;
      _drawText(
          canvas,
          'R:R ${rr.toStringAsFixed(2)}  ·  +${_fmtPrice(reward)} / -${_fmtPrice(risk)}',
          Offset(lo + 4, math.min(ty, sy) - 13),
          color: accentColor,
          fontSize: 10);
      _handle(canvas, Offset(ax, ey),
          active: _isEditing(ChartTool.position, i, 0));
      _handle(canvas, Offset(bx, ty),
          active: _isEditing(ChartTool.position, i, 1));
      _handle(canvas, Offset(bx, sy),
          active: _isEditing(ChartTool.position, i, 2));
    }

    // Bekleyen ilk nokta (2-noktalı araçlar) — geri bildirim
    if (pendStart != null) {
      final px = _xAny(pendStart!.$1, left, w, visN);
      final py = _mapY(pendStart!.$2, minY, maxY, p.top, p.height);
      canvas.drawCircle(Offset(px, py), 5,
          Paint()..color = accentColor.withValues(alpha: 0.35));
      canvas.drawCircle(Offset(px, py), 3, Paint()..color = accentColor);
    }
    canvas.restore();
  }

  /// Hover yokken üst-sol kalıcı OHLC + günlük değişim satırı.
  void _drawOhlcLegend(Canvas canvas, double left, double top) {
    if (visibleEnd < 1) return;
    final last = data[visibleEnd - 1];
    final o = (last['open'] as num?)?.toDouble() ?? 0;
    final h = (last['high'] as num?)?.toDouble() ?? 0;
    final l = (last['low'] as num?)?.toDouble() ?? 0;
    final cl = (last['close'] as num?)?.toDouble() ?? 0;
    final prev = visibleEnd >= 2
        ? (data[visibleEnd - 2]['close'] as num?)?.toDouble() ?? cl
        : cl;
    final chg = prev == 0 ? 0.0 : (cl - prev) / prev * 100;
    final base =
        'O ${_fmtPrice(o)}   Y ${_fmtPrice(h)}   D ${_fmtPrice(l)}   K ${_fmtPrice(cl)}   ';
    _drawText(canvas, base, Offset(left + 4, top + 3),
        color: axisColor, fontSize: 10);
    final bp = TextPainter(
      text: TextSpan(text: base, style: const TextStyle(fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    _drawText(canvas, '${formatPctSigned(chg, decimals: 2)}%',
        Offset(left + 4 + bp.width, top + 3),
        color: chg >= 0 ? _kGreen : _kRedC, fontSize: 10);
  }

  String _fmtPrice(double v) {
    if (v.abs() >= 1000) return v.toStringAsFixed(0);
    if (v.abs() >= 10) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }

  void _drawText(Canvas canvas, String text, Offset pos,
      {Color color = Colors.white,
      double fontSize = 11,
      TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(color: color, fontSize: fontSize)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: 220);
    final dx = align == TextAlign.right
        ? pos.dx - tp.width
        : align == TextAlign.center
            ? pos.dx - tp.width / 2
            : pos.dx;
    tp.paint(canvas, Offset(dx, pos.dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) {
    return old.type != type ||
        old.active.length != active.length ||
        old.hoverIndex != hoverIndex ||
        old.hoverPos != hoverPos ||
        old.visibleStart != visibleStart ||
        old.visibleEnd != visibleEnd ||
        old.data.length != data.length ||
        old.priceLines.length != priceLines.length ||
        old.gridColor != gridColor ||
        old.axisColor != axisColor ||
        old.lineColor != lineColor ||
        old.tool != tool ||
        old.hLines.length != hLines.length ||
        old.trends.length != trends.length ||
        old.measA != measA ||
        old.measB != measB ||
        old.fibs.length != fibs.length ||
        old.rects.length != rects.length ||
        old.hrays.length != hrays.length ||
        old.vlines.length != vlines.length ||
        old.notes.length != notes.length ||
        old.channels.length != channels.length ||
        old.pendChannel != pendChannel ||
        old.positions.length != positions.length ||
        old.pendStart != pendStart ||
        old.logScale != logScale ||
        old.priceScale != priceScale ||
        old.priceOffset != priceOffset ||
        old.upColor != upColor ||
        old.downColor != downColor ||
        old.editing != editing ||
        // Çizim listeleri YERİNDE mutate edilir (aynı referans, aynı uzunluk)
        // → sürükleyerek düzenlerken yalnız uzunluk/referans kontrolü repaint'i
        // ATLIYORDU (kutu sadece bırakınca hareket ediyordu). Aktif düzenlemede
        // her karede yeniden çiz (canlı önizleme).
        editing != null;
  }
}

class _Candle {
  final double open;
  final double high;
  final double low;
  final double close;
  const _Candle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

/// Full-seri kolonlar + tüm indikatörler — `data` başına BİR kez hesaplanır.
/// `_PriceChartState` bunu data değişince memo'lar; `_ChartPainter` yalnız
/// görünür dilimi slice eder. Hover/zoom/pan paint'i tetiklese de ağır
/// indikatör matematiği (SMA200, Bollinger, VWAP, RSI, MACD) tekrar
/// çalışmaz → grafik akıcı kalır.
class _SeriesCache {
  final List<double> closes, highs, lows, vols;
  final List<double?> sma20, sma50, sma200, ema20, vwap, rsi14;
  final ({List<double?> mid, List<double?> upper, List<double?> lower}) boll;
  final ({List<double?> macd, List<double?> signal, List<double?> hist}) macd;

  _SeriesCache._({
    required this.closes,
    required this.highs,
    required this.lows,
    required this.vols,
    required this.sma20,
    required this.sma50,
    required this.sma200,
    required this.ema20,
    required this.vwap,
    required this.rsi14,
    required this.boll,
    required this.macd,
  });

  factory _SeriesCache.from(List<Map<String, dynamic>> data) {
    List<double> col(String k) =>
        data.map((d) => (d[k] as num?)?.toDouble() ?? 0).toList();
    final closes = col('close');
    final highs = col('high');
    final lows = col('low');
    final vols = col('volume');
    return _SeriesCache._(
      closes: closes,
      highs: highs,
      lows: lows,
      vols: vols,
      sma20: Indicators.sma(closes, 20),
      sma50: Indicators.sma(closes, 50),
      sma200: Indicators.sma(closes, 200),
      ema20: Indicators.ema(closes, 20),
      vwap: Indicators.vwap(highs, lows, closes, vols),
      rsi14: Indicators.rsi(closes, 14),
      boll: Indicators.bollinger(closes, 20, 2),
      macd: Indicators.macd(closes),
    );
  }
}
