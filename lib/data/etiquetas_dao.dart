import 'package:drift/drift.dart';

import 'database.dart';

/// Geração de etiquetas e o quadro de cada produto.
extension EtiquetasDao on AppDatabase {
  // --- Etiquetas --------------------------------------------------------

  /// Gera [quantidade] etiquetas para o produto [produtoId], prontas pra
  /// imprimir.
  ///
  /// Etiqueta só existe atrelada a um produto: as geradas aqui já nascem
  /// vinculadas. Recusa com [VinculoInvalido] se o produto não existir.
  Future<List<String>> gerarLoteEtiquetas(
    int quantidade,
    int produtoId, {
    int unidades = 1,
  }) async {
    if (unidades <= 0) {
      throw MovimentacaoInvalida('unidades por etiqueta tem que ser > 0');
    }
    if (quantidade <= 0) return [];

    // Tudo numa transação: entre ler o maior número e gravar o lote não pode
    // entrar outra geração, ou os dois lotes colidiriam no índice UNIQUE.
    return transaction(() async {
      final produto = await (select(produtos)
            ..where((p) => p.id.equals(produtoId)))
          .getSingleOrNull();
      if (produto == null) {
        throw VinculoInvalido('produto $produtoId não existe');
      }

      // MAX no banco: o GLOB garante que só códigos com 6 dígitos entrem na
      // conta, então sufixo não numérico é ignorado sem filtrar em Dart.
      final linha = await customSelect(
        "SELECT MAX(CAST(SUBSTR(codigo, 5) AS INTEGER)) AS maior FROM etiquetas "
        "WHERE codigo GLOB 'PRD-[0-9][0-9][0-9][0-9][0-9][0-9]'",
        readsFrom: {etiquetas},
      ).getSingle();
      final proximo = (linha.read<int?>('maior') ?? 0) + 1;

      final codigos = [
        for (var i = 0; i < quantidade; i++) formatarCodigo(proximo + i),
      ];

      await batch((b) => b.insertAll(
            etiquetas,
            [
              for (final c in codigos)
                EtiquetasCompanion.insert(
                  codigo: c,
                  produtoId: produtoId,
                  unidades: Value(unidades),
                ),
            ],
          ));

      return codigos;
    });
  }

  /// Monta o código de etiqueta a partir do número sequencial [numero].
  ///
  /// Função pura: `PRD-` seguido do número em 6 dígitos, com zeros à esquerda.
  /// Ex.: `1` vira `PRD-000001`; `12` vira `PRD-000012`.
  String formatarCodigo(int numero) {
    return 'PRD-${numero.toString().padLeft(6, '0')}';
  }


  // --- Resumo de etiquetas ---------------------------------------------

  /// Quadro das etiquetas de [produtoId]: quantas estão disponíveis, quantas
  /// já foram usadas, e quantas unidades as disponíveis cobrem.
  ///
  /// Uma etiqueta está disponível quando `usadaEm` é nulo. `unidadesCobertas`
  /// é a soma de `unidades` das disponíveis — as usadas não contam, porque já
  /// viraram baixa.
  ///
  /// Recusa com [VinculoInvalido] se o produto não existir.
  Future<ResumoEtiquetas> resumoEtiquetas(int produtoId) async {
    final produto = await (select(produtos)
          ..where((p) => p.id.equals(produtoId)))
        .getSingleOrNull();
    if (produto == null) {
      throw VinculoInvalido('produto $produtoId não existe');
    }

    // Nome diferente do getter da tabela de propósito: `etiquetas` aqui
    // esconderia `select(etiquetas)` na própria linha que o usa.
    final linhas = await (select(etiquetas)
          ..where((t) => t.produtoId.equals(produtoId)))
        .get();

    int disponiveis = 0;
    int usadas = 0;
    int unidadesCobertas = 0;

    for (final etiqueta in linhas) {
      if (etiqueta.usadaEm == null) {
        disponiveis++;
        unidadesCobertas += etiqueta.unidades;
      } else {
        usadas++;
      }
    }

    return ResumoEtiquetas(
      disponiveis: disponiveis,
      usadas: usadas,
      unidadesCobertas: unidadesCobertas,
    );
  }

  /// Quanto do estoque de [produtoId] ainda não tem etiqueta.
  ///
  /// É `quantidadeAtual` menos as unidades já cobertas por etiqueta
  /// disponível. Nunca devolve negativo: gerar etiqueta a mais é permitido,
  /// mas a tela não deve receber número negativo.
  ///
  /// Recusa com [VinculoInvalido] se o produto não existir.
  Future<int> unidadesSemEtiqueta(int produtoId) async {
    final produto = await (select(produtos)
          ..where((p) => p.id.equals(produtoId)))
        .getSingleOrNull();
    if (produto == null) {
      throw VinculoInvalido('produto $produtoId não existe');
    }

    final resumo = await resumoEtiquetas(produtoId);
    final unidadesSemEtiqueta = produto.quantidadeAtual - resumo.unidadesCobertas;

    return unidadesSemEtiqueta < 0 ? 0 : unidadesSemEtiqueta;
  }
}
