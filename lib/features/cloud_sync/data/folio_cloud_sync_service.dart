import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../firebase_options.dart';
import '../../finance/domain/finance_models.dart';

class RemoteFinancePayload {
  const RemoteFinancePayload({
    required this.snapshot,
    required this.updatedAtMs,
  });

  final FinanceSnapshot snapshot;
  final int updatedAtMs;
}

class RemoteScratchpadPayload {
  const RemoteScratchpadPayload({
    required this.content,
    required this.updatedAtMs,
  });

  final String content;
  final int updatedAtMs;
}

/// Manages Firebase Auth + real-time Cloud Firestore synchronization for Folio
/// across macOS, Android, iOS, and Web (`folio-2b7e3`).
class FolioCloudSyncService extends ChangeNotifier {
  FolioCloudSyncService._();

  static final FolioCloudSyncService instance = FolioCloudSyncService._();

  bool _initialized = false;
  bool _initializing = false;
  bool _googleInitialized = false;
  String? _initError;
  String? _lastError;
  DateTime? _lastSyncedAt;
  bool _syncing = false;
  StreamSubscription<User?>? _authSub;

  bool get isInitialized => _initialized;
  bool get isSyncing => _syncing;
  String? get initError => _initError;
  String? get lastError => _lastError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  FirebaseAuth? get _auth => _initialized ? FirebaseAuth.instance : null;
  FirebaseFirestore? get _db =>
      _initialized ? FirebaseFirestore.instance : null;

