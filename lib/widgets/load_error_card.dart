import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';

/// "Veri YOK" ile "veri ALINAMADI" aynı ekran değildir.
///
/// Ekranların çoğu istek başarısız olunca boş listeyle kalıyordu ve boş-durum
/// metnini basıyordu: 38 pozisyonu olan kullanıcı ağ hatasında "portföyün boş,
/// ilk hisseni ekle" görüyordu. Bu kart yalnız GERÇEK hata için kullanılır;
/// veri sahiden yoksa ekranın kendi boş-durum metni gösterilmeye devam eder.
class LoadErrorCard extends StatelessWidget {
  const LoadErrorCard({
    super.key,
    required this.title,
    this.hint = 'Sunucu uyanıyor olabilir — tekrar dene',
    this.icon = Icons.cloud_off_rounded,
    this.onRetry,
  });

  final String title;
  final String hint;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.xl),
      child: Column(
        children: [
          Icon(icon, size: 38, color: c.textSubtle),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: IOSPillButton(
                label: 'Tekrar Dene',
                secondary: true,
                onPressed: onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
