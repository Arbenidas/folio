import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/blog_connection.dart';

String blogAuthorLabel(User user) {
  final metadata = user.userMetadata;
  final name = metadata?['full_name'] ?? metadata?['name'];
  final email = user.email;
  if (name is String && name.trim().isNotEmpty) {
    return email == null ? name : '$name · $email';
  }
  return email ?? 'Cuenta de arbe.blog';
}

class BlogAccountPanel extends ConsumerStatefulWidget {
  const BlogAccountPanel({super.key});

  @override
  ConsumerState<BlogAccountPanel> createState() => _BlogAccountPanelState();
}

class _BlogAccountPanelState extends ConsumerState<BlogAccountPanel> {
  bool _busy = false;
  bool _failed = false;
  String? _message;

  Future<void> _run(Future<void> Function() action, String? success) async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } on BlogFailure catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'No se pudo completar el acceso. Vuelve a intentarlo.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(blogConnectionProvider)
        .when(
          loading: () => const CupertinoActivityIndicator(),
          error: (_, _) =>
              const Text('No se pudo iniciar la integración con arbe.blog.'),
          data: (connection) {
            if (connection == null) {
              return const Text('Integración no disponible.');
            }
            return StreamBuilder<AuthState>(
              stream: connection.authChanges,
              builder: (context, snapshot) {
                final user = connection.session?.user;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user == null
                          ? 'Conecta tu cuenta de autor de arbe.blog.'
                          : blogAuthorLabel(user),
                    ),
                    if (user == null)
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final (label, provider) in [
                            ('Google', OAuthProvider.google),
                            ('GitHub', OAuthProvider.github),
                          ])
                            CupertinoButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => connection.signIn(provider),
                                      'Completa el acceso en el navegador para volver a Folio.',
                                    ),
                              child: Text('Continuar con $label'),
                            ),
                        ],
                      )
                    else ...[
                      CupertinoButton(
                        onPressed: _busy
                            ? null
                            : () => _run(connection.signOut, null),
                        child: const Text('Desconectar de Folio'),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: connection.keychainAvailable,
                        builder: (context, available, _) => available
                            ? const SizedBox.shrink()
                            : const Text(
                                'El Llavero no está disponible. La sesión dura hasta cerrar Folio.',
                              ),
                      ),
                    ],
                    if (snapshot.hasError ||
                        (_message != null && (user == null || _failed)))
                      Text(
                        snapshot.hasError
                            ? 'El acceso no se completó. Inténtalo de nuevo.'
                            : _message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (_busy) const CupertinoActivityIndicator(),
                  ],
                );
              },
            );
          },
        );
  }
}

class BlogIntegrationSection extends StatelessWidget {
  const BlogIntegrationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('INTEGRACIONES'),
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('arbe.blog', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              BlogAccountPanel(),
            ],
          ),
        ),
      ],
    );
  }
}
