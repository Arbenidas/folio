import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/folio_brand_icon.dart';
import '../../../cloud_sync/data/folio_cloud_sync_service.dart';
import '../../../cloud_sync/presentation/cloud_sync_dialog.dart';
import '../../../finance/domain/finance_models.dart';
import '../../../finance/presentation/controllers/finance_controller.dart';

/// Modern 3-step welcome onboarding shared across Web and Mobile (and reusable
/// as a guided tour): Welcome -> Live Theme Picker -> Optional Google/Email Sync.
class WelcomeOnboardingScreen extends StatefulWidget {
  const WelcomeOnboardingScreen({
    super.key,
    required this.selectedTheme,
    required this.onSelectTheme,
    required this.onComplete,
    this.financeController,
  });

  final AppTheme selectedTheme;
  final ValueChanged<AppTheme> onSelectTheme;
  final VoidCallback onComplete;
  final FinanceController? financeController;

  @override
  State<WelcomeOnboardingScreen> createState() =>
      _WelcomeOnboardingScreenState();
}

class _WelcomeOnboardingScreenState extends State<WelcomeOnboardingScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  static const _featuredThemes = <(AppTheme, String, String, Color, Color)>[
    (
      AppTheme.noche,
      'Noche',
      'Oscuro profundo y suave a la vista',
      Color(0xFF141820),
      Color(0xFF7CB8D9),
    ),
    (
      AppTheme.crema,
      'Crema',
      'Papel cálido estilo libreta',
      Color(0xFFF6F1E7),
      Color(0xFFB55D3C),
    ),
    (
      AppTheme.oscuro,
      'Oscuro',
      'Neutro y nítido de alto contraste',
      Color(0xFF1A1B1E),
      Color(0xFF4ADE98),
    ),
    (
      AppTheme.claro,
      'Claro',
      'Limpio, luminoso y minimalista',
      Color(0xFFFAFAFA),
      Color(0xFF2B6CB0),
    ),
  ];

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await FolioCloudSyncService.instance.signInWithGoogle();
    if (err == null &&
        FolioCloudSyncService.instance.isSignedIn &&
        widget.financeController != null) {
      await widget.financeController!.syncNowWithCloud();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null && FolioCloudSyncService.instance.isSignedIn) {
      widget.onComplete();
    }
  }

  Future<void> _openEmailAuth() async {
    await showCloudSyncDialog(
      context,
      financeController: widget.financeController,
    );
    if (mounted && FolioCloudSyncService.instance.isSignedIn) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final signedIn = FolioCloudSyncService.instance.isSignedIn;
    final compact = MediaQuery.sizeOf(context).width < 500;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 20,
              vertical: compact ? 14 : 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: EdgeInsets.all(compact ? 20 : 28),
                decoration: BoxDecoration(
                  color: palette.cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: palette.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: palette.isDark ? 0.32 : 0.08,
                      ),
                      blurRadius: 36,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with Folio brand + step progress
                    Row(
                      children: [
                        const FolioBrandIcon(size: 42, borderRadius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FOLIO',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w800,
                                  color: palette.accent,
                                ),
                              ),
                              Text(
                                'Paso ${_step + 1} de 3',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_step < 2)
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            onPressed: widget.onComplete,
                            child: Text(
                              'Omitir',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Animated step content
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: switch (_step) {
                          0 => _buildWelcomeStep(colors, palette),
                          1 => _buildThemeStep(colors, palette),
                          _ => _buildAccountStep(colors, palette, signedIn),
                        },
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: palette.negative.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.negative,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Footer: progress dots + navigation
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < 3; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(right: 6),
                                width: i == _step ? 22 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: i == _step
                                      ? palette.accent
                                      : colors.outlineVariant,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_step > 0)
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _step--;
                                          _error = null;
                                        }),
                                child: Text(
                                  'Atrás',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            if (_step < 2)
                              CupertinoButton.filled(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                minimumSize: Size.zero,
                                borderRadius: BorderRadius.circular(11),
                                onPressed: () => setState(() {
                                  _step++;
                                  _error = null;
                                }),
                                child: const Text(
                                  'Siguiente',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 9,
                                ),
                                minimumSize: Size.zero,
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(11),
                                onPressed: _busy ? null : widget.onComplete,
                                child: Text(
                                  signedIn
                                      ? 'Entrar a Folio'
                                      : 'Seguir sin cuenta',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeStep(ColorScheme colors, FinancePalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tu dinero y tus ideas,\nen un solo lugar.',
          style: TextStyle(
            fontSize: 26,
            height: 1.18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Folio combina finanzas personales claras con notas rápidas en Markdown, sin complicaciones ni pantallas recargadas.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _FeatureHighlightRow(
          icon: Icons.account_balance_wallet_rounded,
          tint: palette.positive,
          title: 'Disponible real hoy',
          subtitle:
              'Separa tu dinero líquido de tus tarjetas, adelanto salarial y pagos fijos.',
        ),
        const SizedBox(height: 10),
        _FeatureHighlightRow(
          icon: Icons.route_rounded,
          tint: palette.warning,
          title: 'Plan de deudas y préstamos',
          subtitle:
              'Elige tu ritmo para llegar a \$0 y simula cuánto ahorras en intereses.',
        ),
        const SizedBox(height: 10),
        _FeatureHighlightRow(
          icon: Icons.auto_stories_rounded,
          tint: palette.purple,
          title: 'Notas Markdown + Nube',
          subtitle:
              'Accede desde Mac, móvil o Web con respaldo automático y privado.',
        ),
      ],
    );
  }

  Widget _buildThemeStep(ColorScheme colors, FinancePalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Elige tu estilo visual',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Toca una paleta para probarla al instante. Siempre puedes cambiarla en Ajustes.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoCols = constraints.maxWidth >= 380;
            final cardW = twoCols
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in _featuredThemes)
                  SizedBox(
                    width: cardW,
                    child: _ThemeChoiceCard(
                      name: item.$2,
                      description: item.$3,
                      bgPreview: item.$4,
                      accentPreview: item.$5,
                      selected: widget.selectedTheme == item.$1,
                      onTap: () => widget.onSelectTheme(item.$1),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccountStep(
    ColorScheme colors,
    FinancePalette palette,
    bool signedIn,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          signedIn ? '¡Tu cuenta ya está lista!' : 'Sincroniza tus dispositivos',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          signedIn
              ? 'Conectado como ${FolioCloudSyncService.instance.userEmail ?? 'tu cuenta'}. Tus finanzas y notas ya se sincronizan en tiempo real.'
              : 'Inicia sesión con tu cuenta de Google para mantener tus mismos saldos y notas en Mac, móvil y Web. También puedes hacerlo después desde Ajustes.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        if (signedIn)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.positive.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: palette.positive.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_done_rounded, color: palette.positive, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    FolioCloudSyncService.instance.userEmail ??
                        'Sincronización activa',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          GoogleSignInButton(
            busy: _busy,
            onPressed: _signInWithGoogle,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 11),
              color: palette.innerBg,
              borderRadius: BorderRadius.circular(11),
              onPressed: _busy ? null : _openEmailAuth,
              child: Text(
                'Usar correo y contraseña',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tus datos son privados: solo tu usuario puede acceder a ellos.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FeatureHighlightRow extends StatelessWidget {
  const _FeatureHighlightRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.innerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChoiceCard extends StatelessWidget {
  const _ThemeChoiceCard({
    required this.name,
    required this.description,
    required this.bgPreview,
    required this.accentPreview,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String description;
  final Color bgPreview;
  final Color accentPreview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: palette.innerBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 20,
                  decoration: BoxDecoration(
                    color: bgPreview,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 10,
                      height: 20,
                      decoration: BoxDecoration(
                        color: accentPreview,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: palette.accent,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
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
    );
  }
}
