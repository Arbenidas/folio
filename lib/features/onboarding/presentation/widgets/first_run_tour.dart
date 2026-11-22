import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/onboarding_preferences.dart';
import '../../../finance/domain/finance_models.dart';

/// Redesigned modern Folio welcome tour modal with crisp icons, progress dots,
/// and theme-adaptive contrast.
Future<void> showFirstRunTour(BuildContext context) async {
  const steps = <(String, String, String, IconData)>[
    (
      'BIENVENIDO A FOLIO',
      'Tus notas y finanzas en un solo lugar',
      'Cambia entre Notas Markdown y Finanzas desde la barra superior. Cada módulo guarda sus datos de forma aislada y segura.',
      Icons.auto_stories_rounded,
    ),
    (
      'CUADERNO LOCAL',
      'Carpetas y archivos Markdown reales',
      'Cada nota es un archivo .md real dentro de tu carpeta Folio. Organiza con carpetas, subcarpetas, búsqueda rápida (⌘K) y plantillas.',
      Icons.folder_copy_rounded,
    ),
    (
      'FINANZAS SIN ESTRÉS',
      'Control real de deudas, préstamos y presupuesto',
      'Ve cuánto tienes disponible hoy, planifica cómo bajar tu adelanto y tarjeta a \$0, y simula ahorro en intereses de tus préstamos.',
      Icons.account_balance_wallet_rounded,
    ),
    (
      'NUBE Y MULTIPLATAFORMA',
      'Sincroniza con tu cuenta cuando quieras',
      'Inicia sesión con Google o correo desde Ajustes para sincronizar tus saldos y notas entre Mac, móvil y Web (folio-2b7e3.web.app).',
      Icons.cloud_done_rounded,
    ),
  ];

  var index = 0;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final colors = Theme.of(context).colorScheme;
        final palette = FinancePalette.of(context);
        final step = steps[index];
        final isLast = index == steps.length - 1;
        final accent = switch (index) {
          0 => palette.accent,
          1 => palette.purple,
          2 => palette.positive,
          _ => palette.warning,
        };

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(step.$4, size: 24, color: accent),
                      ),
                      const Spacer(),
                      CupertinoButton(
                        padding: const EdgeInsets.all(6),
                        minimumSize: Size.zero,
                        onPressed: () async {
                          await OnboardingPreferences.setTourCompleted();
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    step.$1,
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.$2,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    step.$3,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < steps.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 6),
                              width: i == index ? 20 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: i == index
                                    ? accent
                                    : colors.outlineVariant,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      if (index > 0) ...[
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          onPressed: () => setState(() => index--),
                          child: Text(
                            'Atrás',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else ...[
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          onPressed: () async {
                            await OnboardingPreferences.setTourCompleted();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          child: Text(
                            'Omitir',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () async {
                          if (!isLast) {
                            setState(() => index++);
                          } else {
                            await OnboardingPreferences.setTourCompleted();
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          }
                        },
                        child: Text(
                          isLast ? 'Empezar' : 'Siguiente',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
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
  await OnboardingPreferences.setTourCompleted();
}
