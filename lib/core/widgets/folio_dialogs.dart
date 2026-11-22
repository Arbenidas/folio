import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../../features/editor/presentation/widgets/editor_motion.dart';

/// Modern macOS-style text input dialog matching Folio's theme and style.
Future<String?> showFolioPromptDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String confirmLabel = 'Aceptar',
  IconData icon = CupertinoIcons.pencil,
  int? maxLength,
}) async {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  final result = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    animationStyle: EditorMotion.dialog(context),
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      final style = FolioStyle.of(dialogContext);
      return Dialog(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: style.isGraphic
            ? style.outline
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant),
              ),
        child: SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 15,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                CupertinoTextField(
                  autofocus: true,
                  controller: controller,
                  placeholder: hint,
                  maxLength: maxLength,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  style: TextStyle(fontSize: 13.5, color: colors.onSurface),
                  placeholderStyle: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.6),
                      width: 1.3,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  onSubmitted: (text) => Navigator.pop(dialogContext, text),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '↵ confirmar · Esc cancelar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  // Dispose after route exit animation settles.
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 220)).then((_) {
      controller.dispose();
    }),
  );
  return result;
}

/// Modern macOS-style confirmation dialog for destructive or important actions.
Future<bool> showFolioConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    animationStyle: EditorMotion.dialog(context),
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      final style = FolioStyle.of(dialogContext);
      final accentBg = destructive
          ? colors.errorContainer.withValues(alpha: 0.85)
          : colors.primaryContainer;
      final accentFg = destructive ? colors.error : colors.onPrimaryContainer;
      return Dialog(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: style.isGraphic
            ? style.outline
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.outlineVariant),
              ),
        child: SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accentBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        destructive
                            ? CupertinoIcons.trash
                            : CupertinoIcons.info_circle,
                        size: 15,
                        color: accentFg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: destructive
                            ? colors.error
                            : colors.primary,
                        foregroundColor: destructive
                            ? colors.onError
                            : colors.onPrimary,
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(actionLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class FolioPickerItem<T> {
  const FolioPickerItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon = CupertinoIcons.doc_text,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData icon;
}

/// Native macOS-style searchable list picker dialog (replaces iOS bottom action sheets).
Future<T?> showFolioPickerDialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<FolioPickerItem<T>> items,
  String emptyMessage = 'No hay elementos disponibles.',
  IconData icon = CupertinoIcons.link,
  bool searchable = true,
}) async {
  final searchController = TextEditingController();
  final result = await showDialog<T>(
    context: context,
    useRootNavigator: true,
    animationStyle: EditorMotion.dialog(context),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        final colors = Theme.of(dialogContext).colorScheme;
        final style = FolioStyle.of(dialogContext);
        final query = searchController.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? items
            : items.where((item) {
                return item.title.toLowerCase().contains(query) ||
                    (item.subtitle?.toLowerCase().contains(query) ?? false);
              }).toList();

        return Dialog(
          backgroundColor: colors.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          elevation: 18,
          shape: style.isGraphic
              ? style.outline
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colors.outlineVariant),
                ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(
                            alpha: 0.85,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: 15,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (searchable && items.length > 4) ...[
                    const SizedBox(height: 12),
                    CupertinoSearchTextField(
                      controller: searchController,
                      autofocus: true,
                      placeholder: 'Filtrar…',
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 13, color: colors.onSurface),
                      placeholderStyle: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                      itemColor: colors.onSurfaceVariant,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                emptyMessage,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return _PickerOptionRow(
                                item: item,
                                onTap: () =>
                                    Navigator.pop(dialogContext, item.value),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 220)).then((_) {
      searchController.dispose();
    }),
  );
  return result;
}

class _PickerOptionRow<T> extends StatefulWidget {
  const _PickerOptionRow({required this.item, required this.onTap});

  final FolioPickerItem<T> item;
  final VoidCallback onTap;

  @override
  State<_PickerOptionRow<T>> createState() => _PickerOptionRowState<T>();
}

class _PickerOptionRowState<T> extends State<_PickerOptionRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onTap,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.secondaryContainer
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _hovered
                  ? colors.primary.withValues(alpha: 0.45)
                  : colors.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.item.icon,
                size: 15,
                color: _hovered ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _hovered
                            ? colors.onSecondaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    if (widget.item.subtitle case final sub?)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _hovered
                              ? colors.onSecondaryContainer.withValues(
                                  alpha: 0.8,
                                )
                              : colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 13,
                color: colors.onSurfaceVariant.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modern macOS-style informational alert dialog.
Future<void> showFolioMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'Listo',
  IconData icon = CupertinoIcons.checkmark_circle_fill,
}) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  animationStyle: EditorMotion.dialog(context),
  builder: (dialogContext) {
    final colors = Theme.of(dialogContext).colorScheme;
    final style = FolioStyle.of(dialogContext);
    return Dialog(
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: style.isGraphic
          ? style.outline
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 16,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

