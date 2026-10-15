import 'dart:async';
import 'package:flutter/material.dart';
import '../models/city.dart';
import '../services/geo_service.dart';
import '../services/storage.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ctrl = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  List<City> results = [];
  List<City> saved = [];
  bool searching = false;

  @override
  void initState() {
    super.initState();
    Storage.loadCities().then((l) {
      if (mounted) setState(() => saved = l);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        results = [];
        searching = false;
      });
      return;
    }
    setState(() => results = GeoService.local(q)); // мгновенные подсказки
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final my = ++_seq;
      setState(() => searching = true);
      final remote = await GeoService.remote(q);
      if (!mounted || my != _seq || ctrl.text.trim() != q) return;
      setState(() {
        results = GeoService.merge(GeoService.local(q), remote);
        searching = false;
      });
    });
  }

  Future<void> _pick(City c) async {
    if (!c.isGps && !saved.any((s) => s.sameAs(c))) {
      saved.add(c);
      await Storage.saveCities(saved);
    }
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final q = ctrl.text.trim();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B2A49), Color(0xFF0F1626)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск города',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                ctrl.clear();
                                _onChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ]),
            ),
            if (searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: q.isEmpty ? _home() : _results()),
          ]),
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _home() {
    return ListView(children: [
      ListTile(
        leading: const Icon(Icons.near_me, color: Colors.lightBlueAccent),
        title: const Text('Моё местоположение'),
        subtitle: const Text('Определить по GPS'),
        onTap: () => Navigator.pop(
            context, const City(name: 'Моё местоположение', lat: 0, lon: 0, isGps: true)),
      ),
      if (saved.isNotEmpty) _header('ВАШИ ГОРОДА  (смахните влево, чтобы удалить)'),
      for (final c in List<City>.from(saved))
        Dismissible(
          key: ValueKey('${c.lat},${c.lon}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red.shade700,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) {
            saved.removeWhere((s) => s.sameAs(c));
            Storage.saveCities(saved);
            setState(() {});
          },
          child: ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(c.name),
            subtitle: c.region == null ? null : Text(c.region!),
            onTap: () => _pick(c),
          ),
        ),
      _header('ПОПУЛЯРНЫЕ'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final r in popularCities.take(14))
            ActionChip(label: Text(r.$1), onPressed: () => _pick(cityFromRecord(r))),
        ]),
      ),
    ]);
  }

  Widget _results() {
    if (results.isEmpty) {
      return Center(
        child: Text(searching ? '' : 'Ничего не найдено',
            style: const TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final c = results[i];
        final has = saved.any((s) => s.sameAs(c));
        return ListTile(
          leading: const Icon(Icons.location_city),
          title: Text(c.name),
          subtitle: c.region == null ? null : Text(c.region!),
          trailing: Icon(has ? Icons.check : Icons.add, color: Colors.white54),
          onTap: () => _pick(c),
        );
      },
    );
  }
}