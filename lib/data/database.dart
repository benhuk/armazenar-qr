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
  BoolColumn get vinculado => boolean().withDefault(const Constant(false))();
  IntColumn get produtoId => integer().nullable().references(Produtos, #id)();
  DateTimeColumn get criadoEm => dateTime().withDefault(currentDateAndTime)();
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
  int get schemaVersion => 1;

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
  /// vinculadas. Formato `PRD-` + 6 dígitos com zeros à esquerda. A numeração é
  /// global — continua a partir do maior número existente na tabela inteira,
  /// não por produto —, ignorando códigos de sufixo não numérico.
  ///
  /// Recusa com [VinculoInvalido] se o produto não existir; nesse caso nada é
  /// gravado. Devolve os códigos gerados, na ordem.
  Future<List<String>> gerarLoteEtiquetas(int quantidade, int produtoId) async {
    throw UnimplementedError('gerarLoteEtiquetas');
  }

  // --- Scanner / baixa ----------------------------------------------------

  /// Busca o produto vinculado a um código escaneado.
  ///
  /// Devolve `null` se o código não existir ou se a etiqueta ainda estiver
  /// livre (impressa, mas não vinculada a nenhum produto).
  Future<Produto?> buscarProdutoPorCodigo(String codigo) async {
    final etiqueta = await (select(etiquetas)
          ..where((t) => t.codigo.equals(codigo)))
        .getSingleOrNull();

    if (etiqueta == null || !etiqueta.vinculado) {
      return null;
    }

    return (select(produtos)..where((p) => p.id.equals(etiqueta.produtoId!))).getSingleOrNull();
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
