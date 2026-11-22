import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../finance/domain/finance_models.dart';
import '../../finance/presentation/controllers/finance_controller.dart';
import '../data/folio_cloud_sync_service.dart';

Future<void> showCloudSyncDialog(
  BuildContext context, {
  FinanceController? financeController,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _CloudSyncModal(financeController: financeController),
      ),
    ),
  );
}

class _CloudSyncModal extends StatefulWidget {
  const _CloudSyncModal({this.financeController});

  final FinanceController? financeController;

  @override
  State<_CloudSyncModal> createState() => _CloudSyncModalState();
}

class _CloudSyncModalState extends State<_CloudSyncModal> {
  final _sync = FolioCloudSyncService.instance;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isRegister = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    unawaited(_sync.ensureInitialized());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final err = await _sync.signInWithGoogle();
    if (err == null && _sync.isSignedIn && widget.financeController != null) {
      await widget.financeController!.syncNowWithCloud();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = err;
        if (err == null && _sync.isSignedIn) {
          _info = 'Conectado con Google y sincronizado con folio-2b7e3.';
        }
      });
    }
  }

  Future<void> _submitAuth() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.length < 6) {
      setState(
        () => _error = 'Ingresa un correo válido y contraseña de 6+ caracteres.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final err = _isRegister
        ? await _sync.registerWithEmail(email, pass)
        : await _sync.signInWithEmail(email, pass);
    if (err == null && widget.financeController != null) {
      await widget.financeController!.syncNowWithCloud();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = err;
        if (err == null) {
          _info = 'Conectado a folio-2b7e3 y sincronizado.';
        }
      });
    }
  }

  Future<void> _forceUpload() async {
    final ctrl = widget.financeController;
    if (ctrl == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final ok = await ctrl.pushLocalToCloud();
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) {
          _info = 'Tus datos locales se subieron a la nube.';
        } else {
          _error = _sync.lastError ?? 'No se pudo subir a la nube.';
        }
      });
    }
  }

  Future<void> _forceDownload() async {
    final ctrl = widget.financeController;
    if (ctrl == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final ok = await ctrl.pullCloudToLocal();
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) {
          _info = 'Datos descargados desde la nube correctamente.';
        } else {
          _error =
              _sync.lastError ??
              'Aún no hay un respaldo guardado en la nube para esta cuenta.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);

    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) {
        final signedIn = _sync.isSignedIn;
        return Container(
          padding: const EdgeInsets.all(22),
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (signedIn ? palette.positive : palette.accent)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        signedIn
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_sync_rounded,
                        size: 20,
                        color: signedIn ? palette.positive : palette.accent,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sincronización en la nube',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          Text(
                            signedIn
                                ? 'Proyecto Firebase · folio-2b7e3'
                                : 'Sincroniza Mac, Android, iOS y Web',
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
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (signedIn) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.cardBg,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: palette.positive,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _sync.userEmail ?? 'Cuenta conectada',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _sync.lastSyncedAt != null
                              ? 'Última sincronización: ${_fmtTime(_sync.lastSyncedAt!)}'
                              : 'Sincronización automática activa en tiempo real.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (widget.financeController != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: Size.zero,
                            color: palette.cardBg,
                            borderRadius: BorderRadius.circular(10),
                            onPressed: _busy ? null : _forceUpload,
                            child: Text(
                              'Subir datos locales',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: Size.zero,
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                            onPressed: _busy ? null : _forceDownload,
                            child: Text(
                              'Descargar nube',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    minimumSize: Size.zero,
                    onPressed: _busy
                        ? null
                        : () async {
                            await _sync.signOut();
                            if (mounted) {
                              setState(() {
                                _info = 'Sesión cerrada.';
                                _error = null;
                              });
                            }
                          },
                    child: Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.negative,
                      ),
                    ),
                  ),
                ] else ...[
                  GoogleSignInButton(
                    busy: _busy,
                    onPressed: _signInGoogle,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          height: 1,
                          color: palette.border.withValues(alpha: 0.7),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'o con correo',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          height: 1,
                          color: palette.border.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CupertinoSlidingSegmentedControl<bool>(
                    groupValue: _isRegister,
                    onValueChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _isRegister = v;
                          _error = null;
                          _info = null;
                        });
                      }
                    },
                    children: const {
                      false: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Iniciar sesión',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      true: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Crear cuenta',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    },
                  ),
                  const SizedBox(height: 14),
                  CupertinoTextField(
                    controller: _emailCtrl,
                    placeholder: 'Tu correo electrónico',
                    keyboardType: TextInputType.emailAddress,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                  ),
                  const SizedBox(height: 10),
                  CupertinoTextField(
                    controller: _passCtrl,
                    placeholder: 'Contraseña (mín. 6 caracteres)',
                    obscureText: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                    onSubmitted: (_) => unawaited(_submitAuth()),
                  ),
                  const SizedBox(height: 14),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    borderRadius: BorderRadius.circular(10),
                    onPressed: _busy ? null : _submitAuth,
                    child: _busy
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : Text(
                            _isRegister
                                ? 'Crear cuenta y sincronizar'
                                : 'Iniciar sesión y sincronizar',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tus datos son privados: las reglas de Firestore bloquean el acceso a cualquier otro usuario.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: palette.negative.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(9),
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
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: palette.positive.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      _info!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.positive,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmtTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

/// Clean, theme-aware Google Sign-In button shared by Settings, Cloud Sync,
/// and the Welcome Onboarding flow.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'Continuar con Google',
  });

  final VoidCallback onPressed;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: busy ? null : onPressed,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: palette.isDark ? colors.surfaceContainerHigh : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: palette.isDark ? 0.16 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const CupertinoActivityIndicator(radius: 8.5)
            else ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CustomPaint(painter: _GoogleGLogoPainter()),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.isDark ? colors.onSurface : const Color(0xFF1F1F1F),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  const _GoogleGLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.21;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - stroke) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Red top arc
    canvas.drawArc(rect, -2.55, 1.85, false, paint..color = const Color(0xFFEA4335));
    // Yellow left arc
    canvas.drawArc(rect, 2.45, 1.30, false, paint..color = const Color(0xFFFBBC05));
    // Green bottom arc
    canvas.drawArc(rect, 0.72, 1.78, false, paint..color = const Color(0xFF34A853));
    // Blue right arc
    canvas.drawArc(rect, -0.05, 0.85, false, paint..color = const Color(0xFF4285F4));
    // Blue horizontal bar
    canvas.drawLine(
      Offset(size.width * 0.51, size.height * 0.51),
      Offset(size.width * 0.94, size.height * 0.51),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
