import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/money.dart';

/// Genel amaçlı ağırlık donut'u — Hisseler / Sektör / Borsa dağılımlarının
/// HEPSİ bunu kullanır (tek tasarım kaynağı). Yandan lider-çizgili "AD %"
/// etiketleri + ortada canlı detay (üzerine gelince ad · % · ₺) + ızgara
/// lejant.
///
/// ⚠️ TASARIM (churn'den ders): etiketler/merkez metni canvas'a ÇİZİLMİYOR;
/// gerçek `Text` widget'ı olarak `Stack`/`Positioned` ile yerleştirilir.
/// Painter sadece halka + dilim + lider çizgi + nokta çizer. Hover için
/// `Listener.onPointerHover` (MouseRegion'ın MouseTracker'ı test/raster
/// pipeline'ını asıyordu). Tek geometri kaynağı: `_layout()`.
class AllocationDonut extends StatefulWidget {
  /// Çizilecek bölümler. Sıralı olması gerekmez (içeride büyükten küçüğe
  /// sıralanır); değer ₺ (veya tutarlı tek birim) olmalı.
  final List<({String label, double value})> items;

  /// Merkezdeki "TOPLAM" altında gösterilecek birim ("varlık"/"sektör"/"borsa").
  final String centerUnit;

  /// Dilim etiketi → o dilimin İÇİNDEKİ kalemler. Verilen bir dilime
  /// dokununca donut AYNI tasarımla o dilimin içini gösterir; merkeze
  /// dokunmak geri döner. "Diğer" gibi toplayıcı dilimlerin içeriğini
  /// görünür kılmak için. Boş bırakılırsa (Hisseler/Borsa) davranış
  /// birebir eskisi gibi kalır — tıklama yalnız vurgular.
  final Map<String, List<({String label, double value})>> breakdowns;

  /// [breakdowns] ile açılan alt görünümde merkezdeki birim ("varlık").
  final String memberUnit;

  const AllocationDonut({
    super.key,
    required this.items,
    required this.centerUnit,
    this.breakdowns = const {},
    this.memberUnit = 'varlık',
  });

  // Ayırt edilebilir, desature ama elit palet — geniş hue+parlaklık.
  static const palette = [
    Color(0xFFC9A572), // gold (brand)
    Color(0xFF6E93C4), // azure
    Color(0xFF6FB0A0), // teal-green
    Color(0xFFBE82B6), // orchid
    Color(0xFFD09A5E), // amber clay
    Color(0xFF8E8FCB), // periwinkle
    Color(0xFF7FB36B), // leaf
    Color(0xFFCC8576), // terracotta
    Color(0xFF5FA2B8), // cyan
    Color(0xFFB0A95F), // olive
    Color(0xFF9B7FC0), // violet
    Color(0xFFCB87A0), // rose
    Color(0xFF6FA38C), // sage
    Color(0xFFAAB0BE), // cool grey
  ];

  // <%0.6 dilim çizilir ama etiketlenmez (lejantta zaten var).
  static const _labelMinPct = 0.6;

  @override
  State<AllocationDonut> createState() => _AllocationDonutState();
}

class _AllocationDonutState extends State<AllocationDonut> {
  int? _hovered;

  /// İçine girilmiş dilimin etiketi (null = üst seviye).
  String? _drill;

  Offset _center = Offset.zero;
  double _innerR = 0, _outerR = 0;
  List<double> _pcts = const [];
  List<String> _labels = const [];

  void _setHover(int? i) {
    if (_hovered != i) setState(() => _hovered = i);
  }

  /// Noktanın hangi dilime düştüğü; halka dışındaysa null.
  int? _sliceAt(Offset local) {
    final d = local - _center;
    final dist = d.distance;
    if (dist < _innerR - 8 || dist > _outerR + 8) return null;
    var rel = math.atan2(d.dy, d.dx) - (-math.pi / 2);
    rel %= 2 * math.pi;
    if (rel < 0) rel += 2 * math.pi;
    double acc = 0;
    for (int i = 0; i < _pcts.length; i++) {
      final seg = _pcts[i] / 100 * 2 * math.pi;
      if (rel >= acc && rel < acc + seg) return i;
      acc += seg;
    }
    return null;
  }

  void _hoverAt(Offset local) => _setHover(_sliceAt(local));

