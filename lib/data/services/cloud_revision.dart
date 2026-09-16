class CloudDataChangedException implements Exception {
  final int localRevision;
  final int cloudRevision;

  const CloudDataChangedException({
    required this.localRevision,
    required this.cloudRevision,
  });

  @override
  String toString() => 'Os dados na nuvem foram alterados por outra pessoa. '
      'Atualize os dados antes de enviar novamente.';
}

int nextCloudRevision({
  required int? localRevision,
  required int cloudRevision,
}) {
  // Compatibilidade com o documento antigo, que ainda não tinha revisão.
  if (localRevision == null && cloudRevision == 0) return 1;

  if (localRevision != cloudRevision) {
    throw CloudDataChangedException(
      localRevision: localRevision ?? 0,
      cloudRevision: cloudRevision,
    );
  }
  return cloudRevision + 1;
}
