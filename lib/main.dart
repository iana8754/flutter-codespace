import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'models/weather.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WeatherPage(),
  ));
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});
  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  Weather? weather;
  String city = '';
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final pos = await LocationService.getPosition();
      final results = await Future.wait([
        WeatherService.fetch(pos.latitude, pos.longitude),
        LocationService.getCity(pos.latitude, pos.longitude),
      ]);
      weather = results[0] as Weather;
      city = results[1] as String;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = weather != null
        ? infoFor(weather!.code)
        : const WeatherInfo('🌡️', '', [Color(0xFF607D8B), Color(0xFF263238)]);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: info.colors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: _body(info)),
      ),
    );
  }

  Widget _body(WeatherInfo info) {
    if (loading && weather == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (error != null && weather == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_off, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(onPressed: load, child: const Text('Повторить')),
          ]),
        ),
      );
    }

    final w = weather!;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.place, color: Colors.white70),
            const SizedBox(width: 4),
            Text(city, style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 24),
          Center(child: Text(info.emoji, style: const TextStyle(fontSize: 96))),
          Center(
            child: Text('${w.temp.round()}°',
                style: const TextStyle(color: Colors.white, fontSize: 88,
                    fontWeight: FontWeight.w200)),
          ),
          Center(
            child: Text(info.text,
                style: const TextStyle(color: Colors.white70, fontSize: 22)),
          ),
          const SizedBox(height: 28),
          _card(Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(Icons.thermostat, 'Ощущается', '${w.feels.round()}°'),
              _stat(Icons.water_drop, 'Влажность', '${w.humidity}%'),
              _stat(Icons.air, 'Ветер', '${w.wind.round()} км/ч'),
            ],
          )),
          const SizedBox(height: 16),
          _card(Column(
            children: w.days.map((d) {
              final di = infoFor(d.code);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      DateFormat.E('ru').format(d.date),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  Text(di.emoji, style: const TextStyle(fontSize: 24)),
                  const Spacer(),
                  Text('${d.min.round()}°',
                      style: const TextStyle(color: Colors.white60, fontSize: 16)),
                  const SizedBox(width: 16),
                  Text('${d.max.round()}°',
                      style: const TextStyle(color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ]),
              );
            }).toList(),
          )),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      );

  Widget _stat(IconData icon, String label, String value) => Column(children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.w600)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]);
}