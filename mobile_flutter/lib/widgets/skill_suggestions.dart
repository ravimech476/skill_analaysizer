import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/knowledge_api.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

/// Staff panel on a student's analysis: skill levels the marks support, to accept or dismiss one by one.
/// Nothing is recorded until it is accepted, and a level that is already higher is never lowered.
class SkillSuggestionsCard extends StatefulWidget {
  const SkillSuggestionsCard({super.key, required this.studentId, this.onChanged});
  final int studentId;
  final VoidCallback? onChanged;

  @override
  State<SkillSuggestionsCard> createState() => _SkillSuggestionsCardState();
}

class _SkillSuggestionsCardState extends State<SkillSuggestionsCard> {
  List<Map<String, dynamic>>? _rows;
  String? _summary;
  List<String> _unmapped = const [];
  bool _generated = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SkillSuggestionsCard old) {
    super.didUpdateWidget(old);
    if (old.studentId != widget.studentId) {
      _generated = false;
      _summary = null;
      _unmapped = const [];
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await skillSuggestApi.pending(widget.studentId);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final r = await skillSuggestApi.generate(widget.studentId);
      if (!mounted) return;
      setState(() {
        _rows = maps(r['suggestions']);
        _summary = text(r['summary']);
        _unmapped = ((r['unmapped_subjects'] ?? []) as List).map((e) => '$e').toList();
        _generated = true;
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> s, bool accept) async {
    setState(() => _busy = true);
    final id = asInt(s['id']);
    final ok = await runAction(context, () => accept ? skillSuggestApi.accept(id) : skillSuggestApi.dismiss(id), success: accept ? 'Skill recorded' : null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _load();
      if (accept) widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? const <Map<String, dynamic>>[];
    return SectionCard(
      title: 'Skills noticed from marks',
      subtitle: 'Levels are worked out from the student\'s marks in the subjects that build each skill. Nothing is recorded until you accept it.',
      trailing: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: _busy ? null : _generate,
        icon: const Icon(Icons.bolt, size: 18),
        label: const Text('Check marks'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_summary != null && _summary!.isNotEmpty) ...[NoteBanner(title: _summary!, color: Brand.info, icon: Icons.info_outline), const SizedBox(height: 8)],
        if (_unmapped.isNotEmpty) ...[
          NoteBanner(
            title: 'No skill mapping for: ${_unmapped.join(', ')}',
            body: 'Marks in these subjects cannot produce suggestions. Map them under Skill Analysis Config.',
            color: Brand.warning,
            icon: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: 8),
        ],
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: Brand.error, fontSize: 13)),
        if (!_loading && _error == null && rows.isEmpty)
          Text(_generated ? 'No new skill levels are supported by the marks.' : 'Press "Check marks" to look for skills the marks support.',
              style: const TextStyle(fontSize: 13, color: Brand.muted)),
        for (final s in rows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: Brand.border), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(text(s['skill']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                  Text(s['current_level'] == null ? 'none' : 'level ${s['current_level']}', style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                  const Text('  →  '),
                  Tag('level ${asInt(s['suggested_level'])}', color: asInt(s['suggested_level']) >= 4 ? Brand.success : Brand.info),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${s['percent']}% across ${maps(s['evidence']).map((e) => '${text(e['subject'])} (${e['percent']}%${asDouble(e['weight']) != 1 ? ', weight ${e['weight']}' : ''})').join(', ')}',
                  style: const TextStyle(fontSize: 12.5, color: Brand.textSoft),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  FilledButton(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _busy ? null : () => _decide(s, true),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _busy ? null : () => _decide(s, false),
                    child: const Text('Dismiss'),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
