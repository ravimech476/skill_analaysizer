import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Colours for the six levels, lowest to highest.
const bloomColors = <String, Color>{
  'remember': Brand.textSoft,
  'understand': Brand.info,
  'apply': Color(0xFF0E7490),
  'analyze': Brand.warning,
  'evaluate': Color(0xFF6D28D9),
  'create': Brand.success,
};

class BloomTag extends StatelessWidget {
  const BloomTag(this.level, {super.key});
  final String level;
  @override
  Widget build(BuildContext context) => level.isEmpty
      ? const Text('—')
      : Tag(pretty(level), color: bloomColors[level] ?? Brand.textSoft);
}

/// "High confidence" / "Please check", coloured to match.
class ConfidenceTag extends StatelessWidget {
  const ConfidenceTag(this.confidence, {super.key});
  final String confidence;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      'high' => ('High confidence', Brand.success),
      'medium' => ('Medium confidence', Brand.info),
      _ => ('Please check', Brand.warning),
    };
    return Tag(label, color: color);
  }
}

/// Classifies every question in small batches and lets staff tick the suggestions to apply.
/// Nothing changes until "Apply" is pressed; low-confidence suggestions start unticked.
class BloomsReviewScreen extends StatefulWidget {
  const BloomsReviewScreen({super.key});

  @override
  State<BloomsReviewScreen> createState() => _BloomsReviewScreenState();
}

class _BloomsReviewScreenState extends State<BloomsReviewScreen> {
  bool _running = true;
  bool _applying = false;
  int _done = 0;
  int _total = 0;
  String? _error;
  final _items = <BloomReviewItem>[];
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final all = await mastersApi.all('question-bank');
      final ids = all.map((q) => q.id).toList();
      if (mounted) setState(() => _total = ids.length);
      for (var i = 0; i < ids.length; i += BloomsApi.reviewBatch) {
        final batch = await bloomsApi.review(
          ids.sublist(i, (i + BloomsApi.reviewBatch).clamp(0, ids.length)),
        );
        if (!mounted) return;
        setState(() {
          _items.addAll(batch.where((b) => b.differs));
          _selected
            ..clear()
            ..addAll(
              _items.where((b) => b.confidence != 'low').map((b) => b.id),
            );
          _done = (i + BloomsApi.reviewBatch).clamp(0, ids.length);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final n = await bloomsApi.apply([
        for (final i in _items.where((i) => _selected.contains(i.id)))
          (id: i.id, level: i.level),
      ]);
      if (!mounted) return;
      toast(context, 'Updated $n question${n == 1 ? '' : 's'}');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              const Text(
                'The AI reads each question and compares its level with the saved one. Tick the suggestions you accept. '
                'Nothing changes until you press Apply.',
                style: TextStyle(fontSize: 13, color: Brand.textSoft),
              ),
              const SizedBox(height: 12),
              if (_running) ...[
                LinearProgressIndicator(
                  value: _total == 0 ? null : _done / _total,
                ),
                const SizedBox(height: 4),
                Text(
                  'Checked $_done of $_total',
                  style: const TextStyle(fontSize: 12, color: Brand.textSoft),
                ),
                const SizedBox(height: 8),
              ],
              if (_error != null)
                NoteBanner(
                  title: _error!,
                  color: Brand.error,
                  icon: Icons.error_outline,
                ),
              if (!_running && _error == null && _items.isEmpty)
                const NoteBanner(
                  title: 'Every question already has the level the AI would suggest.',
                  color: Brand.success,
                  icon: Icons.check_circle_outline,
                ),
              for (final item in _items) _row(item),
            ],
          ),
        ),
        if (_items.isNotEmpty)
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: Brand.surface,
                border: Border(top: BorderSide(color: Brand.border)),
              ),
              child: FilledButton(
                onPressed: _selected.isEmpty || _running || _applying
                    ? null
                    : _apply,
                child: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Apply ${_selected.length} selected'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(BloomReviewItem item) {
    final on = _selected.contains(item.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(
          () => on ? _selected.remove(item.id) : _selected.add(item.id),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: on,
                onChanged: (v) => setState(
                  () => v == true
                      ? _selected.add(item.id)
                      : _selected.remove(item.id),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.question,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.subject} · ${item.marks} marks',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Brand.textSoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        BloomTag(item.current),
                        const Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: Brand.textSoft,
                        ),
                        BloomTag(item.level),
                        ConfidenceTag(item.confidence),
                      ],
                    ),
                    if (item.reason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.reason,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Brand.textSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
