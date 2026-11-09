import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/onboarding_preferences.dart';

Future<void> showFirstRunTour(BuildContext context) async {
  const steps = <(String, String, IconData)>[
    (
      'Tu espacio',
      'La barra lateral muestra tus carpetas y notas. Se corresponden con carpetas y archivos .md dentro de Folio.',
      CupertinoIcons.folder,
    ),
    (
      'Organiza tus ideas',
      'Usa el botón de carpeta para crear carpetas y subcarpetas. También puedes arrastrar notas entre carpetas.',
      CupertinoIcons.folder_badge_plus,
    ),
    (
      'Escribe en Markdown',
      'Crea una nota y escribe en el editor. Folio guarda cada nota como un archivo Markdown que puedes abrir desde Finder.',
      CupertinoIcons.doc_text,
    ),
    (
      'Vim, si lo quieres',
      'El modo Vim está apagado de forma predeterminada. Puedes activarlo desde la barra superior. La ayuda explica los comandos que Folio admite.',
      CupertinoIcons.keyboard,
    ),
  ];
  var index = 0;
  await showCupertinoDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final step = steps[index];
        return CupertinoAlertDialog(
          title: Column(
            children: [
              Icon(
                step.$3,
                size: 29,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(step.$1),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(step.$2),
                const SizedBox(height: 12),
                Text(
                  '${index + 1} de ${steps.length}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                await OnboardingPreferences.setTourCompleted();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Omitir recorrido'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                if (index + 1 < steps.length) {
                  setState(() => index++);
                } else {
                  await OnboardingPreferences.setTourCompleted();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                }
              },
              child: Text(index + 1 == steps.length ? 'Terminar' : 'Siguiente'),
            ),
          ],
        );
      },
    ),
  );
  await OnboardingPreferences.setTourCompleted();
}
