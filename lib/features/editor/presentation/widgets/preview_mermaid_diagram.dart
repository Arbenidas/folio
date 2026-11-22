import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Builds the `mermaid.ink` PNG URL using pure 7-bit ASCII-escaped JSON
/// (`\uXXXX` for any UTF-16 code unit > 0x7F) so Spanish accents, symbols, and
/// emojis decode cleanly across Web, macOS, iOS, and Android with zero `dart:io`.
String buildMermaidInkUrl(
  String source, {
  required bool isDark,
  required Color backgroundColor,
}) {
  final payload = jsonEncode({
    'code': source,
    'mermaid': {'theme': isDark ? 'dark' : 'default'},
  });
  final asciiBuf = StringBuffer();
  for (final unit in payload.codeUnits) {
    if (unit > 0x7F) {
      asciiBuf.write('\\u');
      asciiBuf.write(unit.toRadixString(16).padLeft(4, '0'));
    } else {
      asciiBuf.writeCharCode(unit);
    }
  }
  final b64 = base64Url
      .encode(ascii.encode(asciiBuf.toString()))
      .replaceAll('=', '');
  final bgHex = _colorToHexRgb(backgroundColor);
  return 'https://mermaid.ink/img/$b64?type=png&bgColor=!$bgHex';
}

String _colorToHexRgb(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '$r$g$b'.toUpperCase();
}

String detectMermaidKindLabel(String source) {
  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('%%')) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('flowchart') || lower.startsWith('graph')) {
      return 'Diagrama de flujo';
    }
    if (lower.startsWith('sequencediagram')) return 'Secuencia';
    if (lower.startsWith('classdiagram')) return 'Clases';
    if (lower.startsWith('statediagram')) return 'Estados';
    if (lower.startsWith('erdiagram')) return 'Entidad-Relación';
    if (lower.startsWith('gantt')) return 'Gantt';
    if (lower.startsWith('pie')) return 'Pastel';
    if (lower.startsWith('mindmap')) return 'Mapa mental';
    if (lower.startsWith('timeline')) return 'Línea de tiempo';
    if (lower.startsWith('gitgraph')) return 'Git Graph';
    if (lower.startsWith('xychart')) return 'Gráfica XY';
    break;
  }
  return 'Diagrama';
}

/// Renders a ` ```mermaid ` code fence in Markdown previews across macOS, Web,
/// Android, and iOS. Uses `mermaid.ink` with LRU in-memory caching for full
/// Mermaid spec support, and falls back to an instant offline native flowchart
/// renderer when no internet connection is available.
class PreviewMermaidDiagram extends StatefulWidget {
  const PreviewMermaidDiagram({
    super.key,
    required this.source,
    this.title,
  });

  final String source;
  final String? title;

  @override
  State<PreviewMermaidDiagram> createState() => _PreviewMermaidDiagramState();
}

class _PreviewMermaidDiagramState extends State<PreviewMermaidDiagram> {
  static final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();
  static const int _maxCacheEntries = 48;

