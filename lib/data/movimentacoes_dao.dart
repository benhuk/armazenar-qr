import 'package:drift/drift.dart';

import 'database.dart';

/// Entrada, saída e a baixa que o scanner dispara.
extension MovimentacoesDao on AppDatabase {
  // --- Scanner / baixa ----------------------------------------------------

  /// Busca o produto dono de um código escaneado.
  ///
  /// Devolve `null` só quando o código não existe: se a etiqueta existe, ela
  /// tem produto — o schema garante.
  Future<Produto?> buscarProdutoPorCodigo(String codigo) async {
    final etiqueta = await (select(etiquetas)
          ..where((t) => t.codigo.equals(codigo)))
        .getSingleOrNull();
    if (etiqueta == null) return null;

    return (select(produtos)..where((p) => p.id.equals(etiqueta.produtoId)))
        .getSingleOrNull();
  }

  /// Dá baixa (ou entrada) e registra a movimentação, tudo em uma transação.
  ///
  /// A estrutura transacional é fixa: buscar o produto, calcular o novo saldo,
  /// gravar o saldo e o histórico — tudo ou nada. O que decide o saldo (e o que
  /// é recusado) mora em [calcularNovaQuantidade].
  Future<void> registrarMovimentacao({
    required int produtoId,
    required String tipo, // 'entrada' ou 'saida'
    required int quantidade,
    String? observacao,
  }) async {
    await transaction(() async {
      final produto =
          await (select(produtos)..where((p) => p.id.equals(produtoId)))
              .getSingleOrNull();
      if (produto == null) {
        throw MovimentacaoInvalida('produto $produtoId não existe');
      }

      final novaQuantidade = calcularNovaQuantidade(
        estoqueAtual: produto.quantidadeAtual,
        tipo: tipo,
        quantidade: quantidade,
      );

      await (update(produtos)..where((p) => p.id.equals(produtoId))).write(
        ProdutosCompanion(quantidadeAtual: Value(novaQuantidade)),
      );

      await into(movimentacoes).insert(
        MovimentacoesCompanion.insert(
          produtoId: produtoId,
          tipo: tipo,
          quantidade: quantidade,
          observacao: Value(observacao),
        ),
      );
    });
  }

  /// Decide o novo saldo de estoque, ou recusa a movimentação.
  ///
  /// Função pura: não toca no banco. Regras:
  /// - [quantidade] tem que ser maior que zero;
  /// - [tipo] só pode ser `'entrada'` ou `'saida'`;
  /// - `'entrada'` soma, `'saida'` subtrai;
  /// - saída não pode deixar o estoque negativo (zerar é permitido).
  ///
  /// Recusa lançando [MovimentacaoInvalida] com o motivo.
  int calcularNovaQuantidade({
    required int estoqueAtual,
    required String tipo,
    required int quantidade,
  }) {
    if (quantidade <= 0) {
      throw MovimentacaoInvalida('Quantidade deve ser maior que zero');
    }

    if (tipo != 'entrada' && tipo != 'saida') {
      throw MovimentacaoInvalida('Tipo de movimentação inválido');
    }

    final novaQuantidade = tipo == 'entrada'
        ? estoqueAtual + quantidade
        : estoqueAtual - quantidade;

    if (novaQuantidade < 0) {
      throw MovimentacaoInvalida('Não pode deixar o estoque negativo');
    }

    return novaQuantidade;
  }


  /// Dá baixa no produto dono da etiqueta [codigo] e CONSOME a etiqueta.
  ///
  /// A quantidade vem da própria etiqueta (`unidades`), não do chamador: quem
  /// escaneia não escolhe nada. Cada etiqueta vale por uma baixa só; relida,
  /// é recusada.
  ///
  /// Checar e marcar tem que ser atômico, junto com a movimentação: se a baixa
  /// for recusada (estoque insuficiente, quantidade inválida), a etiqueta
  /// continua valendo — seria perverso queimá-la numa operação que não
  /// aconteceu.
  ///
  /// Recusa com [VinculoInvalido] se o código não existir ou já tiver sido
  /// usado, e com [MovimentacaoInvalida] se a quantidade for inválida ou maior
  /// que o estoque.
  Future<Produto> darBaixaPorCodigo(
    String codigo, {
    String? observacao,
  }) async {
    return transaction(() async {
      final etiqueta = await (select(etiquetas)
            ..where((t) => t.codigo.equals(codigo)))
          .getSingleOrNull();
      if (etiqueta == null) {
        throw VinculoInvalido('código $codigo não existe');
      }
      if (etiqueta.usadaEm != null) {
        throw VinculoInvalido('etiqueta $codigo já foi utilizada');
      }

      // Quem decide o quanto é a etiqueta, não quem escaneia.
      await registrarMovimentacao(
        produtoId: etiqueta.produtoId,
        tipo: 'saida',
        quantidade: etiqueta.unidades,
        observacao: observacao,
      );

      await (update(etiquetas)..where((t) => t.codigo.equals(codigo)))
          .write(EtiquetasCompanion(usadaEm: Value(DateTime.now())));

      return (select(produtos)..where((p) => p.id.equals(etiqueta.produtoId)))
          .getSingle();
    });
  }


  // --- Histórico ------------------------------------------------------

  Future<List<Movimentacao>> listarMovimentacoes({int? produtoId}) {
    final query = select(movimentacoes);
    if (produtoId != null) {
      query.where((m) => m.produtoId.equals(produtoId));
    }
    query.orderBy([(m) => OrderingTerm.desc(m.data)]);
    return query.get();
  }

  /// Histórico com o nome do produto junto, para a tela não mostrar "#id".
  ///
  /// Usa [listarMovimentacoes] (que já ordena da mais recente para a mais
  /// antiga e aceita o filtro) e casa cada movimentação com o nome do seu
  /// produto. A ordem de [listarMovimentacoes] é preservada.
  Future<List<MovimentacaoComProduto>> listarMovimentacoesDetalhadas({
    int? produtoId,
  }) async {
    // Nome diferente do getter da tabela: `produtos` aqui o esconderia, e
    // qualquer select(produtos) futuro neste método pararia de compilar.
    final todos = await listarProdutos();
    final nomePorId = {for (final p in todos) p.id: p.nome};

    final movimentacoes = await listarMovimentacoes(produtoId: produtoId);
    final detalhadas = movimentacoes.map((m) => MovimentacaoComProduto(
          movimentacao: m,
          nomeProduto: nomePorId[m.produtoId] ?? 'Produto removido',
        )).toList();

    return detalhadas;
  }
}
