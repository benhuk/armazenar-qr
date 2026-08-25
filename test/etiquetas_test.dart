// Especificacao de `buscarProdutoPorCodigo` — Fase 1.
// O fluxo de etiqueta livre foi removido: toda etiqueta nasce vinculada.
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criarProduto(String nome) =>
      db.criarProduto(ProdutosCompanion.insert(nome: nome));

  group('buscarProdutoPorCodigo', () {
    test('devolve o produto dono da etiqueta', () async {
      final id = await criarProduto('Parafuso');
      final codigo = (await db.gerarLoteEtiquetas(1, id)).single;

      final produto = await db.buscarProdutoPorCodigo(codigo);
      expect(produto, isNotNull);
      expect(produto!.id, id);
      expect(produto.nome, 'Parafuso');
    });

    test('devolve null para codigo inexistente', () async {
      expect(await db.buscarProdutoPorCodigo('PRD-999999'), isNull);
    });

    test('cada etiqueta aponta pro seu proprio produto', () async {
      final a = await criarProduto('Parafuso');
      final b = await criarProduto('Prego');
      final codigoA = (await db.gerarLoteEtiquetas(1, a)).single;
      final codigoB = (await db.gerarLoteEtiquetas(1, b)).single;

      expect((await db.buscarProdutoPorCodigo(codigoA))!.nome, 'Parafuso');
      expect((await db.buscarProdutoPorCodigo(codigoB))!.nome, 'Prego');
    });
  });
}
