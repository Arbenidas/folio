import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../editor/presentation/widgets/editor_motion.dart';
import '../../editor/presentation/widgets/markdown_preview.dart';
import '../data/blog_connection.dart';
import '../data/blog_publication.dart';
import 'blog_account.dart';

class BlogPublishDialog extends ConsumerStatefulWidget {
  const BlogPublishDialog({
    super.key,
    required this.noteId,
    required this.noteTitle,
    required this.markdown,
    required this.readImage,
  });

  final String noteId;
  final String noteTitle;
  final String markdown;
  final Future<Uint8List?> Function(String path) readImage;

  @override
  ConsumerState<BlogPublishDialog> createState() => _BlogPublishDialogState();
}

class _BlogPublishDialogState extends ConsumerState<BlogPublishDialog> {
  late final _title = TextEditingController(text: widget.noteTitle);
  late final _slug = TextEditingController(text: blogSlug(widget.noteTitle));
  final _description = TextEditingController();
  final _tags = TextEditingController();
  final _detailsScroll = ScrollController();
  final _previewScroll = ScrollController();
  bool _showPreview = false;
  BlogCategory _category = BlogCategory.log;
  BlogCover? _cover;
  bool _preparingCover = false;
  bool _manualSlug = false;
  bool _publishing = false;
  bool _copied = false;
  String? _error;
  String _progress = '';
  Uri? _url;
  late Future<List<BlogCapture>> _captures = _prepare();

  Future<List<BlogCapture>> _prepare() =>
      prepareBlogCaptures(widget.markdown, widget.readImage);

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    _description.dispose();
    _tags.dispose();
    _detailsScroll.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  BlogPublication _publication(List<BlogCapture> captures) => BlogPublication(
    noteId: widget.noteId,
    markdown: widget.markdown,
    title: _title.text.trim(),
    description: _description.text.trim(),
    slug: _slug.text.trim(),
    category: _category,
    tags: _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(),
    captures: captures,
    cover: _cover,
  );

