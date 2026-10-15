import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/city.dart';
import 'pages/city_page.dart';
import 'pages/search_page.dart';
import 'services/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
  );
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Погода',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const gps = City(name: 'Моё местоположение', lat: 0, lon: 0, isGps: true);
  final controller = PageController();
  List<City> cities = [gps];
  int index = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final saved = await Storage.loadCities();
    if (mounted) setState(() => cities = [gps, ...saved]);
  }

  Future<void> _openSearch() async {
    final picked = await Navigator.push<City>(
      context,
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
    await _reload();
    if (!mounted) return;
    int i;
    if (picked == null) {
      i = math.min(index, cities.length - 1);
    } else if (picked.isGps) {
      i = 0;
    } else {
      i = cities.indexWhere((c) => !c.isGps && c.sameAs(picked));
      if (i < 0) i = 0;
    }
    setState(() => index = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) controller.jumpToPage(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14213D),
      body: Stack(children: [
        PageView.builder(
          controller: controller,
          itemCount: cities.length,
          onPageChanged: (i) => setState(() => index = i),
          itemBuilder: (_, i) {
            final c = cities[i];
            return CityPage(
              key: ValueKey(c.isGps ? 'gps' : '${c.lat},${c.lon}'),
              city: c,
            );
          },
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar()),
      ]),
    );
  }

  Widget _bottomBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          color: Colors.black.withValues(alpha: 0.25),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(children: [
                IconButton(
                  onPressed: () => controller.animateToPage(0,
                      duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                  icon: const Icon(Icons.near_me, color: Colors.white),
                ),
                Expanded(
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < cities.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: cities[i].isGps
                              ? Icon(Icons.near_me,
                                  size: 12,
                                  color: i == index ? Colors.white : Colors.white38)
                              : Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == index ? Colors.white : Colors.white38,
                                  ),
                                ),
                        ),
                    ]),
                  ),
                ),
                IconButton(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.list, color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}