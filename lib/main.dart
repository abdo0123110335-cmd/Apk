import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ElsheikhCustomsApp());
}

class ElsheikhCustomsApp extends StatelessWidget {
  const ElsheikhCustomsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أعمال الشيخ مختار للتخليص الجمركي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SD'),
      supportedLocales: const [
        Locale('ar', 'SD'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF003366),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003366),
          primary: const Color(0xFF003366),
          secondary: const Color(0xFF0099CC),
          background: const Color(0xFFF4F6F9),
        ),
        fontFamily: GoogleFonts.cairo().fontFamily,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF003366),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
