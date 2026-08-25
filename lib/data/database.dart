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

  /// Gera [quantidade] códigos únicos e livres, prontos pra imprimir.
  ///
  /// Formato `PRD-` + 6 dígitos com zeros à esquerda. Continua a numeração a
  /// partir do maior número já existente na tabela, ignorando códigos cujo
  /// sufixo não seja numérico. Devolve os códigos gerados, na ordem.
  Future<List<String>> gerarLoteEtiquetas(int quantidade) async {
    if (quantidade <= 0) return [];

    // Tudo numa transação: entre ler o maior número e gravar o lote não pode
    // entrar outra geração, ou os dois lotes colidiriam no índice UNIQUE.
    return transaction(() async {
      // MAX no banco em vez de carregar a tabela: o GLOB garante que só
      // códigos com 6 dígitos entrem na conta, então o sufixo não numérico é
      // ignorado sem precisar filtrar em Dart.
      final linha = await customSelect(
        "SELECT MAX(CAST(SUBSTR(codigo, 5) AS INTEGER)) AS maior FROM etiquetas "
        "WHERE codigo GLOB 'PRD-[0-9][0-9][0-9][0-9][0-9][0-9]'",
        readsFrom: {etiquetas},
      ).getSingle();
      final proximo = (linha.read<int?>('maior') ?? 0) + 1;

      final codigos = [
        for (var i = 0; i < quantidade; i++)
          'PRD-${(proximo + i).toString().padLeft(6, '0')}',
      ];

      // batch = uma única ida ao banco, e all-or-nothing: se um insert falhar,
      // nenhum código do lote fica gravado.
      await batch((b) => b.insertAll(
            etiquetas,
            [for (final c in codigos) EtiquetasCompanion.insert(codigo: c)],
          ));

      return codigos;
    });
  }

  /// Etiquetas já geradas mas ainda não vinculadas a um produto.
  Future<List<Etiqueta>> listarEtiquetasLivres() =>
      (select(etiquetas)..where((t) => t.vinculado.equals(false))).get();

  /// Vincula uma etiqueta livre a um produto recém-cadastrado.
  ///
  /// Recusa com [VinculoInvalido] se o código não existir, se o produto não
  /// existir, ou se a etiqueta já estiver vinculada — inclusive ao mesmo
  /// produto. Em caso de recusa nada é gravado.
  Future<void> vincularEtiqueta(String codigo, int produtoId) async {
    // Checar `vinculado` e gravar tem que ser atômico: sem a transação, duas
    // chamadas simultâneas leem a etiqueta ainda livre, as duas passam na
    // guarda de dupla-vinculação, e a segunda sobrescreve a primeira.
    await transaction(() async {
      final etiqueta = await (select(etiquetas)
            ..where((t) => t.codigo.equals(codigo)))
          .getSingleOrNull();
      if (etiqueta == null) {
        throw VinculoInvalido('código $codigo não existe');
      }
      if (etiqueta.vinculado) {
        throw VinculoInvalido('etiqueta $codigo já está vinculada');
      }

      final produto = await (select(produtos)
            ..where((p) => p.id.equals(produtoId)))
          .getSingleOrNull();
      if (produto == null) {
        throw VinculoInvalido('produto $produtoId não existe');
      }

      await (update(etiquetas)..where((t) => t.codigo.equals(codigo))).write(
        EtiquetasCompanion(
          vinculado: const Value(true),
          produtoId: Value(produtoId),
        ),
      );
    });
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
