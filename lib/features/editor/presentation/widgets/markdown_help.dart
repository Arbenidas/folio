import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/widgets/app_icon_button.dart';

class MarkdownHelp extends StatefulWidget {
  const MarkdownHelp({super.key});

  @override
  State<MarkdownHelp> createState() => _MarkdownHelpState();
}

class _MarkdownHelpState extends State<MarkdownHelp> {
  int _section = 0;

  static const examples = [
    ('Títulos', '# Título\n## Subtítulo\n### Sección'),
    ('Énfasis', '**negrita** · *cursiva* · ~~tachado~~'),
    (
      'Listas',
      '- Un elemento\n- Otro elemento\n\n1. Primer paso\n2. Segundo paso',
    ),
    ('Tareas', '- [ ] Pendiente\n- [x] Terminado'),
    ('Código en una línea', '`final nombre = "Flutter";`'),
    ('Bloque de código', '```dart\nvoid main() {\n  print("Hola");\n}\n```'),
    ('Enlaces', '[Documentación de Flutter](https://docs.flutter.dev)'),
    ('Citas y separadores', '> Una idea importante\n\n---'),
    (
      'Tablas',
      '| Concepto | Significado |\n| --- | --- |\n| Widget | Pieza de interfaz |',
    ),
  ];

  static const keys = [
    ('i  ·  Esc', 'Entrar en INSERT / volver a NORMAL'),
    ('h  j  k  l', 'Mover el cursor: izquierda, abajo, arriba, derecha'),
    ('w  ·  b', 'Siguiente palabra / palabra anterior'),
    ('0  ·  \$', 'Inicio / último carácter de la línea'),
    ('gg  ·  G', 'Inicio / última línea del documento'),
    ('a  ·  A  ·  I', 'Insertar después / al final / al inicio de línea'),
    ('o  ·  O', 'Crear una línea debajo / encima'),
    ('x  ·  dd', 'Borrar carácter / borrar línea'),
    ('yy  ·  p', 'Copiar línea / pegar línea debajo'),
    ('u  ·  Ctrl+R', 'Deshacer / rehacer'),
    ('/  ·  n  ·  N', 'Buscar / siguiente resultado / anterior'),
    (':w  ·  :new', 'Guardar / crear una nota'),
    ('⌘N  ·  ⇧⌘N  ·  ⌘S', 'Nueva nota / carpeta / guardar'),
    ('⌘K  ·  ⌘F', 'Búsqueda rápida / buscar en la nota'),
    ('⌘1  ·  ⌘2  ·  ⌘3', 'Enfocar notas / editor / vista previa'),
    ('F1  ·  ?', 'Abrir esta ayuda'),
    ('Ctrl+H  ·  Ctrl+L', 'Desde Vim NORMAL: notas / vista previa'),
    ('j  ·  k  ·  Enter', 'En notas: moverte y abrir la nota'),
    ('j  ·  k  ·  h', 'En vista previa: desplazar y volver al editor'),
  ];

  Widget _markdownContent(ColorScheme colors) => ListView.builder(
    key: const PageStorageKey('help-markdown'),
    padding: const EdgeInsets.fromLTRB(25, 8, 25, 24),
    itemCount: examples.length,
    itemBuilder: (context, index) {
      final example = examples[index];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                example.$1,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: SelectableText(
                  example.$2,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontFamily: 'Menlo',
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _keyboardContent(ColorScheme colors) => ListView.builder(
    key: const PageStorageKey('help-keyboard'),
    padding: const EdgeInsets.fromLTRB(25, 8, 25, 24),
    itemCount: keys.length + 1,
    itemBuilder: (context, index) {
      if (index == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 17),
          child: Text(
            'Los atajos con ⌘ funcionan desde los tres paneles. Vim captura sus comandos mientras está activado.',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        );
      }
      final entry = keys[index - 1];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 175,
                child: Text(
                  entry.$1,
                  style: TextStyle(
                    color: colors.primary,
                    fontFamily: 'Menlo',
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.$2,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _navigationItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required ColorScheme colors,
  }) {
    final selected = _section == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => setState(() => _section = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurface,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: selected
                            ? colors.onSecondaryContainer.withValues(alpha: 0.8)
                            : colors.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                  ],
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
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * 0.82).clamp(500.0, 720.0);
    return MacosSheet(
      insetPadding: const EdgeInsets.symmetric(horizontal: 44, vertical: 30),
      child: Container(
        width: 840,
        height: height,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 194,
              color: colors.surfaceContainerLow,
              padding: const EdgeInsets.fromLTRB(13, 18, 10, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 2, 8, 18),
                    child: Text(
                      'GUÍA RÁPIDA',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _navigationItem(
                    index: 0,
                    icon: CupertinoIcons.doc_text,
                    title: 'Markdown',
                    subtitle: 'Formato y ejemplos',
                    colors: colors,
                  ),
                  _navigationItem(
                    index: 1,
                    icon: CupertinoIcons.keyboard,
                    title: 'Teclado y Vim',
                    subtitle: 'Atajos y navegación',
                    colors: colors,
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      'F1 abre esta ayuda desde cualquier panel.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: colors.outlineVariant),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(23, 13, 12, 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _section == 0 ? 'Markdown' : 'Teclado y Vim',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _section == 0
                                    ? 'Consulta la sintaxis mientras escribes.'
                                    : 'Atajos disponibles en Folio.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppIconButton(
                          semanticLabel: 'Cerrar ayuda',
                          icon: CupertinoIcons.xmark,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: colors.outlineVariant),
                  Expanded(
                    child: _section == 0
                        ? _markdownContent(colors)
                        : _keyboardContent(colors),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
