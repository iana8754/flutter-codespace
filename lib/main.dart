import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'config.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой Диск',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F6AF5),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7FB),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: supa.auth.onAuthStateChange,
        builder: (_, __) =>
            supa.auth.currentSession == null ? const AuthPage() : const HomePage(),
      ),
    );
  }
}
