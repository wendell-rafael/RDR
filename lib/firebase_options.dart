import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions não suportado para esta plataforma.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA-KGihIggSOgWaSWdYKYfDQaEBxCVNI0s',
    appId: '1:798969577133:android:517bcda3e238a13abcd024',
    messagingSenderId: '798969577133',
    projectId: 'racha-dos-ruins',
    storageBucket: 'racha-dos-ruins.firebasestorage.app',
  );
}
