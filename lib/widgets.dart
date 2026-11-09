import 'package:flutter/material.dart';

import 'models.dart';

class LineChipView extends StatelessWidget {
  const LineChipView(this.info, {super.key});
  final LineInfo info;

  @override
  Widget build(BuildContext context) {
    final fg = ThemeData.estimateBrightnessForColor(info.color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: info.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vehicleIcon(info.kind), size: 14, color: fg),
          const SizedBox(width: 3),
          Text(
            info.label,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final RouteResult route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              formatDuration(route.seconds),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (route.mode == TravelMode.transit)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (route.lines.isEmpty)
                    Text('пешком', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    for (final l in route.lines) LineChipView(l),
                ],
              )
            else
              Text(
                formatDistance(route.meters),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class StepTile extends StatelessWidget {
  const StepTile({super.key, required this.step});
  final StepInfo step;

  @override
  Widget build(BuildContext context) {
    if (step.kind == StepKind.walk) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(
          radius: 16,
          child: Icon(Icons.directions_walk, size: 18),
        ),
        title: Text(step.title),
        subtitle: Text(step.subtitle),
      );
    }
    final fg = ThemeData.estimateBrightnessForColor(step.color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: step.color,
        child: Icon(vehicleIcon(step.vehicle), color: fg, size: 20),
      ),
      title: Text(step.title),
      subtitle: Text(step.subtitle),
    );
  }
}
