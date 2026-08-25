// Especificacao de `gerarLoteEtiquetas` — Fase 1 (Claude Code).
// READ-ONLY para o agente local.
//
// Regra nova: etiqueta so existe atrelada a um produto. Nao ha mais etiqueta
// livre — o produto e obrigatorio no momento da criacao.
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criarProduto(String nome) =>
      db.criarProduto(ProdutosCompanion.insert(nome: nome));

  Future<void> inserirEtiquetaManual(String codigo, int produtoId) =>
      db.into(db.etiquetas).insert(
            EtiquetasCompanion.insert(codigo: codigo, produtoId: produtoId),
          );

  group('gerarLoteEtiquetas', () {
    test('devolve exatamente a quantidade pedida', () async {
      final id = await criarProduto('Parafuso');
      expect(await db.gerarLoteEtiquetas(5, id), hasLength(5));
    });

    test('os codigos devolvidos sao unicos entre si', () async {
      final id = await criarProduto('Parafuso');
      final codigos = await db.gerarLoteEtiquetas(20, id);
      expect(codigos.toSet(), hasLength(20));
    });

    test('usa o formato PRD- seguido de 6 digitos com zeros a esquerda',
        () async {
      final id = await criarProduto('Parafuso');
      final codigos = await db.gerarLoteEtiquetas(3, id);
      for (final c in codigos) {
        expect(c, matches(RegExp(r'^PRD-\d{6}$')), reason: 'codigo invalido: $c');
      }
      expect(codigos.first, 'PRD-000001');
    });

    test('persiste as etiquetas no banco', () async {
      final id = await criarProduto('Parafuso');
      final codigos = await db.gerarLoteEtiquetas(4, id);
      final salvas = await db.select(db.etiquetas).get();
      expect(salvas.map((e) => e.codigo).toList(), codigos);
    });

    test('as etiquetas nascem vinculadas ao produto informado', () async {
      final id = await criarProduto('Parafuso');
      await db.gerarLoteEtiquetas(3, id);

      final salvas = await db.select(db.etiquetas).get();
      expect(salvas, hasLength(3));
      expect(salvas.every((e) => e.produtoId == id), isTrue,
          reason: 'toda etiqueta tem que apontar pro produto');
    });

    test('recusa gerar para um produto que nao existe', () async {
      await expectLater(
        db.gerarLoteEtiquetas(2, 999),
        throwsA(isA<VinculoInvalido>()),
      );
      expect(await db.select(db.etiquetas).get(), isEmpty);
    });

    test('o segundo lote continua a numeracao, nao reinicia', () async {
      final id = await criarProduto('Parafuso');
      final primeiro = await db.gerarLoteEtiquetas(3, id);
      final segundo = await db.gerarLoteEtiquetas(2, id);

      expect(primeiro, ['PRD-000001', 'PRD-000002', 'PRD-000003']);
      expect(segundo, ['PRD-000004', 'PRD-000005']);
    });

    test('a numeracao e global: produtos diferentes nao repetem codigo',
        () async {
      final a = await criarProduto('Parafuso');
      final b = await criarProduto('Prego');

      final loteA = await db.gerarLoteEtiquetas(3, a);
      final loteB = await db.gerarLoteEtiquetas(3, b);

      expect(loteA.toSet().intersection(loteB.toSet()), isEmpty);
      expect(loteB, ['PRD-000004', 'PRD-000005', 'PRD-000006']);
    });

    test('quantidade zero devolve lista vazia e nao grava nada', () async {
      final id = await criarProduto('Parafuso');
      expect(await db.gerarLoteEtiquetas(0, id), isEmpty);
      expect(await db.select(db.etiquetas).get(), isEmpty);
    });

    test('continua a partir do maior numero ja existente no banco', () async {
      final id = await criarProduto('Parafuso');
      await inserirEtiquetaManual('PRD-000010', id);
      expect(await db.gerarLoteEtiquetas(2, id), ['PRD-000011', 'PRD-000012']);
    });

    test('ignora etiquetas de sufixo nao numerico ao calcular o proximo',
        () async {
      final id = await criarProduto('Parafuso');
      await inserirEtiquetaManual('PRD-000007', id);
      await inserirEtiquetaManual('LEGADO-ABC', id);

      expect(await db.gerarLoteEtiquetas(2, id), ['PRD-000008', 'PRD-000009']);
    });

    test('dois lotes simultaneos nao colidem', () async {
      final id = await criarProduto('Parafuso');
      final lotes = await Future.wait([
        db.gerarLoteEtiquetas(5, id),
        db.gerarLoteEtiquetas(5, id),
      ]);

      expect({...lotes[0], ...lotes[1]}, hasLength(10));
      expect(await db.select(db.etiquetas).get(), hasLength(10));
    });
  });
}
