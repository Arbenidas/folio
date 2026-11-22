import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../finance/domain/finance_models.dart';
import '../data/patch_notes_service.dart';

Future<void> showPatchNotesDialog(
  BuildContext context, {
  PatchNotesService? service,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        child: PatchNotesPanel(
          service: service ?? PatchNotesService.instance,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

class PatchNotesPanel extends StatefulWidget {
  const PatchNotesPanel({
    super.key,
    required this.service,
    this.onClose,
  });

  final PatchNotesService service;
  final VoidCallback? onClose;

  @override
  State<PatchNotesPanel> createState() => _PatchNotesPanelState();
}

class _PatchNotesPanelState extends State<PatchNotesPanel> {
  UpdateCheckResult? _result;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final bundled = await widget.service.loadBundledNotes();
    if (mounted && _result == null) {
      setState(() => _result = UpdateCheckResult(notes: bundled));
    }
    final fresh = await widget.service.checkForUpdates();
    final highestBuild = fresh.notes.isNotEmpty
        ? fresh.notes.first.build
        : AppVersionInfo.currentBuild;
    await widget.service.markPatchNotesSeen(highestBuild);
    if (mounted) {
      setState(() {
        _result = fresh;
        _checking = false;
      });
    }
  }

  Future<void> _openDownload() async {
    final url = widget.service.downloadUrlForCurrentPlatform(_result?.manifest);
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final result = _result;
    final notes = result?.notes ?? const <PatchNoteEntry>[];
    final hasUpdate = result?.hasUpdate == true;
    final manifest = result?.manifest;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.new_releases_rounded,
                    size: 19,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notas de parche',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        'Folio v${AppVersionInfo.currentVersion} (build ${AppVersionInfo.currentBuild})${kIsWeb ? ' · Web' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: Size.zero,
                  onPressed: _checking ? null : _refresh,
                  child: _checking
                      ? const CupertinoActivityIndicator(radius: 8)
                      : Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    onPressed: widget.onClose,
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),

          // Live Update Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: hasUpdate
                    ? palette.accent.withValues(alpha: 0.12)
                    : palette.cardBg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: hasUpdate
                      ? palette.accent.withValues(alpha: 0.45)
                      : palette.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasUpdate
                        ? Icons.system_update_rounded
                        : Icons.verified_rounded,
                    size: 20,
                    color: hasUpdate ? palette.accent : palette.positive,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasUpdate
                              ? 'Nueva actualización disponible · v${manifest!.version} (build ${manifest.build})'
                              : _checking
                              ? 'Buscando actualizaciones en GitHub…'
                              : 'Tu app está al día',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          hasUpdate
                              ? (manifest!.summary.isNotEmpty
                                    ? manifest.summary
                                    : 'Hay nuevos cambios publicados desde git listos para descargar.')
                              : 'Cada push a main publica nuevas notas y compilación automática.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasUpdate) ...[
                    const SizedBox(width: 10),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      borderRadius: BorderRadius.circular(9),
                      onPressed: _openDownload,
                      child: Text(
                        widget.service.downloadLabelForCurrentPlatform(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Patch Notes Timeline
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      'Aún no hay notas de parche registradas.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _PatchNoteCard(
                      entry: notes[index],
                      isLatest: index == 0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PatchNoteCard extends StatelessWidget {
  const _PatchNoteCard({
    required this.entry,
    required this.isLatest,
  });

  final PatchNoteEntry entry;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLatest ? palette.accent.withValues(alpha: 0.45) : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isLatest ? palette.accent : colors.onSurfaceVariant)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  'v${entry.version}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isLatest ? palette.accent : colors.onSurface,
                  ),
                ),
              ),
              if (entry.tag.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.purple.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    entry.tag,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: palette.purple,
                    ),
                  ),
                ),
              if (entry.date.isNotEmpty)
                Text(
                  entry.date,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (entry.title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ],
          if (entry.highlights.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final line in entry.highlights)
              _BulletLine(text: line, color: palette.positive),
          ],
          if (entry.fixes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'CORRECCIONES',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            for (final line in entry.fixes)
              _BulletLine(text: line, color: palette.warning),
          ],
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.38,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