  Future<void> _chooseCover() async {
    setState(() {
      _preparingCover = true;
      _error = null;
    });
    try {
      final cover = await pickBlogCover();
      if (mounted && cover != null) setState(() => _cover = cover);
    } on BlogFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo leer el banner. Prueba con otra imagen.',
        );
      }
    } finally {
      if (mounted) setState(() => _preparingCover = false);
    }
  }

  Future<void> _publish(
    BlogConnection connection,
    String authorId,
    List<BlogCapture> captures,
  ) async {
    if (_publishing) return;
    final publication = _publication(captures);
    setState(() {
      _publishing = true;
      _error = null;
      _progress = 'Conectando con arbe.blog…';
    });
    try {
      final url = await publication.publish(connection, authorId, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (mounted) setState(() => _url = url);
    } on BlogFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo completar la publicación. Vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _linkAction(Future<bool> Function() action, String error) async {
    try {
      if (await action()) return;
    } catch (_) {
      // Keep the selectable URL available even if macOS rejects the action.
    }
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return PopScope(
      canPop: !_publishing,
      child: Dialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: style.isGraphic
            ? style.outline
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.outlineVariant),
              ),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: _url == null ? 980 : 480,
          height: _url == null ? 680 : null,
          child: _url != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: _success(context, _url!),
                )
              : ref
                    .watch(blogConnectionProvider)
                    .when(
                      loading: () => _body(
                        const Center(child: CupertinoActivityIndicator()),
                      ),
                      error: (_, _) => _body(
                        const Center(
                          child: Text('No se pudo conectar con arbe.blog.'),
                        ),
                      ),
                      data: (connection) => connection == null
                          ? _body(
                              const Center(
                                child: Text('Integración no disponible.'),
                              ),
                            )
                          : _connected(connection),
                    ),
        ),
      ),
    );
  }

  Widget _connected(BlogConnection connection) => StreamBuilder(
    stream: connection.authChanges,
    builder: (context, _) {
      final user = connection.session?.user;
      if (user == null && !_publishing) {
        return _body(const SingleChildScrollView(child: BlogAccountPanel()));
      }
      return FutureBuilder(
        future: _captures,
        builder: (context, snapshot) {
          final captures = snapshot.data;
          final colors = Theme.of(context).colorScheme;
          final canPublish =
              !_publishing &&
              !_preparingCover &&
              _title.text.trim().isNotEmpty &&
              user != null &&
              captures != null &&
              !snapshot.hasError &&
              snapshot.connectionState == ConnectionState.done;
          return _body(
            _review(captures),
            author: user == null ? null : blogAuthorLabel(user),
            status: _captureStatus(snapshot),
            publishButton: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                disabledBackgroundColor: colors.surfaceContainerHighest,
                disabledForegroundColor: colors.onSurfaceVariant,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: canPublish
                  ? () => _publish(connection, user.id, captures)
                  : null,
              icon: _publishing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  : const Icon(CupertinoIcons.paperplane_fill, size: 14),
              label: Text(_publishing ? 'Publicando…' : 'Publicar ahora'),
            ),
          );
        },
      );
    },
  );

  Widget _body(
    Widget content, {
    String? author,
    Widget? status,
    Widget? publishButton,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 14, 15),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.globe,
                  size: 18,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Publicar en arbe.blog',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'El artículo y sus imágenes serán públicos en el blog.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (author != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  flex: 0,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.person_crop_circle,
                          size: 14,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              AppIconButton(
                semanticLabel: 'Cerrar publicación',
                icon: CupertinoIcons.xmark,
                size: 16,
                onPressed: _publishing ? null : () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: content,
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(liveRegion: true, child: _errorLabel(colors)),
                ),
              Row(
                children: [
                  if (status != null)
                    Expanded(child: status)
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    onPressed: _publishing
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (publishButton != null) ...[
                    const SizedBox(width: 8),
                    publishButton,
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _captureStatus(AsyncSnapshot<List<BlogCapture>> snapshot) {
    final colors = Theme.of(context).colorScheme;
    if (snapshot.hasError) {
      final error = snapshot.error;
      return Semantics(
        liveRegion: true,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              error is BlogFailure
                  ? error.message
                  : 'No se pudieron preparar las capturas.',
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
            TextButton(
              onPressed: () => setState(() => _captures = _prepare()),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final count = snapshot.data?.length ?? 0;
    final String label;
    final IconData icon;
    if (_publishing) {
      label = _progress;
      icon = CupertinoIcons.cloud_upload;
    } else if (snapshot.connectionState != ConnectionState.done) {
      label = 'Preparando capturas…';
      icon = CupertinoIcons.photo;
    } else {
      label = switch (count) {
        0 => 'Sin capturas adjuntas',
        1 => '1 captura lista para publicar',
        _ => '$count capturas listas para publicar',
      };
      icon = CupertinoIcons.photo;
    }
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _review(List<BlogCapture>? captures) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 740;
      final details = _details(captures ?? const [], showHeading: wide);
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 344, child: details),
            const SizedBox(width: 18),
            Expanded(child: _preview(captures, showHeading: true)),
          ],
        );
      }

      final colors = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoSlidingSegmentedControl<bool>(
            groupValue: _showPreview,
            backgroundColor: colors.surfaceContainerHigh,
            thumbColor: colors.surfaceContainerLowest,
            children: const {
              false: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                child: Text('Detalles', style: TextStyle(fontSize: 12.5)),
              ),
              true: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                child: Text('Vista previa', style: TextStyle(fontSize: 12.5)),
              ),
            },
            onValueChanged: (value) {
              if (value != null) setState(() => _showPreview = value);
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: IndexedStack(
              index: _showPreview ? 1 : 0,
              sizing: StackFit.expand,
              children: [
                ExcludeFocus(excluding: _showPreview, child: details),
                ExcludeFocus(
                  excluding: !_showPreview,
                  child: _preview(captures, showHeading: false),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _details(List<BlogCapture> captures, {required bool showHeading}) {
    final colors = Theme.of(context).colorScheme;
    return RawScrollbar(
      controller: _detailsScroll,
      thumbColor: colors.onSurfaceVariant.withValues(alpha: 0.35),
      radius: const Radius.circular(4),
      thickness: 4,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          key: const PageStorageKey('blog-publication-details'),
          controller: _detailsScroll,
          padding: const EdgeInsets.fromLTRB(2, 2, 12, 12),
          children: [
            if (showHeading) ...[
              _sectionHeader('DATOS DEL ARTÍCULO', colors),
              const SizedBox(height: 12),
            ],
            _modernField(
              label: 'Título',
              controller: _title,
              hint: 'Título visible en el blog',
              onChanged: (value) {
                if (!_manualSlug) _slug.text = blogSlug(value);
                setState(() {});
              },
            ),
            const SizedBox(height: 14),
            _fieldLabel('Categoría', colors),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final category in BlogCategory.values)
                  _categoryPill(category, colors),
              ],
            ),
            const SizedBox(height: 14),
            _modernField(
              label: 'Identificador en la URL',
              controller: _slug,
              hint: 'mi-articulo',
              monospace: true,
              onChanged: (_) {
                _manualSlug = true;
                setState(() {});
              },
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.link,
                    size: 12,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      _publication(const []).previewUrl.toString(),
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionHeader('OPCIONALES', colors),
            const SizedBox(height: 12),
            _coverPicker(),
            const SizedBox(height: 14),
            _modernField(
              label: 'Resumen',
              controller: _description,
              hint: 'Breve descripción para SEO y tarjeta del blog…',
              lines: 2,
            ),
            const SizedBox(height: 14),
            _modernField(
              label: 'Palabras clave',
              controller: _tags,
              hint: 'flutter, dart, arquitectura',
            ),
            if (captures.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionHeader('CAPTURAS ADJUNTAS (${captures.length})', colors),
              const SizedBox(height: 8),
              for (final capture in captures)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.memory(
                          capture.bytes,
                          width: 44,
                          height: 34,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              capture.alt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            if (capture.resized)
                              Text(
                                'Optimizada para la web',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, ColorScheme colors) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w700,
      color: colors.onSurfaceVariant,
    ),
  );

  Widget _fieldLabel(String label, ColorScheme colors) => Text(
    label,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colors.onSurface,
    ),
  );

  Widget _categoryPill(BlogCategory category, ColorScheme colors) {
    final selected = _category == category;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: _publishing
          ? null
          : () => setState(() => _category = category),
      child: AnimatedContainer(
        duration: EditorMotion.duration(context, 140),
        curve: EditorMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          category.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _coverPicker() {
    final colors = Theme.of(context).colorScheme;
    final cover = _cover;
    final busy = _publishing || _preparingCover;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Imagen de portada', colors),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cover != null)
                Stack(
                  children: [
                    Image.memory(
                      cover.bytes,
                      height: 92,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          onPressed: busy
                              ? null
                              : () => setState(() => _cover = null),
                          child: Text(
                            'Quitar',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: Size.zero,
                onPressed: busy ? null : _chooseCover,
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.photo_on_rectangle,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _preparingCover
                            ? 'Preparando imagen…'
                            : cover == null
                            ? 'Elegir imagen de portada…'
                            : cover.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: cover == null
                              ? colors.primary
                              : colors.onSurface,
                        ),
                      ),
                    ),
                    if (cover != null)
                      Text(
                        'Cambiar',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(List<BlogCapture>? captures, {required bool showHeading}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cover = _cover;
    final title = _title.text.trim();
    final byPath = {
      for (final item in captures ?? const <BlogCapture>[])
        item.path: item.bytes,
    };
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeading)
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(bottom: BorderSide(color: colors.outlineVariant)),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.eye,
                    size: 13.5,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Vista previa',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _category.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: MarkdownPreview(
              key: ObjectKey(captures),
              content: widget.markdown,
              controller: _previewScroll,
              noteId: widget.noteId,
              readImage: (_, path) async => byPath[path],
              compact: true,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cover != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(
                        cover.bytes,
                        height: 140,
                        fit: BoxFit.cover,
                        semanticLabel: 'Portada del artículo',
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    title.isEmpty ? 'Artículo sin título' : title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernField({
    required String label,
    required TextEditingController controller,
    int lines = 1,
    String? hint,
    bool monospace = false,
    ValueChanged<String>? onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: colors.primary, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, colors),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_publishing,
          onChanged: onChanged,
          maxLines: lines,
          style: TextStyle(
            fontSize: monospace ? 12.5 : 13.5,
            fontFamily: monospace ? 'Menlo' : null,
            color: colors.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12.5,
              color: colors.onSurfaceVariant.withValues(alpha: 0.65),
            ),
            isDense: true,
            filled: true,
            fillColor: colors.surfaceContainerLowest,
            border: enabledBorder,
            enabledBorder: enabledBorder,
            focusedBorder: focusedBorder,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorLabel(ColorScheme colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: colors.errorContainer.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      _error!,
      style: TextStyle(color: colors.error, fontSize: 12),
    ),
  );

  Widget _success(BuildContext context, Uri url) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                CupertinoIcons.checkmark_alt_circle_fill,
                size: 20,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Artículo publicado',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: SelectableText(
            url.toString(),
            style: TextStyle(
              fontFamily: 'Menlo',
              fontSize: 12,
              color: colors.primary,
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _errorLabel(colors),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _linkAction(
                () => launchUrl(url, mode: LaunchMode.externalApplication),
                'No se pudo abrir el enlace.',
              ),
              icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 15),
              label: const Text('Abrir artículo'),
            ),
            OutlinedButton.icon(
              onPressed: () => _linkAction(() async {
                await Clipboard.setData(ClipboardData(text: url.toString()));
                if (mounted) setState(() => _copied = true);
                return true;
              }, 'No se pudo copiar el enlace.'),
              icon: Icon(
                _copied ? CupertinoIcons.check_mark : CupertinoIcons.doc_on_doc,
                size: 14,
              ),
              label: Text(_copied ? 'Enlace copiado' : 'Copiar enlace'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        ),
      ],
    );
  }
}
