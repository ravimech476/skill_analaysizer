import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

/// What each category accepts and how big a file may be, mirroring the server's rules.
class FileRule {
  const FileRule(this.extensions, this.maxMb, this.hint, {this.imagesOnly = false});
  final List<String> extensions;
  final int maxMb;
  final String hint;
  final bool imagesOnly;
}

const fileRules = <String, FileRule>{
  'profile_photo': FileRule(['jpg', 'jpeg', 'png', 'webp'], 2, 'JPG, PNG or WebP, up to 2 MB', imagesOnly: true),
  'company_logo': FileRule(['jpg', 'jpeg', 'png', 'webp'], 1, 'JPG, PNG or WebP, up to 1 MB', imagesOnly: true),
  'resume': FileRule(['pdf'], 5, 'PDF, up to 5 MB'),
  'job_description': FileRule(['pdf'], 5, 'PDF, up to 5 MB'),
  'offer_letter': FileRule(['pdf', 'jpg', 'jpeg', 'png', 'webp'], 5, 'PDF or image, up to 5 MB'),
  'certificate': FileRule(['pdf', 'jpg', 'jpeg', 'png', 'webp'], 5, 'PDF or image, up to 5 MB'),
  'student_document': FileRule(['pdf', 'jpg', 'jpeg', 'png', 'webp'], 5, 'PDF or image, up to 5 MB'),
  'notification_attachment': FileRule(['pdf', 'jpg', 'jpeg', 'png', 'webp'], 10, 'PDF or image, up to 10 MB'),
};

/// Picks a file for a category and uploads it. Returns null when the user cancels.
/// Size is checked here too so an over-sized file never leaves the phone.
Future<FileLink?> pickAndUpload(BuildContext context, String category) async {
  final rule = fileRules[category] ?? const FileRule(['pdf'], 5, 'Up to 5 MB');
  try {
    Uint8List? bytes;
    String name;
    String? path;

    if (rule.imagesOnly) {
      final source = await _askImageSource(context);
      if (source == null) return null;
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 88);
      if (picked == null) return null;
      name = picked.name;
      path = kIsWeb ? null : picked.path;
      if (kIsWeb) bytes = await picked.readAsBytes();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: rule.extensions,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return null;
      final f = result.files.first;
      name = f.name;
      path = f.path;
      bytes = f.bytes;
      if (path == null && bytes == null) {
        if (context.mounted) toast(context, 'Could not read that file', error: true);
        return null;
      }
    }

    final size = bytes?.length ?? await _sizeOf(path!);
    if (size > rule.maxMb * 1024 * 1024) {
      if (context.mounted) toast(context, 'That file is too large. ${rule.hint}.', error: true);
      return null;
    }

    final part = bytes != null
        ? MultipartFile.fromBytes(bytes, filename: name)
        : await MultipartFile.fromFile(path!, filename: name);
    return await filesApi.upload(category, part);
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return null;
  }
}

Future<int> _sizeOf(String path) async {
  try {
    return await XFile(path).length();
  } catch (_) {
    return 0;
  }
}

Future<ImageSource?> _askImageSource(BuildContext context) async {
  if (kIsWeb) return ImageSource.gallery;
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

/// Opens a signed file link in the browser / system viewer.
Future<void> openFile(BuildContext context, FileLink link, {bool download = false}) async {
  final uri = Uri.parse(api.fileUrl(link.url, download: download));
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) toast(context, 'Could not open that file', error: true);
  }
}

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) toast(context, 'Could not open that link', error: true);
  }
}

/// A person's photo, or their initials on a soft tint of a colour derived from the name.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.name, this.photo, this.radius = 20});
  final String? name;
  final FileLink? photo;
  final double radius;

  static Color colorFor(String? name) {
    if (name == null || name.isEmpty) return Brand.textSoft;
    final hash = name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
    return Brand.series[hash % Brand.series.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(name);
    final initials = (name ?? '?')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.12),
      foregroundImage: photo == null ? null : NetworkImage(api.fileUrl(photo!.url)),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: radius * 0.72),
      ),
    );
  }
}

/// A tappable file row: name, size and an open action.
class FileTile extends StatelessWidget {
  const FileTile({super.key, required this.link, this.label, this.onRemove, this.dense = false});
  final FileLink link;
  final String? label;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openFile(context, link),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 6 : 10),
          decoration: BoxDecoration(
            border: Border.all(color: Brand.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(link.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
                  size: 18, color: Brand.textSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label ?? link.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    if (!dense)
                      Text(link.sizeLabel, style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Brand.error),
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                )
              else
                const Icon(Icons.open_in_new, size: 15, color: Brand.muted),
            ],
          ),
        ),
      );
}

/// Attach / replace / remove one file slot (a photo, a resume, a JD…).
class FileSlot extends StatefulWidget {
  const FileSlot({
    super.key,
    required this.category,
    required this.current,
    required this.onChanged,
    this.label,
    this.canEdit = true,
  });

  final String category;
  final FileLink? current;

  /// Called with the uploaded file's id, or null when the file is removed.
  final Future<void> Function(int? fileId, FileLink? link) onChanged;
  final String? label;
  final bool canEdit;

  @override
  State<FileSlot> createState() => _FileSlotState();
}

class _FileSlotState extends State<FileSlot> {
  bool _busy = false;

  Future<void> _pick() async {
    setState(() => _busy = true);
    final uploaded = await pickAndUpload(context, widget.category);
    if (uploaded != null) {
      await runAction(context, () => widget.onChanged(uploaded.id, uploaded), success: 'Saved');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    if (!await confirm(context, 'Remove this file?', danger: true, okLabel: 'Remove')) return;
    setState(() => _busy = true);
    await runAction(context, () => widget.onChanged(null, null), success: 'Removed');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final rule = fileRules[widget.category];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(widget.label!,
                style: const TextStyle(fontSize: 12.5, color: Brand.textSoft, fontWeight: FontWeight.w500)),
          ),
        if (widget.current != null)
          FileTile(link: widget.current!, onRemove: widget.canEdit && !_busy ? _remove : null)
        else
          Text(rule?.hint ?? 'No file attached', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
        if (widget.canEdit) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: _busy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(widget.current == null ? 'Attach' : 'Replace'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
          ),
        ],
      ],
    );
  }
}
