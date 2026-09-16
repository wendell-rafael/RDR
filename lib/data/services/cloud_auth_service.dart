import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Autenticação dos responsáveis que podem publicar os dados do racha.
///
/// As contas Google são autorizadas por um documento vazio em
/// `rdr_writers/{email}`. A decisão final sempre pertence às
/// regras do Firestore; esta checagem serve para dar um erro claro no app.
class CloudAuthService {
  static const _timeout = Duration(seconds: 15);
  static final Future<void> _googleInitialization = kIsWeb
      ? Future<void>.value()
      : GoogleSignIn.instance.initialize();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static Stream<User?> get userChanges => _auth.userChanges();

  static User? get currentUser => _auth.currentUser;

  /// Versões anteriores criavam contas anônimas automaticamente. Elas não têm
  /// permissão no modelo novo e são removidas localmente durante a migração.
  static Future<void> clearLegacyAnonymousSession() async {
    if (_auth.currentUser?.isAnonymous ?? false) {
      await _auth.signOut();
    }
  }

  static Future<User> signInWithGoogle() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Google Sign-In ainda não está configurado para web. '
        'Registre um app web no console Firebase (Configurações > Seus apps > Adicionar app > Web) '
        'e adicione o Client ID em web/index.html.',
      );
    }
    await _googleInitialization;
    late final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate().timeout(_timeout);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SignInCancelledException();
      }
      rethrow;
    }

    final googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError('O Google não retornou um token de identificação.');
    }

    final credential = await _auth
        .signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        )
        .timeout(_timeout);
    final user = credential.user;
    if (user == null) {
      throw StateError('O Firebase não retornou o usuário autenticado.');
    }

    final authorized = await isAuthorizedWriter(user.email);
    if (!authorized) {
      final email = user.email ?? googleUser.email;
      await signOut();
      throw WriterNotAuthorizedException(email);
    }
    return user;
  }

  static Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await _googleInitialization;
      await GoogleSignIn.instance.signOut();
    }
  }

  static Future<bool> isAuthorizedWriter([String? email]) async {
    final accountEmail = (email ?? _auth.currentUser?.email)?.toLowerCase();
    if (accountEmail == null) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('rdr_writers')
        .doc(accountEmail)
        .get(const GetOptions(source: Source.server))
        .timeout(_timeout);
    return snapshot.exists;
  }

  static User requireSignedInWriter() {
    final user = _auth.currentUser;
    final usesGoogle = user?.providerData
            .any((provider) => provider.providerId == 'google.com') ??
        false;
    if (user == null || !usesGoogle || !user.emailVerified) {
      throw StateError(
        'Entre com uma conta Google autorizada antes de enviar dados para a nuvem.',
      );
    }
    return user;
  }
}

class WriterNotAuthorizedException implements Exception {
  final String email;

  const WriterNotAuthorizedException(this.email);

  @override
  String toString() =>
      'Esta conta Google não está autorizada a enviar dados: $email';
}

class SignInCancelledException implements Exception {
  const SignInCancelledException();
}