  /// Alt kırılımı OLAN bir dilime dokunmak içeri girer; merkeze dokunmak
  /// geri döner. Kırılımı olmayan dilimlerde eski davranış (vurgula).
  void _tapAt(Offset local) {
    final open = _drill != null && widget.breakdowns[_drill] != null;
    if (open && (local - _center).distance < _innerR) {
      setState(() {
        _drill = null;
        _hovered = null;
      });
      return;
    }
    final i = _sliceAt(local);
    if (i == null) {
      _setHover(null);
      return;
    }
    if (!open && i < _labels.length) {
      final sub = widget.breakdowns[_labels[i]];
      if (sub != null && sub.length > 1) {
        setState(() {
          _drill = _labels[i];
          _hovered = null;
        });
        return;
      }
    }
    _setHover(i);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);

    // İçine girilmiş dilim varsa onun kalemleri çizilir — AYNI donut, aynı
    // palet, aynı yerleşim; yalnız veri değişir.
    // Veri yenilenip o dilim kaybolduysa (ör. "Diğer" artık boş) sessizce üst
    // seviyeye dön — yoksa merkez var olmayan bir dilimin adını gösterirdi.
    final drilled = _drill != null ? widget.breakdowns[_drill] : null;
    final inDrill = drilled != null;
    final source = drilled ?? widget.items;
    final rows = [...source]..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold<double>(0, (s, r) => s + r.value);
    if (rows.isEmpty || total <= 0) return const SizedBox.shrink();

    final pcts = [for (final r in rows) r.value / total * 100];
    final labels = [for (final r in rows) r.label];
    _pcts = pcts;
    _labels = labels;
    final hv = _hovered != null && _hovered! < rows.length ? _hovered : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (ctx, cons) {
              final w = cons.maxWidth.isFinite ? cons.maxWidth : 360.0;
              final lab = _layout(w, pcts, labels);
              _center = lab.center;
              _outerR = lab.ringR + lab.thickness / 2;
              _innerR = lab.ringR - lab.thickness / 2;
              return Listener(
                onPointerHover: (e) => _hoverAt(e.localPosition),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => _tapAt(e.localPosition),
                  child: SizedBox(
                    width: w,
                    height: lab.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _DonutPainter(
                              slices: lab.slices,
                              leaders: lab.leaders,
                              ringColor: c.surfaceAlt,
                              center: lab.center,
                              ringR: lab.ringR,
                              thickness: lab.thickness,
                              hovered: hv,
                            ),
                          ),
                        ),
                        for (final L in lab.leaders)
                          Positioned(
                            top: L.y - 9,
                            left: L.isRight ? L.textX : null,
                            right: L.isRight ? null : (w - L.textX),
                            child: Opacity(
                              opacity: hv == null || hv == L.idx ? 1.0 : 0.32,
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: L.sym,
                                    style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.1),
                                  ),
                                  TextSpan(
                                    text: '  ${L.pct}',
                                    style: TextStyle(
                                        color: c.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                softWrap: false,
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: Center(
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxWidth: _innerR * 1.7),
                              child: _centerDetail(
                                  c, hv, rows, pcts, total, inDrill),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _legend(c, rows, pcts),
      ],
    );
  }

