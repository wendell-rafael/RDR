import 'package:flutter_test/flutter_test.dart';
import 'package:rdr_app/data/services/cloud_revision.dart';

void main() {
  group('nextCloudRevision', () {
    test('migra o documento legado para a primeira revisão', () {
      expect(nextCloudRevision(localRevision: null, cloudRevision: 0), 1);
    });

    test('incrementa quando a cópia local está atualizada', () {
      expect(nextCloudRevision(localRevision: 4, cloudRevision: 4), 5);
    });

    test('recusa aparelho sem base depois da migração', () {
      expect(
        () => nextCloudRevision(localRevision: null, cloudRevision: 2),
        throwsA(isA<CloudDataChangedException>()),
      );
    });

    test('recusa revisão local desatualizada', () {
      expect(
        () => nextCloudRevision(localRevision: 3, cloudRevision: 4),
        throwsA(isA<CloudDataChangedException>()),
      );
    });
  });
}
