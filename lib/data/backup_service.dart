import 'dart:convert';

import 'database.dart';

/// Exporta (e, no futuro, importa) um backup simples em JSON.
///
/// Como o app é 100% local, isso é o que evita perder tudo se o
/// aparelho for perdido, trocado ou reformatado.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Monta um JSON com produtos e movimentações.
  ///
  /// TODO: gravar o resultado em arquivo (path_provider) e oferecer
  /// compartilhar/salvar — pacote `share_plus` é uma opção simples.
  Future<String> exportarJson() async {
    final produtos = await _db.listarProdutos();
    final movimentacoes = await _db.listarMovimentacoes();

    final dados = {
      'versao': 1,
      'produtos': produtos.map((p) => p.toJson()).toList(),
      'movimentacoes': movimentacoes.map((m) => m.toJson()).toList(),
    };

    return jsonEncode(dados);
  }

  // TODO: Future<void> importarJson(String conteudo) — ler o JSON e
  // recriar os registros no banco (cuidado com IDs duplicados).
}
