// Especificacao de `vincularEtiqueta` e `buscarProdutoPorCodigo` — Fase 1.
// Sem andaime: tarefa inteira no loop local, pra medir onde fica o limite.
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criarProduto(String nome) =>
      db.criarProduto(ProdutosCompanion.insert(nome: nome));

  group('vincularEtiqueta', () {
    test('vincula uma etiqueta livre a um produto', () async {
      final codigo = (await db.gerarLoteEtiquetas(1)).single;
      final id = await criarProduto('Parafuso');

      await db.vincularEtiqueta(codigo, id);

      final etiqueta = await (db.select(db.etiquetas)
            ..where((t) => t.codigo.equals(codigo)))
          .getSingle();
      expect(etiqueta.vinculado, isTrue);
      expect(etiqueta.produtoId, id);
    });

    test('a etiqueta vinculada sai da lista de livres', () async {
      final codigos = await db.gerarLoteEtiquetas(3);
      final id = await criarProduto('Porca');

      await db.vincularEtiqueta(codigos.first, id);

      final livres = await db.listarEtiquetasLivres();
      expect(livres, hasLength(2));
      expect(livres.map((e) => e.codigo), isNot(contains(codigos.first)));
    });

    test('recusa vincular uma etiqueta ja vinculada', () async {
      final codigo = (await db.gerarLoteEtiquetas(1)).single;
      final primeiro = await criarProduto('Parafuso');
      final segundo = await criarProduto('Prego');

      await db.vincularEtiqueta(codigo, primeiro);

      await expectLater(
        db.vincularEtiqueta(codigo, segundo),
        throwsA(isA<VinculoInvalido>()),
      );

      // continua apontando pro primeiro produto
      final etiqueta = await (db.select(db.etiquetas)
            ..where((t) => t.codigo.equals(codigo)))
          .getSingle();
      expect(etiqueta.produtoId, primeiro);
    });

    test('recusa codigo que nao existe', () async {
      final id = await criarProduto('Parafuso');
      await expectLater(
        db.vincularEtiqueta('PRD-999999', id),
        throwsA(isA<VinculoInvalido>()),
      );
    });

    test('recusa produto que nao existe', () async {
      final codigo = (await db.gerarLoteEtiquetas(1)).single;
      await expectLater(
        db.vincularEtiqueta(codigo, 999),
        throwsA(isA<VinculoInvalido>()),
      );

      // a etiqueta continua livre
      expect(await db.listarEtiquetasLivres(), hasLength(1));
    });
  });

  group('buscarProdutoPorCodigo', () {
    test('devolve o produto vinculado ao codigo', () async {
      final codigo = (await db.gerarLoteEtiquetas(1)).single;
      final id = await criarProduto('Parafuso');
      await db.vincularEtiqueta(codigo, id);

      final produto = await db.buscarProdutoPorCodigo(codigo);
      expect(produto, isNotNull);
      expect(produto!.id, id);
      expect(produto.nome, 'Parafuso');
    });

    test('devolve null para codigo inexistente', () async {
      expect(await db.buscarProdutoPorCodigo('PRD-999999'), isNull);
    });

    test('devolve null para etiqueta impressa mas ainda livre', () async {
      final codigo = (await db.gerarLoteEtiquetas(1)).single;
      expect(await db.buscarProdutoPorCodigo(codigo), isNull);
    });
  });
}
