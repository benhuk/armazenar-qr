// Especificacao de `registrarMovimentacao` — Fase 1 (Claude Code).
// READ-ONLY para o agente local.
//
// A estrutura da transacao ja vem pronta no alvo (invariante estrutural, que o
// modelo local nao da conta). O que falta implementar e `_calcularNovaQuantidade`:
// funcao pura, sem Drift, que decide o novo saldo e recusa o que e invalido.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criarProduto({int estoque = 0}) => db.criarProduto(
        ProdutosCompanion.insert(
          nome: 'Parafuso',
          quantidadeAtual: Value(estoque),
        ),
      );

  Future<int> estoqueDe(int id) async {
    final p = await (db.select(db.produtos)..where((t) => t.id.equals(id)))
        .getSingle();
    return p.quantidadeAtual;
  }

  group('registrarMovimentacao', () {
    test('entrada soma ao estoque', () async {
      final id = await criarProduto(estoque: 10);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'entrada', quantidade: 5);
      expect(await estoqueDe(id), 15);
    });

    test('saida subtrai do estoque', () async {
      final id = await criarProduto(estoque: 10);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 4);
      expect(await estoqueDe(id), 6);
    });

    test('saida que zera o estoque e permitida', () async {
      final id = await criarProduto(estoque: 7);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 7);
      expect(await estoqueDe(id), 0);
    });

    test('grava a movimentacao no historico', () async {
      final id = await criarProduto(estoque: 3);
      await db.registrarMovimentacao(
        produtoId: id,
        tipo: 'entrada',
        quantidade: 2,
        observacao: 'compra',
      );

      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs, hasLength(1));
      expect(movs.single.tipo, 'entrada');
      expect(movs.single.quantidade, 2);
      expect(movs.single.observacao, 'compra');
    });

    test('observacao e opcional', () async {
      final id = await criarProduto(estoque: 1);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'entrada', quantidade: 1);
      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs.single.observacao, isNull);
    });

    test('recusa saida maior que o estoque', () async {
      final id = await criarProduto(estoque: 3);
      expect(
        () => db.registrarMovimentacao(
            produtoId: id, tipo: 'saida', quantidade: 4),
        throwsA(isA<MovimentacaoInvalida>()),
      );
    });

    test('saida recusada nao altera estoque nem grava historico', () async {
      // A guarda tem que disparar DENTRO da transacao: se o estoque fosse
      // escrito antes da checagem, sobraria estado parcial.
      final id = await criarProduto(estoque: 3);
      await expectLater(
        db.registrarMovimentacao(produtoId: id, tipo: 'saida', quantidade: 10),
        throwsA(isA<MovimentacaoInvalida>()),
      );

      expect(await estoqueDe(id), 3);
      expect(await db.listarMovimentacoes(produtoId: id), isEmpty);
    });

    test('recusa quantidade zero ou negativa', () async {
      final id = await criarProduto(estoque: 5);
      for (final q in [0, -3]) {
        await expectLater(
          db.registrarMovimentacao(
              produtoId: id, tipo: 'entrada', quantidade: q),
          throwsA(isA<MovimentacaoInvalida>()),
        );
      }
      expect(await estoqueDe(id), 5);
    });

    test('recusa tipo desconhecido', () async {
      final id = await criarProduto(estoque: 5);
      await expectLater(
        db.registrarMovimentacao(
            produtoId: id, tipo: 'devolucao', quantidade: 1),
        throwsA(isA<MovimentacaoInvalida>()),
      );
      expect(await estoqueDe(id), 5);
    });

    test('recusa produto inexistente', () async {
      await expectLater(
        db.registrarMovimentacao(
            produtoId: 999, tipo: 'entrada', quantidade: 1),
        throwsA(isA<MovimentacaoInvalida>()),
      );
    });
  });
}
