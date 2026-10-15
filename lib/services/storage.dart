import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/city.dart';

class Storage {
  static Future<List<City>> loadCities() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('cities');
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => City.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCities(List<City> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cities', jsonEncode(list.map((c) => c.toJson()).toList()));
  }
}