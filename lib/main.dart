// ============================================================================
// Portly — Uygulama Giriş Noktası
//
// Bu dosya, Flutter uygulamasının başlangıç noktasını ve global durum
// yönetimi altyapısını tanımlar.
//
// Durum Yönetimi Mimarisi:
//   Provider paketi kullanılmaktadır. Her ChangeNotifier bağımsız bir
//   veri domainini yönetir:
//     - AuthProvider      → Kullanıcı kimlik doğrulama durumu
//     - PortfolioProvider → Piyasa verisi, portföy, haberler
//     - ChatProvider      → AI sohbet mesajları ve stream durumu
//
//   ChangeNotifierProxyProvider kullanımı kritiktir: AuthProvider'ın
//   sağladığı userId/token değerleri, bağımlı provider'lara reaktif
//   biçimde iletilmektedir. Kullanıcı çıkış yaptığında tüm veri
//   katmanları otomatik temizlenmektedir.
//
// Yönlendirme: AuthGate widget'ı, kimlik doğrulama durumuna göre
//   LoginScreen veya MainScreen arasında şeffaf geçiş sağlar.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/providers/notes_provider.dart';
import 'package:portly/screens/chat_screen.dart';
import 'package:portly/providers/theme_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/utils/app_tabs.dart';
import 'package:portly/screens/home_screen.dart';
import 'package:portly/screens/news_screen.dart';
import 'package:portly/screens/portfolio_screen.dart';
import 'package:portly/screens/signals_screen.dart';
import 'package:portly/screens/profile_screen.dart';
import 'package:portly/screens/login_screen.dart';
import 'package:portly/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// async main: dotenv yüklenmesi WidgetsFlutterBinding başlatıldıktan sonra yapılmalıdır.
// Bu zorunluluk, native channel'ların Flutter engine ile senkronize olmasından kaynaklanır.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // PortfolioProvider, AuthProvider'a bağımlıdır:
        // kullanıcı giriş/çıkış yaptığında userId ve token otomatik güncellenir.
        ChangeNotifierProxyProvider<AuthProvider, PortfolioProvider>(
          create: (_) => PortfolioProvider(),
          update: (_, auth, prev) {
            final p = prev ?? PortfolioProvider();
            p.updateUserAuth(auth.userId, auth.token);
            return p;
          },
        ),
        // ChatProvider da AuthProvider'dan userId alır; stream bağlantısını
        // kullanıcıya göre açıp kapatmak için gereklidir.
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, auth, prev) {
            final c = prev ?? ChatProvider();
            c.updateAuth(auth.userId);
            return c;
          },
        ),
        // NotesProvider (yatırımcı günlüğü) da AuthProvider'dan userId alır;
        // giriş olunca notları yükler, çıkışta temizler.
        ChangeNotifierProxyProvider<AuthProvider, NotesProvider>(
          create: (_) => NotesProvider(),
          update: (_, auth, prev) {
            final n = prev ?? NotesProvider();
            n.updateAuth(auth.userId);
            return n;
          },
        ),
      ],
      child: const PortlyApp(),
    ),
  );
}

class PortlyApp extends StatelessWidget {
  const PortlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'Portly',
      debugShowCheckedModeBanner: false,
      themeMode: themeProv.mode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}