  bool _showSource = false;
  bool _loading = false;
  String? _error;
  Uint8List? _bytes;
  String? _activeCacheKey;
  Timer? _fetchDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant PreviewMermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _ensureLoaded(debounced: true);
    }
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    super.dispose();
  }

  void _ensureLoaded({bool debounced = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = theme.colorScheme.surfaceContainerLow;
    final url = buildMermaidInkUrl(
      widget.source,
      isDark: isDark,
      backgroundColor: bg,
    );
    if (_activeCacheKey == url && (_bytes != null || _loading)) return;
    _activeCacheKey = url;

    final cached = _cache[url];
    if (cached != null) {
      _fetchDebounce?.cancel();
      if (_bytes != cached || _loading || _error != null) {
        setState(() {
          _bytes = cached;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    _fetchDebounce?.cancel();
    if (debounced) {
      _fetchDebounce = Timer(
        const Duration(milliseconds: 360),
        () => unawaited(_fetchDiagram(url)),
      );
    } else {
      unawaited(_fetchDiagram(url));
    }
  }

  Future<void> _fetchDiagram(String url) async {
    if (!mounted || _activeCacheKey != url) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (!mounted || _activeCacheKey != url) return;
      if (response.statusCode == 200 && response.bodyBytes.length > 64) {
        _putCache(url, response.bodyBytes);
        setState(() {
          _bytes = response.bodyBytes;
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'No se pudo renderizar en línea (${response.statusCode}).';
        });
      }
    } catch (_) {
      if (!mounted || _activeCacheKey != url) return;
      setState(() {
        _loading = false;
        _error = 'Sin conexión para renderizar Mermaid en línea.';
      });
    }
  }

  static void _putCache(String key, Uint8List bytes) {
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _openExpanded(BuildContext context) {
    final bytes = _bytes;
    final parsed = _SimpleFlowchart.tryParse(widget.source);
    if (bytes == null && parsed == null) return;
    final colors = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: SizedBox(
          width: math.min(980, MediaQuery.sizeOf(context).width - 48),
          height: math.min(680, MediaQuery.sizeOf(context).height - 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title?.isNotEmpty == true
                            ? widget.title!
                            : 'Mermaid · ${detectMermaidKindLabel(widget.source)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      'Pellizca o usa scroll para hacer zoom',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.4,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: bytes != null
                          ? Image.memory(bytes, fit: BoxFit.contain)
                          : _NativeFlowchartView(chart: parsed!),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kindLabel = detectMermaidKindLabel(widget.source);
    final parsedFallback = _SimpleFlowchart.tryParse(widget.source);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header bar
        ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.title?.isNotEmpty == true
                          ? '${widget.title} · Mermaid'
                          : 'Mermaid · $kindLabel',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniPillButton(
                      label: _showSource ? 'Diagrama' : 'Código',
                      icon: _showSource
                          ? Icons.account_tree_outlined
                          : Icons.code_rounded,
                      onTap: () => setState(() => _showSource = !_showSource),
                    ),
                    if (!_showSource &&
                        (_bytes != null || parsedFallback != null)) ...[
                      const SizedBox(width: 6),
                      _MiniPillButton(
                        label: 'Ampliar',
                        icon: Icons.open_in_full_rounded,
                        onTap: () => _openExpanded(context),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        // Body
        if (_showSource)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.source,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12,
                height: 1.55,
                color: colors.onSurface,
              ),
            ),
          )
        else if (_bytes != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: GestureDetector(
              onTap: () => _openExpanded(context),
              child: MouseRegion(
                cursor: SystemMouseCursors.zoomIn,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 540),
                    child: Image.memory(
                      _bytes!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (parsedFallback != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: Center(child: _NativeFlowchartView(chart: parsedFallback)),
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const CupertinoActivityIndicator(radius: 6),
                        const SizedBox(width: 6),
                        Text(
                          'Mejorando con Mermaid…',
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
          )
        else if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 10),
                Text(
                  'Renderizando diagrama Mermaid…',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error ?? 'No se pudo cargar el diagrama Mermaid.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final key = _activeCacheKey;
                        if (key != null) unawaited(_fetchDiagram(key));
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: SelectableText(
                    widget.source,
                    style: TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 11.5,
                      height: 1.5,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniPillButton extends StatelessWidget {
  const _MiniPillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Offline / instant native Flutter flowchart renderer (pure Dart)
// Supports `flowchart TD/TB/LR` & `graph TD/TB/LR` with boxes, rounded nodes,
// diamonds, edges (`-->`, `---`, `-.->`), and edge labels (`-->|label|`).
// ---------------------------------------------------------------------------

class _FlowNode {
  _FlowNode(this.id, this.label, {this.isDiamond = false, this.isPill = false});
  final String id;
  String label;
  bool isDiamond;
  bool isPill;
}

class _FlowEdge {
  const _FlowEdge(this.from, this.to, {this.label, this.dashed = false});
  final String from;
  final String to;
  final String? label;
  final bool dashed;
}

class _SimpleFlowchart {
  const _SimpleFlowchart({
    required this.horizontal,
    required this.nodes,
    required this.edges,
  });

  final bool horizontal;
  final Map<String, _FlowNode> nodes;
  final List<_FlowEdge> edges;

  static final _headerRe = RegExp(
    r'^(?:flowchart|graph)\s+(TD|TB|BT|LR|RL)\b',
    caseSensitive: false,
  );
  static final _edgeSplitRe = RegExp(
    r'(-->|-.->|==>|--|---)(?:\|([^|]*)\|)?',
  );
  static final _nodeRe = RegExp(
    r'''^([A-Za-z0-9_.-]+)\s*(?:\(\[([^\]]*)\]\)|\(\(([^)]*)\)\)|\[(?:"([^"]*)"|([^\]]*))\]|\((?:"([^"]*)"|([^)]*))\)|\{(?:"([^"]*)"|([^}]*))\})?$''',
  );

  static _SimpleFlowchart? tryParse(String source) {
    final lines = source.split('\n');
    bool? horizontal;
    final nodes = <String, _FlowNode>{};
    final edges = <_FlowEdge>[];

    void upsertNode(String token) {
      final clean = token.trim().replaceAll(RegExp(r';$'), '').trim();
      if (clean.isEmpty) return;
      final m = _nodeRe.firstMatch(clean);
      if (m == null) return;
      final id = m.group(1)!;
      final pill = m.group(2) ?? m.group(3);
      final box = m.group(4) ?? m.group(5);
      final rounded = m.group(6) ?? m.group(7);
      final diamond = m.group(8) ?? m.group(9);
      final label = (pill ?? box ?? rounded ?? diamond)?.trim();
      final existing = nodes[id];
      if (existing == null) {
        nodes[id] = _FlowNode(
          id,
          (label != null && label.isNotEmpty) ? label : id,
          isDiamond: diamond != null,
          isPill: pill != null || rounded != null,
        );
      } else if (label != null && label.isNotEmpty) {
        existing.label = label;
        if (diamond != null) existing.isDiamond = true;
        if (pill != null || rounded != null) existing.isPill = true;
      }
    }

    String? extractId(String token) {
      final clean = token.trim().replaceAll(RegExp(r';$'), '').trim();
      final m = _nodeRe.firstMatch(clean);
      return m?.group(1);
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty ||
          line.startsWith('%%') ||
          line.startsWith('subgraph') ||
          line == 'end' ||
          line.startsWith('style ') ||
          line.startsWith('classDef ') ||
          line.startsWith('class ')) {
        continue;
      }
      if (horizontal == null) {
        final hm = _headerRe.firstMatch(line);
        if (hm == null) return null;
        final dir = hm.group(1)!.toUpperCase();
        horizontal = dir == 'LR' || dir == 'RL';
        continue;
      }

      final matches = _edgeSplitRe.allMatches(line).toList();
      if (matches.isEmpty) {
        upsertNode(line);
        continue;
      }

      var cursor = 0;
      String? prevId;
      for (final m in matches) {
        final leftToken = line.substring(cursor, m.start);
        upsertNode(leftToken);
        final leftId = extractId(leftToken) ?? prevId;
        final connector = m.group(1)!;
        final edgeLabel = m.group(2)?.trim();
        cursor = m.end;
        // Peek next boundary
        final nextIdx = matches.indexOf(m) + 1;
        final rightEnd = nextIdx < matches.length
            ? matches[nextIdx].start
            : line.length;
        final rightToken = line.substring(cursor, rightEnd);
        upsertNode(rightToken);
        final rightId = extractId(rightToken);
        if (leftId != null && rightId != null) {
          edges.add(
            _FlowEdge(
              leftId,
              rightId,
              label: (edgeLabel != null && edgeLabel.isNotEmpty)
                  ? edgeLabel
                  : null,
              dashed: connector.contains('.'),
            ),
          );
          prevId = rightId;
        }
      }
    }

    if (horizontal == null || nodes.isEmpty) return null;
    return _SimpleFlowchart(
      horizontal: horizontal,
      nodes: nodes,
      edges: edges,
    );
  }
}

class _NativeFlowchartView extends StatelessWidget {
  const _NativeFlowchartView({required this.chart});

  final _SimpleFlowchart chart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final layout = _computeLayout(chart);
    return SizedBox(
      width: layout.size.width,
      height: layout.size.height,
      child: CustomPaint(
        painter: _NativeFlowchartPainter(
          chart: chart,
          layout: layout,
          colors: colors,
        ),
      ),
    );
  }

  _FlowLayout _computeLayout(_SimpleFlowchart chart) {
    final ids = chart.nodes.keys.toList();
    final layer = <String, int>{for (final id in ids) id: 0};

    // Longest-path topological layering (capped to handle cycles safely)
    for (var iter = 0; iter < ids.length; iter++) {
      var changed = false;
      for (final edge in chart.edges) {
        final next = (layer[edge.from] ?? 0) + 1;
        if (next > (layer[edge.to] ?? 0) && next <= ids.length) {
          layer[edge.to] = next;
          changed = true;
        }
      }
      if (!changed) break;
    }

    final byLayer = <int, List<String>>{};
    for (final id in ids) {
      byLayer.putIfAbsent(layer[id] ?? 0, () => []).add(id);
    }
    final layerKeys = byLayer.keys.toList()..sort();

    const nodeW = 216.0;
    const nodeH = 48.0;
    const gapX = 28.0;
    const gapY = 40.0;
    const pad = 16.0;

    final rects = <String, Rect>{};
    if (!chart.horizontal) {
      final maxCols = byLayer.values.fold<int>(
        1,
        (acc, list) => math.max(acc, list.length),
      );
      final totalW = maxCols * nodeW + (maxCols - 1) * gapX + pad * 2;
      final totalH =
          layerKeys.length * nodeH + (layerKeys.length - 1) * gapY + pad * 2;
      for (var r = 0; r < layerKeys.length; r++) {
        final row = byLayer[layerKeys[r]]!;
        final rowW = row.length * nodeW + (row.length - 1) * gapX;
        final startX = (totalW - rowW) / 2;
        final y = pad + r * (nodeH + gapY);
        for (var c = 0; c < row.length; c++) {
          rects[row[c]] = Rect.fromLTWH(
            startX + c * (nodeW + gapX),
            y,
            nodeW,
            nodeH,
          );
        }
      }
      return _FlowLayout(Size(totalW, totalH), rects);
    } else {
      final maxRows = byLayer.values.fold<int>(
        1,
        (acc, list) => math.max(acc, list.length),
      );
      final totalW =
          layerKeys.length * nodeW + (layerKeys.length - 1) * gapY + pad * 2;
      final totalH = maxRows * nodeH + (maxRows - 1) * gapX + pad * 2;
      for (var c = 0; c < layerKeys.length; c++) {
        final col = byLayer[layerKeys[c]]!;
        final colH = col.length * nodeH + (col.length - 1) * gapX;
        final startY = (totalH - colH) / 2;
        final x = pad + c * (nodeW + gapY);
        for (var r = 0; r < col.length; r++) {
          rects[col[r]] = Rect.fromLTWH(
            x,
            startY + r * (nodeH + gapX),
            nodeW,
            nodeH,
          );
        }
      }
      return _FlowLayout(Size(totalW, totalH), rects);
    }
  }
}

class _FlowLayout {
  const _FlowLayout(this.size, this.rects);
  final Size size;
  final Map<String, Rect> rects;
}

class _NativeFlowchartPainter extends CustomPainter {
  const _NativeFlowchartPainter({
    required this.chart,
    required this.layout,
    required this.colors,
  });

  final _SimpleFlowchart chart;
  final _FlowLayout layout;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.72)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final arrowFill = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    // 1. Draw smooth curved edges + arrowheads
    for (final edge in chart.edges) {
      final from = layout.rects[edge.from];
      final to = layout.rects[edge.to];
      if (from == null || to == null) continue;

      final Offset start;
      final Offset end;
      final Offset c1;
      final Offset c2;
      if (!chart.horizontal) {
        start = Offset(from.center.dx, from.bottom);
        end = Offset(to.center.dx, to.top - 2);
        final midY = (start.dy + end.dy) / 2;
        c1 = Offset(start.dx, midY);
        c2 = Offset(end.dx, midY);
      } else {
        start = Offset(from.right, from.center.dy);
        end = Offset(to.left - 2, to.center.dy);
        final midX = (start.dx + end.dx) / 2;
        c1 = Offset(midX, start.dy);
        c2 = Offset(midX, end.dy);
      }

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
      canvas.drawPath(path, edgePaint);

      // Arrowhead
      final angle = math.atan2(end.dy - c2.dy, end.dx - c2.dx);
      const arrowLen = 7.5;
      const arrowAngle = 0.45;
      final tip = end;
      final p1 = Offset(
        tip.dx - arrowLen * math.cos(angle - arrowAngle),
        tip.dy - arrowLen * math.sin(angle - arrowAngle),
      );
      final p2 = Offset(
        tip.dx - arrowLen * math.cos(angle + arrowAngle),
        tip.dy - arrowLen * math.sin(angle + arrowAngle),
      );
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close(),
        arrowFill,
      );
    }

    // 2. Draw crisp theme-aware nodes
    final fillPaint = Paint()
      ..color = colors.surface
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = colors.primary.withValues(alpha: 0.65)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final entry in layout.rects.entries) {
      final node = chart.nodes[entry.key]!;
      final rect = entry.value;
      final radius = node.isPill ? 24.0 : 10.0;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, strokePaint);

      final tp = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
            height: 1.25,
          ),
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width - 18);

      tp.paint(
        canvas,
        Offset(
          rect.left + (rect.width - tp.width) / 2,
          rect.top + (rect.height - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NativeFlowchartPainter oldDelegate) =>
      oldDelegate.chart != chart || oldDelegate.colors != colors;
}
