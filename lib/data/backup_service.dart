import 'dart:convert';
import 'dart:io';

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
        throw BackupInvalido('Versão desconhecida: ${dados['versao']}');
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
      if (e is BackupInvalido) {
        rethrow;
      }
      throw BackupInvalido('JSON malformado');
    }
  }

  /// Nome do arquivo de backup para o instante [quando].
  ///
  /// Função pura. Formato `estoque_qr_AAAA-MM-DD_HHMM.json`, com mês, dia,
  /// hora e minuto sempre em dois dígitos. Ex.: 25/08/2026 às 14:07 vira
  /// `estoque_qr_2026-08-25_1407.json`.
  ///
  /// A precisão para no minuto de propósito: dois backups no mesmo minuto
  /// compartilham o nome e um sobrescreve o outro, o que é melhor do que
  /// encher a pasta de arquivos quase idênticos.
  String nomeDoArquivo(DateTime quando) {
    return 'estoque_qr_${quando.year}-${quando.month.toString().padLeft(2, '0')}-${quando.day.toString().padLeft(2, '0')}_${quando.hour.toString().padLeft(2, '0')}${quando.minute.toString().padLeft(2, '0')}.json';
  }

  /// Grava o backup num arquivo dentro de [destino] e devolve o arquivo.
  ///
  /// O conteúdo é exatamente o de [exportarJson]; o nome vem de
  /// [nomeDoArquivo], usando a hora corrente.
  Future<File> exportarParaArquivo(Directory destino) async {
    final conteudo = await exportarJson();
    final arquivo = File('${destino.path}/${nomeDoArquivo(DateTime.now())}');
    await arquivo.writeAsString(conteudo);
    return arquivo;
  }

  /// Lê um backup de [arquivo] e o aplica com [importarJson].
  ///
  /// Recusa com [BackupInvalido] se o arquivo não existir. O conteúdo é
  /// validado por [importarJson], que já recusa JSON malformado e versão
  /// desconhecida sem tocar no banco.
  Future<void> importarDeArquivo(File arquivo) async {
    if (!arquivo.existsSync()) {
      throw BackupInvalido('Arquivo não existe');
    }
    final conteudo = await arquivo.readAsString();
    await importarJson(conteudo);
  }
}
