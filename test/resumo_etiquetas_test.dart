// Especificacao do resumo de etiquetas — Fase 1.
// As duas telas de geracao precisam saber o que ja existe pro produto: quantas
// etiquetas estao disponiveis, quantas unidades elas cobrem, e quanto do
// estoque ainda esta sem etiqueta.
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

  group('resumoEtiquetas', () {
    test('produto sem etiqueta: tudo zero', () async {
      final id = await criarProduto('Parafuso', estoque: 10);

      final r = await db.resumoEtiquetas(id);

      expect(r.disponiveis, 0);
      expect(r.usadas, 0);
      expect(r.unidadesCobertas, 0);
    });

    test('conta as etiquetas disponiveis', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      await db.gerarLoteEtiquetas(3, id);

      final r = await db.resumoEtiquetas(id);

      expect(r.disponiveis, 3);
      expect(r.usadas, 0);
    });

    test('etiqueta consumida sai de disponiveis e entra em usadas', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigos = await db.gerarLoteEtiquetas(3, id);
      await db.darBaixaPorCodigo(codigos.first);

      final r = await db.resumoEtiquetas(id);

      expect(r.disponiveis, 2);
      expect(r.usadas, 1);
    });

    test('unidadesCobertas soma o valor das etiquetas disponiveis', () async {
      final id = await criarProduto('Parafuso', estoque: 100);
      await db.gerarLoteEtiquetas(2, id, unidades: 12); // 24
      await db.gerarLoteEtiquetas(3, id); // 3

      final r = await db.resumoEtiquetas(id);

      expect(r.disponiveis, 5);
      expect(r.unidadesCobertas, 27);
    });

    test('etiqueta usada nao conta nas unidades cobertas', () async {
      final id = await criarProduto('Parafuso', estoque: 100);
      final caixas = await db.gerarLoteEtiquetas(2, id, unidades: 10);
      await db.darBaixaPorCodigo(caixas.first);

      final r = await db.resumoEtiquetas(id);

      expect(r.disponiveis, 1);
      expect(r.unidadesCobertas, 10);
    });

    test('nao mistura etiquetas de outro produto', () async {
      final a = await criarProduto('Parafuso', estoque: 10);
      final b = await criarProduto('Prego', estoque: 10);
      await db.gerarLoteEtiquetas(2, a);
      await db.gerarLoteEtiquetas(5, b);

      expect((await db.resumoEtiquetas(a)).disponiveis, 2);
      expect((await db.resumoEtiquetas(b)).disponiveis, 5);
    });

    test('recusa produto que nao existe', () async {
      await expectLater(
        db.resumoEtiquetas(999),
        throwsA(isA<VinculoInvalido>()),
      );
    });
  });

  group('unidadesSemEtiqueta', () {
    test('sem etiqueta nenhuma, e o estoque inteiro', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      expect(await db.unidadesSemEtiqueta(id), 10);
    });

    test('desconta o que as etiquetas disponiveis ja cobrem', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      await db.gerarLoteEtiquetas(4, id);

      expect(await db.unidadesSemEtiqueta(id), 6);
    });

    test('conta o valor da caixa, nao a quantidade de etiquetas', () async {
      final id = await criarProduto('Parafuso', estoque: 100);
      await db.gerarLoteEtiquetas(2, id, unidades: 12);

      expect(await db.unidadesSemEtiqueta(id), 76);
    });

    test('nunca devolve negativo, mesmo com etiquetas a mais', () async {
      // Gerar mais etiquetas que o estoque e permitido; o resumo so nao pode
      // devolver numero negativo pra tela.
      final id = await criarProduto('Parafuso', estoque: 3);
      await db.gerarLoteEtiquetas(10, id);

      expect(await db.unidadesSemEtiqueta(id), 0);
    });

    test('etiqueta usada volta a descobrir o estoque', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigos = await db.gerarLoteEtiquetas(4, id);
      // consumir a etiqueta baixa o estoque (10->9) e tira ela da cobertura
      await db.darBaixaPorCodigo(codigos.first);

      expect(await db.unidadesSemEtiqueta(id), 6);
    });
  });
}
