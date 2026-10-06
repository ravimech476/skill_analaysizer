import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../theme.dart';

/// snake_case or lower case → "Title Case", used for statuses, sources and roles.
String pretty(String? s) {
  if (s == null || s.isEmpty) return '';
  return s
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

String fmtDate(String? iso, [String pattern = 'dd MMM yyyy']) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat(pattern).format(d.toLocal());
}

String fmtDateTime(String? iso) => fmtDate(iso, 'dd MMM, HH:mm');

String lpa(num? v) => v == null ? '—' : '₹ ${v % 1 == 0 ? v.toInt() : v} LPA';

void toast(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Brand.error : Brand.chrome,
      duration: Duration(seconds: error ? 5 : 3),
    ));
}

void toastError(BuildContext context, Object? e) => toast(context, errorMessage(e), error: true);

Future<bool> confirm(BuildContext context, String title, {String? body, String okLabel = 'Confirm', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Brand.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs an action, shows a message on success and the server's reason on failure.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return false;
  }
}

class Loader extends StatelessWidget {
  const Loader({super.key, this.padding = 48});
  final double padding;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.all(padding), child: const Center(child: CircularProgressIndicator()));
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Brand.error, size: 32),
            const SizedBox(height: 12),
            Text(errorMessage(error), textAlign: TextAlign.center, style: const TextStyle(color: Brand.textSoft)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Try again')),
            ],
          ],
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 34, color: Brand.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Brand.textSoft)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}

/// Loads a future and renders it, with a retry on failure and pull-to-refresh.
/// `refreshKey` changes force a reload (e.g. when a filter changes).
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.builder,
    this.refreshKey,
    this.scrollable = true,
    this.padding,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? refreshKey;
  final bool scrollable;
  final EdgeInsets? padding;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(covariant AsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) reload();
  }

  Future<void> reload() async {
    setState(() => _future = widget.load());
    await _future.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Loader();
        if (snap.hasError) return ErrorView(error: snap.error, onRetry: reload);
        final child = widget.builder(context, snap.data as T, reload);
        if (!widget.scrollable) {
          return RefreshIndicator(onRefresh: reload, child: child);
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding ?? const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [child],
          ),
        );
      },
    );
  }
}

/// A titled white card — the page's basic building block.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding});
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null || trailing != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                            ),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ),
        ),
      );
}

/// A small coloured label. Colour carries meaning (status / identity), never decoration.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Brand.textSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color == null ? Brand.borderSoft : c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class StatusTag extends StatelessWidget {
  const StatusTag(this.status, {super.key});
  final String? status;
  @override
  Widget build(BuildContext context) =>
      status == null || status!.isEmpty ? const SizedBox.shrink() : Tag(pretty(status), color: statusColor(status));
}

/// A headline number with a caption, used across the dashboard and report screens.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.hint, this.color, this.icon});
  final String label;
  final String value;
  final String? hint;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: (color ?? Brand.accent).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, size: 14, color: color ?? Brand.accent),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 12, color: Brand.textSoft), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: color ?? Brand.text)),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint!, style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
              ),
          ],
        ),
      );
}

/// Wraps tiles into a responsive grid without needing a fixed aspect ratio.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minWidth = 150});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final columns = (c.maxWidth / minWidth).floor().clamp(1, 4);
          final width = (c.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: children.map((w) => SizedBox(width: width, child: w)).toList(),
          );
        },
      );
}

/// "Label: value" row, for detail screens.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.valueWidget});
  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Text(label, style: const TextStyle(fontSize: 13, color: Brand.textSoft)),
            ),
            Expanded(
              child: valueWidget ??
                  Text(value == null || value!.isEmpty ? '—' : value!, style: const TextStyle(fontSize: 13.5)),
            ),
          ],
        ),
      );
}

/// A skill bar: how far a student is from the level something asks for.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.label,
    required this.progress,
    required this.trailing,
    this.emphasise = false,
    this.met = false,
    this.tooltip,
  });

  final String label;
  final double progress;
  final String trailing;
  final bool emphasise;
  final bool met;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final bar = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(
              emphasise ? '$label *' : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: emphasise ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 7,
                backgroundColor: Brand.borderSoft,
                valueColor: AlwaysStoppedAnimation(met ? Brand.success : (emphasise ? Brand.error : Brand.accent)),
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              trailing,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: met ? Brand.success : Brand.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? bar : Tooltip(message: tooltip!, child: bar);
  }
}

/// A search box that only fires once typing stops.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, required this.onChanged, this.hint = 'Search', this.initial});
  final ValueChanged<String> onChanged;
  final String hint;
  final String? initial;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  DateTime _last = DateTime.now();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final stamp = DateTime.now();
    _last = stamp;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (_last == stamp && mounted) widget.onChanged(v.trim());
    });
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => widget.onChanged(v.trim()),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search, size: 20, color: Brand.muted),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _c.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
        ),
      );
}

/// Horizontal filter chips, e.g. All / Ready / Close / Explore.
class ChipFilter<T> extends StatelessWidget {
  const ChipFilter({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((o) {
            final selected = o.$1 == value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(o.$2),
                selected: selected,
                onSelected: (_) => onChanged(o.$1),
                showCheckmark: false,
                selectedColor: Brand.accent.withValues(alpha: 0.12),
                backgroundColor: Brand.surface,
                side: BorderSide(color: selected ? Brand.accent : Brand.border),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  color: selected ? Brand.accentDark : Brand.textSoft,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      );
}

/// A full-height sheet for forms, so long forms get the whole screen on a phone.
Future<T?> showFormSheet<T>(BuildContext context, String title, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Brand.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: builder(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A banner for something the user should act on (a stale ranking, a pending queue).
class NoteBanner extends StatelessWidget {
  const NoteBanner({super.key, required this.title, this.body, this.color = Brand.info, this.action, this.icon});
  final String title;
  final String? body;
  final Color color;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? Icons.info_outline, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
                  if (body != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(body!, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                    ),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
      );
}

/// A labelled form field, so every sheet lays its inputs out the same way.
class Field extends StatelessWidget {
  const Field(this.label, {super.key, required this.child, this.hint});
  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            child,
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(hint!, style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
              ),
          ],
        ),
      );
}

/// Five stars, read-only or tappable — how every skill level is shown.
class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.onChanged, this.size = 18});
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final filled = i < value;
          final star = Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: filled ? const Color(0xFFD97706) : Brand.border,
          );
          return onChanged == null
              ? star
              : InkWell(
                  onTap: () => onChanged!(i + 1),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(padding: const EdgeInsets.all(2), child: star),
                );
        }),
      );
}
