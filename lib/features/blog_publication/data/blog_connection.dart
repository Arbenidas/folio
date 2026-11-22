import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// This is the public client configuration also used by arbe.blog.
const _projectUrl = String.fromEnvironment(
  'FOLIO_BLOG_SUPABASE_URL',
  defaultValue: 'https://xadheyltgskjprmjbzvh.supabase.co',
);
const _publicKey = String.fromEnvironment(
  'FOLIO_BLOG_SUPABASE_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhhZGhleWx0Z3NranBybWpienZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE3NDUwMDQsImV4cCI6MjA4NzMyMTAwNH0.IJ-uk4dUpk8ojsfs3ZYnR91--vzkfAYi7Kj8UysOCD0',
);
const _siteUrl = String.fromEnvironment(
  'FOLIO_BLOG_SITE_URL',
  defaultValue: 'https://arbe.blog',
);
const _callback = 'com.folio.app://auth/callback';

bool get blogPublishingConfigured =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.macOS &&
    _projectUrl.isNotEmpty &&
    _publicKey.isNotEmpty;

Uri get blogSite => Uri.parse(_siteUrl);

final blogConnectionProvider = FutureProvider<BlogConnection?>((ref) async {
  if (!blogPublishingConfigured) return null;

  final project = Uri.parse(_projectUrl);
  if (!_isHttpsOrigin(project) ||
      !_isHttpsOrigin(blogSite) ||
      !_isPublicKey(_publicKey)) {
    throw const BlogFailure('La configuración de arbe.blog no es válida.');
  }

  final keychain = _BlogKeychain('folio-blog-${project.host}');
  final storage = _BlogSessionStorage(keychain);
  final sdk = await Supabase.initialize(
    url: project.origin,
    publishableKey: _publicKey,
    debug: false,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: storage,
      pkceAsyncStorage: keychain,
      detectSessionInUriPredicate: (uri) =>
          uri.scheme == 'com.folio.app' &&
          uri.host == 'auth' &&
          uri.path == '/callback' &&
          (uri.queryParameters.containsKey('code') ||
              uri.queryParameters.containsKey('error') ||
              uri.fragment.startsWith('error=')),
    ),
  );
  return BlogConnection(sdk.client, keychain.available);
});

bool _isHttpsOrigin(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    (uri.path.isEmpty || uri.path == '/') &&
    !uri.hasQuery &&
    !uri.hasFragment;

bool _isPublicKey(String key) {
  if (key.startsWith('sb_publishable_')) return true;
  try {
    final parts = key.split('.');
    if (parts.length != 3) return false;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map && payload['role'] == 'anon';
  } on FormatException {
    return false;
  }
}

class BlogConnection {
  BlogConnection(this._client, this.keychainAvailable);

  final SupabaseClient _client;
  final ValueListenable<bool> keychainAvailable;

  Session? get session => _client.auth.currentSession;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<void> signIn(OAuthProvider provider) async {
    final request = await _client.auth.getOAuthSignInUrl(
      provider: provider,
      redirectTo: _callback,
    );
    if (!await launchUrl(
      Uri.parse(request.url),
      mode: LaunchMode.externalApplication,
    )) {
      throw const BlogFailure('No se pudo abrir el navegador.');
    }
  }

  Future<void> signOut() => _client.auth.signOut(scope: SignOutScope.local);

  Future<Map<String, dynamic>> request(
    String operation,
    String authorId, {
    Object? body,
    Map<String, String> parameters = const {},
    String? contentType,
  }) async {
    var current = session;
    if (current == null || current.user.id != authorId) {
      throw const BlogFailure(
        'Vuelve a conectar la misma cuenta para continuar.',
      );
    }
    try {
      if (current.isExpired) {
        await _client.auth.refreshSession().timeout(
          const Duration(seconds: 20),
        );
        current = session;
      }
      if (current == null || current.user.id != authorId) {
        throw const BlogFailure(
          'Vuelve a conectar la misma cuenta para continuar.',
        );
      }
      final abort = Completer<void>();
      final timer = Timer(const Duration(seconds: 45), abort.complete);
      try {
        final response = await _client.functions.invoke(
          'folio-publish',
          queryParameters: {'action': operation, ...parameters},
          headers: {
            'Authorization': 'Bearer ${current.accessToken}',
            'Content-Type': ?contentType,
          },
          body: body,
          abortSignal: abort.future,
        );
        final data = response.data;
        if (data is! Map<String, dynamic>) {
          throw const BlogFailure('La respuesta de arbe.blog no es válida.');
        }
        return data;
      } finally {
        timer.cancel();
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      throw BlogFailure(switch (code) {
        'slug_taken' => 'Esa URL ya está en uso. Elige otra.',
        'missing_image' =>
          'Falta una captura en el servidor. Vuelve a intentarlo.',
        'invalid_content' =>
          'Revisa el título, la URL y el contenido del artículo.',
        'invalid_image' => 'arbe.blog no pudo validar una de las capturas.',
        'article_not_public' =>
          'El artículo de este envío ya existe. Revisa su estado en arbe.blog.',
        _ when error.status == 401 => 'Tu sesión caducó. Vuelve a conectarte.',
        _ when error.status == 403 => 'Tu cuenta no tiene permiso para publicar. Revisa tu perfil en arbe.blog.',
        _ => 'arbe.blog no pudo completar el envío. Vuelve a intentarlo.',
      });
    } on AuthException {
      throw const BlogFailure(
        'No se pudo renovar la sesión. Vuelve a conectarte.',
      );
    } on BlogFailure {
      rethrow;
    } catch (_) {
      throw const BlogFailure(
        'Se perdió la conexión con arbe.blog. Puedes reintentar.',
      );
    }
  }
}

class BlogFailure implements Exception {
  const BlogFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class _BlogSessionStorage extends LocalStorage {
  const _BlogSessionStorage(this._keychain);
  final _BlogKeychain _keychain;
  static const _session = 'session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() => _keychain.getItem(key: _session);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _keychain.setItem(key: _session, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _keychain.removeItem(key: _session);
}

class _BlogKeychain extends GotrueAsyncStorage {
  _BlogKeychain(this.namespace);
  final String namespace;
  final available = ValueNotifier(true);
  final _memory = <String, String>{};
  static const _channel = MethodChannel('folio/blog-keychain');

  Future<String?> _invoke(String method, String key, [String? value]) async {
    try {
      return await _channel.invokeMethod<String>(method, {
        'key': '$namespace-$key',
        'value': ?value,
      });
    } on PlatformException {
      available.value = false;
    } on MissingPluginException {
      available.value = false;
    }
    return null;
  }

  @override
  Future<String?> getItem({required String key}) async {
    if (_memory.containsKey(key)) return _memory[key];
    return available.value ? _invoke('read', key) : null;
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _memory[key] = value;
    if (available.value) await _invoke('write', key, value);
  }

  @override
  Future<void> removeItem({required String key}) async {
    _memory.remove(key);
    // Try deleting even if a previous read or write failed.
    await _invoke('remove', key);
  }
}
