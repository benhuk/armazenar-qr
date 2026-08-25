// Especificacao da listagem de etiquetas por produto — Fase 1.
// O dado de consumo (usadaEm) existe mas nenhuma tela mostra. Isso e o que a
// tela nova precisa: as etiquetas do produto, disponiveis primeiro.
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criar(String nome) =>
      db.criarProduto(ProdutosCompanion.insert(nome: nome));

  group('listarEtiquetasDoProduto', () {
    test('produto sem etiqueta devolve lista vazia', () async {
      final id = await criar('Parafuso');
      expect(await db.listarEtiquetasDoProduto(id), isEmpty);
    });

    test('devolve as etiquetas do produto', () async {
      final id = await criar('Parafuso');
      final codigos = await db.gerarLoteEtiquetas(3, id);

      final lista = await db.listarEtiquetasDoProduto(id);

      expect(lista, hasLength(3));
      expect(lista.map((e) => e.codigo).toSet(), codigos.toSet());
    });

    test('nao traz etiqueta de outro produto', () async {
      final a = await criar('Parafuso');
      final b = await criar('Prego');
      await db.gerarLoteEtiquetas(2, a);
      await db.gerarLoteEtiquetas(5, b);

      expect(await db.listarEtiquetasDoProduto(a), hasLength(2));
    });

    test('disponiveis vem antes das usadas', () async {
      final id = await criar('Parafuso');
      final codigos = await db.gerarLoteEtiquetas(3, id);
      await db.darBaixaPorCodigo(codigos.first);

      final lista = await db.listarEtiquetasDoProduto(id);

      expect(lista.first.usadaEm, isNull, reason: 'disponivel primeiro');
      expect(lista.last.usadaEm, isNotNull, reason: 'usada por ultimo');
    });

    test('dentro do mesmo grupo, ordena por codigo', () async {
      final id = await criar('Parafuso');
      await db.gerarLoteEtiquetas(3, id);

      final lista = await db.listarEtiquetasDoProduto(id);
      final codigos = lista.map((e) => e.codigo).toList();

      expect(codigos, List.of(codigos)..sort());
    });

    test('carrega quantas unidades cada etiqueta vale', () async {
      final id = await criar('Parafuso');
      await db.gerarLoteEtiquetas(1, id, unidades: 12);

      final lista = await db.listarEtiquetasDoProduto(id);
      expect(lista.single.unidades, 12);
    });

    test('recusa produto que nao existe', () async {
      await expectLater(
        db.listarEtiquetasDoProduto(999),
        throwsA(isA<VinculoInvalido>()),
      );
    });
  });
}
