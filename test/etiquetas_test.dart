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

    test('dois vinculos simultaneos na mesma etiqueta: so um vence', () async {
      // Checar `vinculado` e gravar tem que ser atomico. Sem transacao as duas
      // chamadas leem a etiqueta ainda livre, as duas passam na guarda de
      // dupla-vinculacao, e a segunda sobrescreve a primeira em silencio.
      final codigo = (await db.gerarLoteEtiquetas(1)).single;
      final primeiro = await criarProduto('Parafuso');
      final segundo = await criarProduto('Prego');

      final desfechos = await Future.wait([
        db.vincularEtiqueta(codigo, primeiro).then((_) => 'ok').catchError(
            (Object e) => e is VinculoInvalido ? 'recusado' : 'erro'),
        db.vincularEtiqueta(codigo, segundo).then((_) => 'ok').catchError(
            (Object e) => e is VinculoInvalido ? 'recusado' : 'erro'),
      ]);

      expect(desfechos.where((d) => d == 'ok'), hasLength(1),
          reason: 'exatamente um vínculo pode vencer');
      expect(desfechos.where((d) => d == 'recusado'), hasLength(1));
      expect(await db.listarEtiquetasLivres(), isEmpty);
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
