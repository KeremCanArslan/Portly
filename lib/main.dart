import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; // 1. Sihir: Google Fonts içeri alındı
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/screens/home_screen.dart';
import 'package:portly/screens/news_screen.dart';
import 'package:portly/screens/portfolio_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => PortfolioProvider(),
      child: const PortlyApp(),
    ),
  );
}

class PortlyApp extends StatelessWidget {
  const PortlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.tealAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
        // SİHİRLİ DOKUNUŞ: Tüm uygulamanın karakteri değişiyor!
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeScreen(),
    const NewsScreen(),
    const PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Portly', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.show_chart), label: 'Piyasalar'),
          BottomNavigationBarItem(
              icon: Icon(Icons.article_outlined), label: 'Haberler'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet), label: 'Portföy'),
        ],
      ),
    );
  }
}