  User? get currentUser => _auth?.currentUser;
  bool get isSignedIn => currentUser != null;
  String? get userId => currentUser?.uid;
  String? get userEmail => currentUser?.email;

  Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    if (_initializing) return false;
    _initializing = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _initialized = true;
      _initError = null;
      _authSub ??= FirebaseAuth.instance.authStateChanges().listen((_) {
        notifyListeners();
      });
      notifyListeners();
      return true;
    } catch (e) {
      _initError = e.toString();
      notifyListeners();
      return false;
    } finally {
      _initializing = false;
    }
  }

  static const String _googleServerClientId =
      '483907243932-v6r3loqsjiqi12jpfbr0o43r4m2rgcui.apps.googleusercontent.com';

  /// Signs in with Google across Web (popup) and Mobile/Desktop (google_sign_in 7.x).
  /// Returns `null` on success or user cancellation, or a user-friendly error message.
  Future<String?> signInWithGoogle() async {
    final ok = await ensureInitialized();
    if (!ok) return 'No se pudo inicializar Firebase.';
    try {
      _lastError = null;
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await _auth!.signInWithPopup(provider);
      } else {
        if (!_googleInitialized) {
          final isApple =
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.iOS;
          await GoogleSignIn.instance.initialize(
            clientId: isApple
                ? DefaultFirebaseOptions.currentPlatform.iosClientId
                : null,
            serverClientId: _googleServerClientId,
          );
          _googleInitialized = true;
        }
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          throw Exception('No se recibió el token de Google.');
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        await _auth!.signInWithCredential(credential);
      }
      notifyListeners();
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      final msg = e.description ?? 'No se pudo iniciar sesión con Google.';
      _lastError = msg;
      notifyListeners();
      return msg;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      final msg = _friendlyAuthError(e);
      _lastError = msg;
      notifyListeners();
      return msg;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return _lastError;
    }
  }

  Future<String?> signInWithEmail(String email, String password) async {
    final ok = await ensureInitialized();
    if (!ok) return 'No se pudo inicializar Firebase.';
    try {
      _lastError = null;
      await _auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      final msg = _friendlyAuthError(e);
      _lastError = msg;
      notifyListeners();
      return msg;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return _lastError;
    }
  }

  Future<String?> registerWithEmail(String email, String password) async {
    final ok = await ensureInitialized();
    if (!ok) return 'No se pudo inicializar Firebase.';
    try {
      _lastError = null;
      await _auth!.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      final msg = _friendlyAuthError(e);
      _lastError = msg;
      notifyListeners();
      return msg;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return _lastError;
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    final ok = await ensureInitialized();
    if (!ok) return 'No se pudo inicializar Firebase.';
    try {
      await _auth!.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyAuthError(e);
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    if (!kIsWeb && _googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth!.signOut();
    _lastSyncedAt = null;
    _lastError = null;
    notifyListeners();
  }

  DocumentReference<Map<String, dynamic>>? _financeDoc() {
    final uid = userId;
    final db = _db;
    if (uid == null || db == null) return null;
    return db.collection('users').doc(uid).collection('finance').doc('snapshot');
  }

  DocumentReference<Map<String, dynamic>>? _scratchpadDoc() {
    final uid = userId;
    final db = _db;
    if (uid == null || db == null) return null;
    return db
        .collection('users')
        .doc(uid)
        .collection('notes')
        .doc('scratchpad');
  }

  Future<RemoteFinancePayload?> fetchFinanceSnapshot() async {
    final doc = _financeDoc();
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (!snap.exists) return null;
      return _decodeFinanceDoc(snap.data());
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Stream<RemoteFinancePayload?> watchFinanceSnapshot() {
    final doc = _financeDoc();
    if (doc == null) return const Stream<RemoteFinancePayload?>.empty();
    return doc.snapshots().map((snap) {
      if (!snap.exists) return null;
      return _decodeFinanceDoc(snap.data());
    });
  }

  Future<bool> uploadFinanceSnapshot(
    FinanceSnapshot snapshot, {
    int? updatedAtMs,
  }) async {
    final doc = _financeDoc();
    final uid = userId;
    if (doc == null || uid == null) return false;
    final payloadJson = jsonEncode(snapshot.toJson());
    if (payloadJson.length > 524288) {
      _lastError = 'El respaldo supera el límite de 512 KB.';
      notifyListeners();
      return false;
    }
    _syncing = true;
    notifyListeners();
    try {
      final tsMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
      await doc.set({
        'ownerId': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': tsMs,
        'payloadJson': payloadJson,
      });
      _lastSyncedAt = DateTime.now();
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<RemoteScratchpadPayload?> fetchScratchpad() async {
    final doc = _scratchpadDoc();
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return RemoteScratchpadPayload(
        content: data['content'] as String? ?? '',
        updatedAtMs: (data['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Stream<RemoteScratchpadPayload?> watchScratchpad() {
    final doc = _scratchpadDoc();
    if (doc == null) return const Stream<RemoteScratchpadPayload?>.empty();
    return doc.snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return RemoteScratchpadPayload(
        content: data['content'] as String? ?? '',
        updatedAtMs: (data['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<bool> uploadScratchpad(String content, {int? updatedAtMs}) async {
    final doc = _scratchpadDoc();
    final uid = userId;
    if (doc == null || uid == null) return false;
    if (content.length > 200000) return false;
    try {
      await doc.set({
        'ownerId': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        'content': content,
      });
      _lastSyncedAt = DateTime.now();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  RemoteFinancePayload? _decodeFinanceDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    final payloadJson = data['payloadJson'] as String?;
    if (payloadJson == null || payloadJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map<String, dynamic>) {
        return RemoteFinancePayload(
          snapshot: FinanceSnapshot.fromJson(decoded),
          updatedAtMs: (data['updatedAtMs'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return null;
  }

  static String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no tiene un formato válido.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'email-already-in-use':
        return 'Ese correo ya tiene una cuenta registrada. Inicia sesión.';
      case 'weak-password':
        return 'Usa una contraseña de al menos 6 caracteres.';
      case 'network-request-failed':
        return 'Sin conexión a internet para conectar con Firebase.';
      case 'operation-not-allowed':
        return 'Activa este proveedor en Firebase Console.';
      case 'unauthorized-domain':
        return 'Dominio no autorizado en Firebase Auth. Agrégalo en Authorized Domains.';
      default:
        return e.message ?? 'Error de autenticación (${e.code}).';
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