// AuthGate: ilk açılışta onboarding turunu (bir kez), ardından kimlik
// doğrulama durumuna göre doğru ekranı render eder.
// isLoading durumu, SharedPreferences'tan token okunurken beyaz flash'ı engeller.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _onboardKey = 'onboarding_seen';
  bool? _onboardSeen; // null = prefs henüz yüklenmedi

  @override
  void initState() {
    super.initState();
    _loadOnboard();
  }

  Future<void> _loadOnboard() async {
    bool seen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(_onboardKey) ?? false;
    } catch (_) {}
    if (mounted) setState(() => _onboardSeen = seen);
  }

  Future<void> _finishOnboard() async {
    if (mounted) setState(() => _onboardSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading || _onboardSeen == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary),
        ),
      );
    }
    if (_onboardSeen == false) {
      return OnboardingScreen(onDone: _finishOnboard);
    }
    return auth.isAuthenticated ? const MainScreen() : const LoginScreen();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // AI Koç FAB konumu — null = varsayılan (sağ-alt). Kullanıcı basılı tutup
  // taşıyınca güncellenir; oturum boyunca kalır, uygulama yeniden açılınca
  // varsayılana döner.
  Offset? _fabPos;

  @override
  void initState() {
    super.initState();
    kRequestedTab.addListener(_applyTabRequest);
  }

  @override
  void dispose() {
    kRequestedTab.removeListener(_applyTabRequest);
    super.dispose();
  }

  // Başka ekrandan gelen sekme isteği → alt navigasyonu değiştir.
  void _applyTabRequest() {
    final i = kRequestedTab.value;
    if (i < 0 || i >= _tabCount) return;
    if (mounted) _goTab(i);
    kRequestedTab.value = -1; // kanalı boşalt
  }

  // Sayfalar IndexedStack ile yönetilir (Module F / G1): sekme değişince
  // widget AĞACI KORUNUR → scroll/arama/form state'i kaybolmaz.
  //
  // ⚠️ TEMBEL KURULUM (açılış hızı): eskiden 4 sekme de açılışta BİR ANDA
  // kuruluyordu → uygulama daha ilk karede Haber (24 sembol RSS+LLM),
  // Sinyaller (50+ sembol taraması, ~15sn) ve Portföy'ün kart istekleri
  // (sağlık/benchmark) dahil ~12 HTTP isteği atıyordu. Kullanıcı Ana
  // Sayfa'ya bakarken ücretsiz Render örneği (0.5 CPU) bunları paralel
  // işlemeye çalışıyor, ana ekranın verisi de kuyruğa giriyordu.
  // Artık sekme YALNIZCA ilk kez ziyaret edilince kurulur; kurulduktan
  // sonra IndexedStack'te KALIR (state korunur, ikinci ziyaret bedava).
  static const int _tabCount = 4;
  final Set<int> _visited = {0};

  Widget _buildTab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const HomeScreen();
      case 1:
        return const NewsScreen();
      case 2:
        return const SignalsScreen();
      default:
        return const PortfolioScreen();
    }
  }

  void _goTab(int i) {
    if (i < 0 || i >= _tabCount) return;
    setState(() {
      _visited.add(i);
      _currentIndex = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 26, width: 26),
            const SizedBox(width: 8),
            Text('Portly',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5)),
          ],
        ),
        centerTitle: true,
        // Opak bg: şeffaf AppBar light modda üstteki içeriğin sızmasına/
        // ghost kalmasına yol açıyordu.
        backgroundColor: AppColorsExt.of(context).bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Sıralama (soldan sağa): tema · profil · çıkış → çıkış en sağda,
        // tema çıkışın 2 solunda.
        actions: [
          // Tema toggle (güneş/ay) — her ekranda sağ üstte.
          IconButton(
            icon: Icon(
              context.watch<ThemeProvider>().isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: 'Tema',
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
          IconButton(
            icon: Icon(Icons.person_outline,
                color: Theme.of(context).colorScheme.onSurface),
            tooltip: 'Profilim',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7)),
            tooltip: 'Çıkış Yap',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      // AI Koç — amiral özelliği: yuvarlak buton ile HER SEKMEDE her an
      // erişilebilir. Monokrom (data-ink): pure textPrimary zemin + bg ikon.
      // Scaffold FAB yerine Stack içinde Positioned → basılı tutup SÜRÜKLENEBİLİR
      // (varsayılan sağ-alt; tek dokunuş AI Koç'u açar).
      body: LayoutBuilder(
        builder: (context, constraints) {
          const fabSize = 56.0;
          const margin = 16.0;
          final maxX =
              (constraints.maxWidth - fabSize - margin).clamp(margin, double.infinity).toDouble();
          final maxY =
              (constraints.maxHeight - fabSize - margin).clamp(margin, double.infinity).toDouble();
          final base = _fabPos ?? Offset(maxX, maxY);
          final pos = Offset(
            base.dx.clamp(margin, maxX).toDouble(),
            base.dy.clamp(margin, maxY).toDouble(),
          );
          return Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                children: [
                  for (int i = 0; i < _tabCount; i++) _buildTab(i),
                ],
              ),
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  // Android'de FAB'ın kendi dokunma algılayıcısı (onPressed)
                  // sürükleme (onPanUpdate) ile "gesture arena"da yarışıyordu →
                  // pan bazen kaybedip FAB parmağı takip etmiyordu. Çözüm: TEK
                  // GestureDetector hem dokunuşu (onTap → sohbet) hem sürüklemeyi
                  // sahiplensin; FAB IgnorePointer ile sırf görsel olsun (arenaya
                  // girmez). behavior.opaque → tüm FAB alanı dokunuşu güvenle alır.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatScreen()),
                  ),
                  // Delta'yı build anındaki `pos` yerine GÜNCEL `_fabPos`'a ekle:
                  // bir frame içinde birden çok pan olayı gelince hepsi en taze
                  // konumu okur (setState closure'ı senkron çalışır) → hızlı
                  // sürüklemede ara delta'lar düşmez, FAB parmağın gerisinde kalmaz.
                  onPanUpdate: (d) => setState(() {
                    final cur = _fabPos ?? pos;
                    _fabPos = Offset(
                      (cur.dx + d.delta.dx).clamp(margin, maxX).toDouble(),
                      (cur.dy + d.delta.dy).clamp(margin, maxY).toDouble(),
                    );
                  }),
                  child: IgnorePointer(
                    child: FloatingActionButton(
                      heroTag: 'coachFab',
                      onPressed: () {}, // dokunuş GestureDetector.onTap'te; görsel
                      backgroundColor: AppColorsExt.of(context).textPrimary,
                      foregroundColor: AppColorsExt.of(context).bg,
                      elevation: 3,
                      tooltip: 'AI Koç',
                      child: const Icon(Icons.auto_awesome),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColorsExt.of(context).bg,
          border: Border(
            top: BorderSide(
              color: AppColorsExt.of(context).divider,
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _goTab,
          selectedItemColor: AppColorsExt.of(context).warmAccent,
          unselectedItemColor: AppColorsExt.of(context).textSubtle,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          iconSize: 26,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.1),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.1),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.show_chart_outlined),
                activeIcon: Icon(Icons.show_chart_rounded),
                label: 'Ana Sayfa'),
            BottomNavigationBarItem(
                icon: Icon(Icons.article_outlined),
                activeIcon: Icon(Icons.article_rounded),
                label: 'Haberler'),
            BottomNavigationBarItem(
                icon: Icon(Icons.insights_outlined),
                activeIcon: Icon(Icons.insights_rounded),
                label: 'Sinyaller'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                activeIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Portföy'),
          ],
        ),
      ),
    );
  }

  // Yanlışlıkla çıkış yapılmasını önlemek için onay sheet'i.
  void _confirmLogout(BuildContext context) {
    showIOSBottomSheet(
      context: context,
      title: 'Çıkış Yap',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (ctx) {
              final c = AppColorsExt.of(ctx);
              return Text(
                'Hesabından çıkmak istediğine emin misin?',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 14,
                  letterSpacing: -0.1,
                  height: 1.5,
                ),
              );
            }),
            const SizedBox(height: 20),
            IOSPillButton(
              label: 'Çıkış Yap',
              width: double.infinity,
              onPressed: () {
                Navigator.pop(context);
                context.read<AuthProvider>().logout();
              },
            ),
            const SizedBox(height: 10),
            IOSPillButton(
              label: 'Vazgeç',
              secondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
