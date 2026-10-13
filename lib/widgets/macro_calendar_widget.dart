import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';

/// Yaklaşan ekonomik takvim olayları — TÜFE, FED kararı, TCMB PPK vb.
/// Önem rengi = veri → data-ink kuralında izinli, tema token'ı.
class MacroCalendarWidget extends StatefulWidget {
  const MacroCalendarWidget({super.key});

  @override
  State<MacroCalendarWidget> createState() => _MacroCalendarWidgetState();
}

class _MacroCalendarWidgetState extends State<MacroCalendarWidget> {
  final ApiService _api = ApiService();
  List<dynamic>? _events;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await _api.fetchMacroCalendar();
    if (!mounted) return;
    setState(() {
      _events = e;
      _loading = false;
    });
  }

  Color _importanceColor(BuildContext context, String imp) {
    final c = AppColorsExt.of(context);
    switch (imp) {
      case 'high':
        return c.negative;
      case 'medium':
        return c.warmAccent;
      default:
        return c.textSubtle;
    }
  }

  String _importanceLabel(String imp) {
    switch (imp) {
      case 'high':
        return 'Yüksek';
      case 'medium':
        return 'Orta';
      default:
        return 'Düşük';
    }
  }

  String _flagFor(String country) {
    switch (country.toUpperCase()) {
      case 'TUR':
      case 'TR':
        return '🇹🇷';
      case 'USA':
      case 'US':
        return '🇺🇸';
      case 'EU':
      case 'EUR':
        return '🇪🇺';
      case 'CN':
      case 'CHN':
        return '🇨🇳';
      case 'DE':
      case 'GER':
        return '🇩🇪';
      case 'JP':
      case 'JPN':
        return '🇯🇵';
      case 'GB':
      case 'UK':
        return '🇬🇧';
      default:
        return '🌐';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    if (_loading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: CircularProgressIndicator(color: c.textPrimary),
        ),
      );
    }
    if (_events == null || _events!.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, color: c.textMuted, size: 17),
              const SizedBox(width: 7),
              Text('Bu Hafta Önemli Olaylar',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2)),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _load,
                  child: Icon(Icons.refresh, color: c.textSubtle, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._events!.take(6).map((e) {
            final ev = e as Map<String, dynamic>;
            final title = ev['title'] as String? ?? '';
            final date = ev['date'] as String? ?? '';
            final time = ev['time'] as String? ?? '';
            final country = ev['country'] as String? ?? '';
            final imp = ev['importance'] as String? ?? 'medium';
            final impact = ev['impact'] as String? ?? '';
            final color = _importanceColor(context, imp);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: color, width: 3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_flagFor(country), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1)),
                        const SizedBox(height: 3),
                        Text('$date · $time',
                            style: TextStyle(
                              color: c.textSubtle,
                              fontSize: 10,
                            )),
                        if (impact.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(impact,
                              style: TextStyle(
                                  color: c.textMuted,
                                  fontSize: 11,
                                  height: 1.4)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(_importanceLabel(imp),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
