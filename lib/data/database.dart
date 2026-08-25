import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

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

    final existingEtiquetas = await select(etiquetas).get();
    int lastNumber = 0;

    for (final etiqueta in existingEtiquetas) {
      final match = RegExp(r'^PRD-(\d{6})$').firstMatch(etiqueta.codigo);
      if (match != null) {
        final number = int.parse(match.group(1)!);
        if (number > lastNumber) {
          lastNumber = number;
        }
      }
    }

    final newEtiquetas = <String>[];
    for (int i = 0; i < quantidade; i++) {
      lastNumber++;
      final code = 'PRD-${lastNumber.toString().padLeft(6, '0')}';
      newEtiquetas.add(code);
      await into(etiquetas).insert(EtiquetasCompanion(codigo: Value(code)));
    }

    return newEtiquetas;
  }

  /// Etiquetas já geradas mas ainda não vinculadas a um produto.
  Future<List<Etiqueta>> listarEtiquetasLivres() =>
      (select(etiquetas)..where((t) => t.vinculado.equals(false))).get();

  /// Vincula uma etiqueta livre a um produto recém-cadastrado.
  Future<void> vincularEtiqueta(String codigo, int produtoId) =>
      (update(etiquetas)..where((t) => t.codigo.equals(codigo))).write(
        EtiquetasCompanion(
          vinculado: const Value(true),
          produtoId: Value(produtoId),
        ),
      );

  // --- Scanner / baixa ----------------------------------------------------

  /// Busca o produto vinculado a um código escaneado.
  Future<Produto?> buscarProdutoPorCodigo(String codigo) async {
    final etiqueta = await (select(etiquetas)
          ..where((t) => t.codigo.equals(codigo)))
        .getSingleOrNull();
    if (etiqueta?.produtoId == null) return null;

    return (select(produtos)..where((p) => p.id.equals(etiqueta!.produtoId!)))
        .getSingleOrNull();
  }

  /// Dá baixa (ou entrada) e registra a movimentação, tudo em uma transação.
  Future<void> registrarMovimentacao({
    required int produtoId,
    required String tipo, // 'entrada' ou 'saida'
    required int quantidade,
    String? observacao,
  }) async {
    await transaction(() async {
      final produto =
          await (select(produtos)..where((p) => p.id.equals(produtoId)))
              .getSingle();

      final novaQuantidade = tipo == 'saida'
          ? produto.quantidadeAtual - quantidade
          : produto.quantidadeAtual + quantidade;

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
