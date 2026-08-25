import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Movimentação recusada: quantidade inválida, tipo desconhecido, produto
/// inexistente ou saída maior que o estoque disponível.
class MovimentacaoInvalida implements Exception {
  MovimentacaoInvalida(this.motivo);
  final String motivo;
  @override
  String toString() => 'MovimentacaoInvalida: $motivo';
}

/// Vínculo recusado: código inexistente, produto inexistente ou etiqueta que
/// já está vinculada a outro produto.
class VinculoInvalido implements Exception {
  VinculoInvalido(this.motivo);
  final String motivo;
  @override
  String toString() => 'VinculoInvalido: $motivo';
}

// ---------------------------------------------------------------------------
// Tabelas
// ---------------------------------------------------------------------------

@DataClassName('Produto')
class Produtos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nome => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get categoria => text().nullable()();
  IntColumn get quantidadeAtual => integer().withDefault(const Constant(0))();
  TextColumn get unidade => text().withDefault(const Constant('un'))();
  DateTimeColumn get criadoEm => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Movimentacao')
class Movimentacoes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get produtoId => integer().references(Produtos, #id)();
  TextColumn get tipo => text()(); // 'entrada' ou 'saida'
  IntColumn get quantidade => integer()();
  DateTimeColumn get data => dateTime().withDefault(currentDateAndTime)();
  TextColumn get observacao => text().nullable()();
}

@DataClassName('Etiqueta')
class Etiquetas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get codigo => text().unique()();
  // Etiqueta so existe atrelada a um produto: obrigatorio, nao anulavel.
  IntColumn get produtoId => integer().references(Produtos, #id)();
  DateTimeColumn get criadoEm => dateTime().withDefault(currentDateAndTime)();
  // Etiqueta vale por uma baixa so: aqui fica quando ela foi consumida.
  // Nulo = ainda disponivel.
  DateTimeColumn get usadaEm => dateTime().nullable()();
}

// ---------------------------------------------------------------------------
// Banco
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Produtos, Movimentacoes, Etiquetas])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'estoque_qr'));

  /// Construtor para testes: recebe um executor em memoria
  /// (`NativeDatabase.memory()`), sem tocar em disco nem no path_provider.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: etiqueta só existe atrelada a um produto. As livres
            // (produto_id NULL) perderam sentido e são descartadas — sem isso
            // a coluna não pode virar NOT NULL. A coluna `vinculado` sai
            // junto: com produto obrigatório, ela seria sempre true.
            await m.database
                .customStatement('DELETE FROM etiquetas WHERE produto_id IS NULL');
            // `usada_em` (v3) não existe na v1: entra como coluna nova aqui,
            // senão o TableMigration tenta copiá-la da tabela antiga. Ele usa
            // a definição ATUAL da tabela, não a da v2.
            await m.alterTable(
              TableMigration(etiquetas, newColumns: [etiquetas.usadaEm]),
            );
          } else if (from < 3) {
            // v3: etiqueta passa a valer por uma baixa só. As que já existem
            // ficam com usada_em nulo, ou seja, continuam disponíveis.
            await m.addColumn(etiquetas, etiquetas.usadaEm);
          }
        },
      );

  // --- Produtos -------------------------------------------------------

  Future<List<Produto>> listarProdutos() => select(produtos).get();

  Stream<List<Produto>> watchProdutos() => select(produtos).watch();

  Future<int> criarProduto(ProdutosCompanion produto) =>
      into(produtos).insert(produto);

  // --- Etiquetas --------------------------------------------------------

  /// Gera [quantidade] etiquetas para o produto [produtoId], prontas pra
  /// imprimir.
  ///
  /// Etiqueta só existe atrelada a um produto: as geradas aqui já nascem
  /// vinculadas. Recusa com [VinculoInvalido] se o produto não existir.
  Future<List<String>> gerarLoteEtiquetas(int quantidade, int produtoId) async {
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
                EtiquetasCompanion.insert(codigo: c, produtoId: produtoId),
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

  /// Dá baixa no produto dono da etiqueta [codigo] e CONSOME a etiqueta.
  ///
  /// Cada etiqueta vale por uma baixa só: relida, é recusada. Sem isso o mesmo
  /// QR na frente da câmera desconta o estoque repetidamente.
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
    String codigo,
    int quantidade, {
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

      await registrarMovimentacao(
        produtoId: etiqueta.produtoId,
        tipo: 'saida',
        quantidade: quantidade,
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
}
