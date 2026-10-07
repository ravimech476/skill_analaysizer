import 'package:flutter/material.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ThresholdScreen extends StatefulWidget {
  const ThresholdScreen({super.key});

  @override
  State<ThresholdScreen> createState() => _ThresholdScreenState();
}

class _ThresholdScreenState extends State<ThresholdScreen> {
  Map<String, dynamic>? _config;
  List<MasterRow>? _skills;
  bool _loading = true;

  double _globalThreshold = 75;
  Map<String, double> _overrides = {};
  double _skillWeight = 70;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await scoresApi.scoring();
      final skillRows = await mastersApi.all('skills');
      final threshold = config['global_threshold'] as num? ?? 75;
      final overrides = (config['skill_overrides'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as num).toDouble())) ?? {};
      final sw = (config['match_weights']?['skill'] as num?)?.toDouble() ?? 70;
      setState(() {
        _config = config;
        _skills = skillRows;
        _globalThreshold = threshold.toDouble();
        _overrides = overrides;
        _skillWeight = sw;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _save() async {
    await runAction(context, () async {
      await scoresApi.saveScoring({
        'global_threshold': _globalThreshold.round(),
        'skill_overrides': _overrides,
        'match_weights': {'skill': _skillWeight.round(), 'academic': (100 - _skillWeight).round()},
      });
      toast(context, 'Configuration saved');
    });
  }

  Future<void> _recompute() async {
    final yes = await confirm(context, 'Recompute all student skill scores?', 'This may take a moment.');
    if (!yes) return;
    await runAction(context, () async {
      final result = await scoresApi.recompute({'scope': 'all'});
      final count = result['recomputed'] ?? 0;
      if (mounted) toast(context, 'Recomputed $count student scores');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Loader();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Global Mark Threshold',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Minimum mark % to consider a student skilled in a subject\'s mapped skills.',
                style: TextStyle(color: Brand.textSoft, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _globalThreshold,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '${_globalThreshold.round()}%',
                      onChanged: (v) => setState(() => _globalThreshold = v),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Brand.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_globalThreshold.round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.accent, fontSize: 16)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Per-Skill Threshold Override',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Leave blank to use global value (${_globalThreshold.round()}%).',
                  style: const TextStyle(color: Brand.textSoft, fontSize: 13)),
              const SizedBox(height: 12),
              if (_skills != null)
                ...(_skills!).map((s) {
                  final name = s['name'] as String? ?? '';
                  final cat = s['category'] as String? ?? '';
                  final ov = _overrides[name];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    subtitle: Text(cat, style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                    trailing: SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: ov != null ? '${ov.round()}' : '',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(hintText: '${_globalThreshold.round()}', suffixText: '%', isDense: true),
                        onChanged: (v) {
                          setState(() {
                            final n = double.tryParse(v);
                            if (n == null || v.isEmpty) {
                              _overrides.remove(name);
                            } else {
                              _overrides[name] = n.clamp(0, 100);
                            }
                          });
                        },
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Match Weights',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'When matching students to placement drives, weight of skill scores vs academic scores.',
                style: TextStyle(color: Brand.textSoft, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text('Skill Score: ${_skillWeight.round()}%'),
              Slider(
                value: _skillWeight,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${_skillWeight.round()}%',
                onChanged: (v) => setState(() => _skillWeight = v),
              ),
              Text('Academic Score: ${(100 - _skillWeight).round()}%'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: _save, child: const Text('Save Configuration')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(onPressed: _recompute, child: const Text('Recompute All')),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
