import 'database.dart';

/// Substituição integral do conteúdo, para restaurar backup.
extension BackupDao on AppDatabase {
  // --- Backup -----------------------------------------------------------

  /// Substitui todo o conteúdo do banco pelo do backup, numa transação.
  ///
  /// Apaga antes de inserir, então importar duas vezes não duplica. Os ids
  /// originais são preservados, o que mantém o vínculo entre movimentação e
  /// produto. Tudo ou nada: se um insert falhar, o banco fica como estava.
  Future<void> restaurarBackup({
    required List<Produto> listaProdutos,
    required List<Movimentacao> listaMovimentacoes,
  }) async {
    await transaction(() async {
      await delete(movimentacoes).go();
      await delete(produtos).go();

      await batch((b) {
        b.insertAll(
          produtos,
          [for (final p in listaProdutos) p.toCompanion(false)],
        );
        b.insertAll(
          movimentacoes,
          [for (final m in listaMovimentacoes) m.toCompanion(false)],
        );
      });
    });
  }
}