  /// Türkçe duyarlı büyük harf. Dart'ın `toUpperCase()`'i locale bilmez:
  /// "Diğer" → "DIĞER" (noktasız I) çıkar. Sektör adları Türkçe → i/ı ayrımı
  /// elle yapılır.
  static String _upperTr(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// Alt kırılımı olan dilimlerde merkezde gösterilen ipucu ("12 varlık ›").
  /// Yalnız o dilim seçiliyken görünür; başka hiçbir yeri değiştirmez.
  Widget _drillHint(AppColorsExt c, String label) {
    final sub = widget.breakdowns[label];
    if (sub == null || sub.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text('${sub.length} ${widget.memberUnit} \u203A',
          style: TextStyle(
              color: c.textSubtle, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _centerDetail(
      AppColorsExt c,
      int? hv,
      List<({String label, double value})> rows,
      List<double> pcts,
      double total,
      bool inDrill) {
    if (hv == null) {
      // İçindeyken merkez: TOPLAM yerine hangi dilimin içinde olduğumuz +
      // geri dönüş ipucu (merkeze dokun). Tipografi üst seviyeyle aynı.
      final inside = inDrill;
      return Column(
        key: ValueKey(inside ? 'drill$_drill' : 'total'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(inside ? '\u2039 ${_upperTr(_drill!)}' : 'TOPLAM',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.textSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text('₺${formatMoney(total, decimals: 0)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6)),
          const SizedBox(height: 2),
          Text(
              '${rows.length} '
              '${inside ? widget.memberUnit : widget.centerUnit}',
              style: TextStyle(color: c.textMuted, fontSize: 11.5)),
        ],
      );
    }
    final color = AllocationDonut.palette[hv % AllocationDonut.palette.length];
    return Column(
      key: ValueKey('h$hv'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(rows[hv].label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.1)),
        const SizedBox(height: 5),
        Text('%${formatPct(pcts[hv], decimals: 1)}',
            style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6)),
        const SizedBox(height: 1),
        Text('₺${formatMoney(rows[hv].value, decimals: 0)}',
            style: TextStyle(
                color: c.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        if (!inDrill) _drillHint(c, rows[hv].label),
      ],
    );
  }

  _LayoutResult _layout(double w, List<double> pcts, List<String> labels) {
    const start = -math.pi / 2;
    // Mobil/dar genişlik: yan lider-etiketleri çiz, taşır. Alttaki lejant
    // tüm bilgiyi (ad + %) zaten veriyor. Yalnız halka + ortadaki detay.
    final narrow = w < 480;
    final mids = <int, double>{};
    int rightN = 0, leftN = 0;
    if (!narrow) {
      double a = start;
      for (int i = 0; i < pcts.length; i++) {
        final sweep = (pcts[i] / 100) * 2 * math.pi;
        final mid = a + sweep / 2;
        a += sweep;
        if (pcts[i] < AllocationDonut._labelMinPct) continue;
        mids[i] = mid;
        if (math.cos(mid) >= 0) {
          rightN++;
        } else {
          leftN++;
        }
      }
    }
    const rowH = 24.0;
    final perSideMax = math.max(rightN, leftN);
    final height = narrow
        ? math.min(w * 0.78, 280.0)
        : math.max(360.0, perSideMax * rowH + 70.0);

    final center = Offset(w / 2, height / 2);
    // Dar: kenar boşluğu küçük (lider çizgi yok). Geniş: yan etiket alanı.
    final gutter = narrow ? 18.0 : 132.0;
    final outerR = math.min(w / 2 - gutter, height / 2 - 18);
    final safeR = outerR.isFinite && outerR > 24 ? outerR : 24.0;
    // Mobilde halka biraz daha ince — büyük yüzeyde aşırı "kalın" görünmesin.
    final thickness = safeR * (narrow ? 0.32 : 0.42);
    final r = safeR - thickness / 2;
    final edgeR = r + thickness / 2;

    final slices = <_Slice>[];
    final rawR = <_LeaderTmp>[];
    final rawL = <_LeaderTmp>[];
    {
      double a = start;
      for (int i = 0; i < pcts.length; i++) {
        final sweep = (pcts[i] / 100) * 2 * math.pi;
        final color =
            AllocationDonut.palette[i % AllocationDonut.palette.length];
        if (sweep > 0) {
          slices.add(_Slice(start: a, sweep: sweep, color: color, idx: i));
        }
        a += sweep;
        if (!mids.containsKey(i)) continue;
        final mid = mids[i]!;
        final isRight = math.cos(mid) >= 0;
        final tmp = _LeaderTmp(
          idx: i,
          color: color,
          isRight: isRight,
          sym: labels[i],
          pct: '${formatPct(pcts[i], decimals: 1)}%',
          edge: Offset(center.dx + math.cos(mid) * edgeR,
              center.dy + math.sin(mid) * edgeR),
          idealY: center.dy + math.sin(mid) * edgeR,
        );
        (isRight ? rawR : rawL).add(tmp);
      }
    }

    final leaders = <_Leader>[];
    void place(List<_LeaderTmp> side, bool isRight) {
      if (side.isEmpty) return;
      side.sort((x, y) => x.idealY.compareTo(y.idealY));
      final n = side.length;
      const top = 12.0;
      final bottom = height - 12.0;
      final ys = List<double>.filled(n, 0);
      for (int i = 0; i < n; i++) {
        final ideal = side[i].idealY.clamp(top, bottom);
        ys[i] = i == 0 ? ideal : math.max(ideal, ys[i - 1] + rowH);
      }
      if (ys[n - 1] > bottom) {
        ys[n - 1] = bottom;
        for (int i = n - 2; i >= 0; i--) {
          ys[i] = math.min(ys[i], ys[i + 1] - rowH);
        }
      }
      if (ys[0] < top) {
        final span = (bottom - top);
        for (int i = 0; i < n; i++) {
          ys[i] = top + (n == 1 ? span / 2 : span * i / (n - 1));
        }
      }
      final colX = isRight ? center.dx + safeR + 22 : center.dx - safeR - 22;
      final textX = isRight ? colX + 14 : colX - 14;
      for (int i = 0; i < n; i++) {
        leaders.add(_Leader(
          idx: side[i].idx,
          color: side[i].color,
          isRight: isRight,
          y: ys[i],
          colX: colX,
          textX: textX,
          edge: side[i].edge,
          sym: side[i].sym,
          pct: side[i].pct,
        ));
      }
    }

    place(rawR, true);
    place(rawL, false);

    return _LayoutResult(
      height: height,
      center: center,
      ringR: r,
      thickness: thickness,
      slices: slices,
      leaders: leaders,
    );
  }

  Widget _legend(AppColorsExt c, List<({String label, double value})> rows,
      List<double> pcts) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: List.generate(rows.length, (i) {
          final color =
              AllocationDonut.palette[i % AllocationDonut.palette.length];
          final on = _hovered == i;
          return Listener(
            onPointerHover: (_) => _setHover(i),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setHover(on ? null : i),
              child: Container(
                width: 158,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? c.surfaceAlt : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Opacity(
                  opacity: _hovered == null || on ? 1.0 : 0.4,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          rows[i].label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${formatPct(pcts[i], decimals: 1)}%',
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Slice {
  final double start;
  final double sweep;
  final Color color;
  final int idx;
  _Slice(
      {required this.start,
      required this.sweep,
      required this.color,
      required this.idx});
}

class _LeaderTmp {
  final int idx;
  final Color color;
  final bool isRight;
  final String sym;
  final String pct;
  final Offset edge;
  final double idealY;
  _LeaderTmp({
    required this.idx,
    required this.color,
    required this.isRight,
    required this.sym,
    required this.pct,
    required this.edge,
    required this.idealY,
  });
}

class _Leader {
  final int idx;
  final Color color;
  final bool isRight;
  final double y;
  final double colX;
  final double textX;
  final Offset edge;
  final String sym;
  final String pct;
  _Leader({
    required this.idx,
    required this.color,
    required this.isRight,
    required this.y,
    required this.colX,
    required this.textX,
    required this.edge,
    required this.sym,
    required this.pct,
  });
}

class _LayoutResult {
  final double height;
  final Offset center;
  final double ringR;
  final double thickness;
  final List<_Slice> slices;
  final List<_Leader> leaders;
  _LayoutResult({
    required this.height,
    required this.center,
    required this.ringR,
    required this.thickness,
    required this.slices,
    required this.leaders,
  });
}

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  final List<_Leader> leaders;
  final Color ringColor;
  final Offset center;
  final double ringR;
  final double thickness;
  final int? hovered;

  _DonutPainter({
    required this.slices,
    required this.leaders,
    required this.ringColor,
    required this.center,
    required this.ringR,
    required this.thickness,
    required this.hovered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: ringR);

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = ringColor,
    );

    const gap = 0.012;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    _Slice? top;
    for (final s in slices) {
      if (hovered == s.idx) {
        top = s;
        continue;
      }
      arc
        ..strokeWidth = thickness
        ..color = hovered == null ? s.color : s.color.withValues(alpha: 0.28);
      final pad = s.sweep > gap * 2 ? gap : s.sweep * 0.2;
      canvas.drawArc(rect, s.start + pad / 2, s.sweep - pad, false, arc);
    }
    if (top != null) {
      arc
        ..strokeWidth = thickness + 7
        ..color = top.color;
      final pad = top.sweep > gap * 2 ? gap : top.sweep * 0.2;
      canvas.drawArc(rect, top.start + pad / 2, top.sweep - pad, false, arc);
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final l in leaders) {
      final dim = hovered != null && hovered != l.idx;
      final v = l.edge - center;
      final vl = v.distance == 0 ? 1.0 : v.distance;
      final p1 = l.edge + (v / vl) * 12.0;
      final kneeX = l.isRight ? l.colX - 18 : l.colX + 18;
      line.color = l.color.withValues(alpha: dim ? 0.22 : 0.85);
      canvas.drawLine(l.edge, p1, line);
      canvas.drawLine(p1, Offset(kneeX, l.y), line);
      canvas.drawLine(Offset(kneeX, l.y), Offset(l.colX, l.y), line);
      final dotX = l.isRight ? l.colX + 6 : l.colX - 6;
      canvas.drawCircle(Offset(dotX, l.y), 3.5,
          Paint()..color = l.color.withValues(alpha: dim ? 0.3 : 1.0));
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices ||
      old.leaders != leaders ||
      old.ringColor != ringColor ||
      old.center != center ||
      old.ringR != ringR ||
      old.thickness != thickness ||
      old.hovered != hovered;
}
