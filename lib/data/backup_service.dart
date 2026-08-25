import 'dart:convert';

import 'database.dart';

/// Backup recusado: JSON malformado, estrutura inesperada ou versão que este
/// app não sabe ler.
class BackupInvalido implements Exception {
  BackupInvalido(this.motivo);
  final String motivo;
  @override
  String toString() => 'BackupInvalido: $motivo';
}

/// Exporta e importa um backup simples em JSON.
///
/// Como o app é 100% local, isso é o que evita perder tudo se o
/// aparelho for perdido, trocado ou reformatado.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Versão do formato que este app sabe ler e escrever.
  static const versaoSuportada = 1;

  /// Monta um JSON com produtos e movimentações.
  Future<String> exportarJson() async {
    final produtos = await _db.listarProdutos();
    final movimentacoes = await _db.listarMovimentacoes();

    final dados = {
      'versao': versaoSuportada,
      'produtos': produtos.map((p) => p.toJson()).toList(),
      'movimentacoes': movimentacoes.map((m) => m.toJson()).toList(),
    };

    return jsonEncode(dados);
  }

  /// Lê o JSON de um backup e substitui o conteúdo do banco por ele.
  ///
  /// Valida ANTES de tocar no banco: se o conteúdo for recusado, nada é
  /// apagado. Recusa com [BackupInvalido] quando o texto não é JSON válido,
  /// quando não é um objeto com `produtos` e `movimentacoes`, ou quando
  /// `versao` é diferente de [versaoSuportada].
  Future<void> importarJson(String json) async {
    try {
      final dados = jsonDecode(json) as Map<String, dynamic>;

      if (dados['versao'] != versaoSuportada) {
        throw BackupInvalido('Versão desconhecida');
      }

      if (!dados.containsKey('produtos') || !dados.containsKey('movimentacoes')) {
        throw BackupInvalido('Estrutura inesperada');
      }

      final produtosJson = dados['produtos'] as List<dynamic>;
      final movimentacoesJson = dados['movimentacoes'] as List<dynamic>;

      final produtos = produtosJson.map((p) => Produto.fromJson(p)).toList();
      final movimentacoes = movimentacoesJson.map((m) => Movimentacao.fromJson(m)).toList();

      await _db.restaurarBackup(
        listaProdutos: produtos,
        listaMovimentacoes: movimentacoes,
      );
    } catch (e) {
      throw BackupInvalido('JSON malformado');
    }
  }
}
