import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _suggestions = [
  'How am I doing in my marks?',
  'Which skills should I improve for placements?',
  'Which placement drives am I eligible for?',
  'Give me interview questions to practice',
];

class _Turn {
  _Turn(this.mine, this.text, [this.sources = const []]);
  final bool mine;
  final String text;
  final List<String> sources;
}

/// The AI assistant: answers come from the college's own data, through the backend.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await chatApi.history();
      if (!mounted) return;
      setState(() {
        _turns
          ..clear()
          ..addAll(rows.map((m) => _Turn(m['role'] == 'user', m['content'] as String, ChatApi.sourceTitles(m['sources']))));
        _loading = false;
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage(e);
      });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _input.text).trim();
    if (q.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _turns.add(_Turn(true, q));
      _sending = true;
      _error = null;
    });
    _toBottom();
    try {
      final r = await chatApi.ask(q);
      if (!mounted) return;
      setState(() => _turns.add(_Turn(false, r.answer, r.sources)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  Future<void> _clear() async {
    if (!await confirm(context, 'Clear this conversation?', okLabel: 'Clear', danger: true)) return;
    if (!mounted) return;
    await runAction(context, () async {
      await chatApi.clear();
      if (mounted) setState(_turns.clear);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Loader();
    return Column(
      children: [
        if (_turns.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _sending ? null : _clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear'),
            ),
          ),
        Expanded(
          child: _turns.isEmpty && !_sending ? _intro() : _messages(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(_error!, style: const TextStyle(color: Brand.error, fontSize: 13)),
          ),
        _composer(),
      ],
    );
  }

  Widget _intro() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.smart_toy_outlined, size: 44, color: Brand.accent),
          const SizedBox(height: 12),
          const Text('EduSkill Assistant',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Brand.text)),
          const SizedBox(height: 6),
          const Text('Ask about your marks, skills, placements or interview prep',
              textAlign: TextAlign.center, style: TextStyle(color: Brand.textSoft)),
          const SizedBox(height: 20),
          for (final s in _suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(onPressed: () => _send(s), child: Text(s, textAlign: TextAlign.center)),
            ),
        ],
      );

  Widget _messages() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _turns.length + (_sending ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _turns.length) return _typing();
          return _bubble(_turns[i]);
        },
      );

  Widget _bubble(_Turn t) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    return Align(
      alignment: t.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: t.mine ? Brand.accent : Brand.surface,
          border: t.mine ? null : Border.all(color: Brand.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: t.mine
            ? SelectableText(t.text, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.4))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MarkdownText(t.text),
                  if (t.sources.isNotEmpty) ...[
                    const Divider(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 14, color: Brand.textSoft),
                        const Text('Sources:', style: TextStyle(fontSize: 12, color: Brand.textSoft)),
                        for (final s in t.sources) Tag(s),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _typing() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Thinking… this can take a little while', style: TextStyle(color: Brand.textSoft, fontSize: 13)),
          ],
        ),
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: const BoxDecoration(color: Brand.surface, border: Border(top: BorderSide(color: Brand.border))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Ask a question…', counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send, size: 20),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      );
}

/// Just enough Markdown for the model's answers: headings, bullets, numbered lines and **bold**.
class _MarkdownText extends StatelessWidget {
  const _MarkdownText(this.source);
  final String source;

  static final _bullet = RegExp(r'^(\s*)[*+-]\s+(.*)$');
  static final _number = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)$');
  static final _bold = RegExp(r'\*\*(.+?)\*\*');

  static const _base = TextStyle(color: Brand.text, fontSize: 14.5, height: 1.4);

  List<InlineSpan> _inline(String s) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _bold.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return spans;
  }

  Widget _line(String prefix, String text, {double indent = 0, bool bold = false}) => Padding(
        padding: EdgeInsets.only(left: indent, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (prefix.isNotEmpty) SizedBox(width: 20, child: Text(prefix, style: _base)),
            Expanded(
              child: Text.rich(
                TextSpan(style: bold ? _base.copyWith(fontWeight: FontWeight.w700) : _base, children: _inline(text)),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 5));
        continue;
      }
      final h = _heading.firstMatch(line);
      final b = _bullet.firstMatch(line);
      final n = _number.firstMatch(line);
      if (h != null) {
        children.add(_line('', h.group(1)!, bold: true));
      } else if (b != null) {
        children.add(_line('•', b.group(2)!, indent: (b.group(1)!.length ~/ 2) * 10.0));
      } else if (n != null) {
        children.add(_line('${n.group(2)}.', n.group(3)!, indent: (n.group(1)!.length ~/ 2) * 10.0));
      } else {
        children.add(_line('', line));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
