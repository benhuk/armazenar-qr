// Especificacao de `darBaixaPorCodigo` — Fase 1.
//
// Modelo: a etiqueta carrega quantas unidades vale. Quem escaneia nao escolhe
// nada — le e a baixa acontece. Etiqueta avulsa vale 1; etiqueta de caixa vale
// o que foi definido ao gerar.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criarProduto(String nome, {int estoque = 0}) => db.criarProduto(
        ProdutosCompanion.insert(
          nome: nome,
          quantidadeAtual: Value(estoque),
        ),
      );

  Future<int> estoqueDe(int id) async {
    final p = await (db.select(db.produtos)..where((t) => t.id.equals(id)))
        .getSingle();
    return p.quantidadeAtual;
  }

  group('etiqueta avulsa (1 unidade)', () {
    test('baixa uma unidade', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo);

      expect(await estoqueDe(id), 9);
    });

    test('devolve o produto com o estoque ja descontado', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final produto = await db.darBaixaPorCodigo(codigo);

      expect(produto.id, id);
      expect(produto.nome, 'Parafuso');
      expect(produto.quantidadeAtual, 9);
    });

    test('registra a movimentacao como saida', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo, observacao: 'bipe no galpao');

      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs, hasLength(1));
      expect(movs.single.tipo, 'saida');
      expect(movs.single.quantidade, 1);
      expect(movs.single.observacao, 'bipe no galpao');
    });

    test('observacao e opcional', () async {
      final id = await criarProduto('Parafuso', estoque: 5);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo);

      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs.single.observacao, isNull);
    });
  });

  group('etiqueta de caixa (N unidades)', () {
    test('baixa o que a etiqueta vale, nao 1', () async {
      final id = await criarProduto('Parafuso', estoque: 100);
      final codigo =
          (await db.gerarLoteEtiquetas(1, id, unidades: 12)).single;

      await db.darBaixaPorCodigo(codigo);

      expect(await estoqueDe(id), 88);
    });

    test('a movimentacao registra a quantidade da etiqueta', () async {
      final id = await criarProduto('Parafuso', estoque: 100);
      final codigo =
          (await db.gerarLoteEtiquetas(1, id, unidades: 12)).single;

      await db.darBaixaPorCodigo(codigo);

      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs.single.quantidade, 12);
    });

    test('etiquetas de tamanhos diferentes convivem no mesmo produto',
        () async {
      final id = await criarProduto('Parafuso', estoque: 100);
      final caixa = (await db.gerarLoteEtiquetas(1, id, unidades: 12)).single;
      final avulsa = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(caixa);
      await db.darBaixaPorCodigo(avulsa);

      expect(await estoqueDe(id), 87);
    });

    test('gerar com unidades zero ou negativa e recusado', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      for (final u in [0, -3]) {
        await expectLater(
          db.gerarLoteEtiquetas(1, id, unidades: u),
          throwsA(isA<MovimentacaoInvalida>()),
        );
      }
      expect(await db.select(db.etiquetas).get(), isEmpty);
    });

    test('sem informar unidades, a etiqueta vale 1', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      await db.gerarLoteEtiquetas(2, id);

      final salvas = await db.select(db.etiquetas).get();
      expect(salvas.every((e) => e.unidades == 1), isTrue);
    });
  });

  group('recusas', () {
    test('recusa codigo que nao existe', () async {
      await expectLater(
        db.darBaixaPorCodigo('PRD-999999'),
        throwsA(isA<VinculoInvalido>()),
      );
      expect(await db.listarMovimentacoes(), isEmpty);
    });

    test('a mesma etiqueta nao pode dar baixa duas vezes', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo);

      await expectLater(
        db.darBaixaPorCodigo(codigo),
        throwsA(isA<VinculoInvalido>()),
      );
      expect(await estoqueDe(id), 9, reason: 'so a primeira leitura conta');
      expect(await db.listarMovimentacoes(produtoId: id), hasLength(1));
    });

    test('cada etiqueta do lote vale por uma baixa', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigos = await db.gerarLoteEtiquetas(3, id);

      for (final c in codigos) {
        await db.darBaixaPorCodigo(c);
      }

      expect(await estoqueDe(id), 7);
      expect(await db.listarMovimentacoes(produtoId: id), hasLength(3));
    });

    test('recusa caixa maior que o estoque', () async {
      final id = await criarProduto('Parafuso', estoque: 5);
      final codigo =
          (await db.gerarLoteEtiquetas(1, id, unidades: 12)).single;

      await expectLater(
        db.darBaixaPorCodigo(codigo),
        throwsA(isA<MovimentacaoInvalida>()),
      );
      expect(await estoqueDe(id), 5);
    });

    test('baixa recusada nao consome a etiqueta', () async {
      // Seria perverso queimar a etiqueta numa operacao que nao aconteceu.
      final id = await criarProduto('Parafuso', estoque: 5);
      final codigo =
          (await db.gerarLoteEtiquetas(1, id, unidades: 12)).single;

      await expectLater(
        db.darBaixaPorCodigo(codigo),
        throwsA(isA<MovimentacaoInvalida>()),
      );

      // repoe o estoque e a mesma etiqueta ainda vale
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'entrada', quantidade: 10);
      final produto = await db.darBaixaPorCodigo(codigo);
      expect(produto.quantidadeAtual, 3);
    });

    test('baixa que zera o estoque e permitida', () async {
      final id = await criarProduto('Parafuso', estoque: 3);
      final codigo = (await db.gerarLoteEtiquetas(1, id, unidades: 3)).single;

      final produto = await db.darBaixaPorCodigo(codigo);
      expect(produto.quantidadeAtual, 0);
    });

    test('duas leituras simultaneas da mesma etiqueta: so uma vence', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final desfechos = await Future.wait([
        db.darBaixaPorCodigo(codigo).then((_) => 'ok').catchError(
            (Object e) => e is VinculoInvalido ? 'recusado' : 'erro'),
        db.darBaixaPorCodigo(codigo).then((_) => 'ok').catchError(
            (Object e) => e is VinculoInvalido ? 'recusado' : 'erro'),
      ]);

      expect(desfechos.where((d) => d == 'ok'), hasLength(1));
      expect(await estoqueDe(id), 9);
      expect(await db.listarMovimentacoes(produtoId: id), hasLength(1));
    });
  });
}
