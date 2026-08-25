// Especificacao de `darBaixaPorCodigo` — Fase 1.
// E o que o scanner precisa: um codigo lido vira movimentacao de saida.
// Hoje a tela so mostra o nome do produto e nao mexe no estoque.
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

  group('darBaixaPorCodigo', () {
    test('baixa a quantidade do estoque do produto da etiqueta', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo, 3);

      expect(await estoqueDe(id), 7);
    });

    test('devolve o produto que sofreu a baixa', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final produto = await db.darBaixaPorCodigo(codigo, 2);

      expect(produto.id, id);
      expect(produto.nome, 'Parafuso');
    });

    test('o produto devolvido ja reflete o estoque novo', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final produto = await db.darBaixaPorCodigo(codigo, 4);

      expect(produto.quantidadeAtual, 6,
          reason: 'a tela mostra esse numero depois do bipe');
    });

    test('registra a movimentacao no historico como saida', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo, 3, observacao: 'bipe no galpao');

      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs, hasLength(1));
      expect(movs.single.tipo, 'saida');
      expect(movs.single.quantidade, 3);
      expect(movs.single.observacao, 'bipe no galpao');
    });

    test('observacao e opcional', () async {
      final id = await criarProduto('Parafuso', estoque: 5);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo, 1);

      final movs = await db.listarMovimentacoes(produtoId: id);
      expect(movs.single.observacao, isNull);
    });

    test('recusa codigo que nao existe', () async {
      await expectLater(
        db.darBaixaPorCodigo('PRD-999999', 1),
        throwsA(isA<VinculoInvalido>()),
      );
    });

    test('codigo inexistente nao grava movimentacao nenhuma', () async {
      await criarProduto('Parafuso', estoque: 5);
      await expectLater(
        db.darBaixaPorCodigo('PRD-999999', 1),
        throwsA(isA<VinculoInvalido>()),
      );
      expect(await db.listarMovimentacoes(), isEmpty);
    });

    test('recusa baixa maior que o estoque', () async {
      final id = await criarProduto('Parafuso', estoque: 2);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await expectLater(
        db.darBaixaPorCodigo(codigo, 5),
        throwsA(isA<MovimentacaoInvalida>()),
      );
      expect(await estoqueDe(id), 2, reason: 'estoque nao pode mudar');
      expect(await db.listarMovimentacoes(), isEmpty);
    });

    test('recusa quantidade zero ou negativa', () async {
      final id = await criarProduto('Parafuso', estoque: 5);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      for (final q in [0, -2]) {
        await expectLater(
          db.darBaixaPorCodigo(codigo, q),
          throwsA(isA<MovimentacaoInvalida>()),
        );
      }
      expect(await estoqueDe(id), 5);
    });

    test('baixa que zera o estoque e permitida', () async {
      final id = await criarProduto('Parafuso', estoque: 3);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final produto = await db.darBaixaPorCodigo(codigo, 3);

      expect(produto.quantidadeAtual, 0);
    });

    test('duas etiquetas do mesmo produto baixam do mesmo estoque', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigos = await db.gerarLoteEtiquetas(2, id);

      await db.darBaixaPorCodigo(codigos[0], 2);
      await db.darBaixaPorCodigo(codigos[1], 3);

      expect(await estoqueDe(id), 5);
    });

    test('a mesma etiqueta nao pode dar baixa duas vezes', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await db.darBaixaPorCodigo(codigo, 1);

      await expectLater(
        db.darBaixaPorCodigo(codigo, 1),
        throwsA(isA<VinculoInvalido>()),
      );
      expect(await estoqueDe(id), 9, reason: 'so a primeira leitura conta');
      expect(await db.listarMovimentacoes(produtoId: id), hasLength(1));
    });

    test('cada etiqueta do lote vale por uma baixa', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigos = await db.gerarLoteEtiquetas(3, id);

      for (final c in codigos) {
        await db.darBaixaPorCodigo(c, 1);
      }

      expect(await estoqueDe(id), 7);
      expect(await db.listarMovimentacoes(produtoId: id), hasLength(3));
    });

    test('baixa recusada nao consome a etiqueta', () async {
      // Se o estoque nao dava, a etiqueta continua valendo: seria perverso
      // queimar a etiqueta numa operacao que nao aconteceu.
      final id = await criarProduto('Parafuso', estoque: 2);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      await expectLater(
        db.darBaixaPorCodigo(codigo, 5),
        throwsA(isA<MovimentacaoInvalida>()),
      );

      final produto = await db.darBaixaPorCodigo(codigo, 2);
      expect(produto.quantidadeAtual, 0);
    });

    test('duas leituras simultaneas da mesma etiqueta: so uma vence', () async {
      // Checar `usadaEm` e gravar tem que ser atomico, ou o bipe duplo passa
      // pelas duas guardas antes de qualquer uma marcar a etiqueta.
      final id = await criarProduto('Parafuso', estoque: 10);
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final desfechos = await Future.wait([
        db.darBaixaPorCodigo(codigo, 1).then((_) => 'ok').catchError(
            (Object e) => e is VinculoInvalido ? 'recusado' : 'erro'),
        db.darBaixaPorCodigo(codigo, 1).then((_) => 'ok').catchError(
            (Object e) => e is VinculoInvalido ? 'recusado' : 'erro'),
      ]);

      expect(desfechos.where((d) => d == 'ok'), hasLength(1));
      expect(await estoqueDe(id), 9);
      expect(await db.listarMovimentacoes(produtoId: id), hasLength(1));
    });
  });
}
