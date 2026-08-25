// Especificacao de `gerarLoteEtiquetas` — escrita na Fase 1 (Claude Code).
// READ-ONLY para o agente local: o orquestrador restaura este arquivo antes
// de cada tentativa (§6.1).
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Insere uma etiqueta direto na tabela, sem passar pela funcao sob teste.
  Future<void> inserirEtiquetaManual(String codigo) =>
      db.into(db.etiquetas).insert(EtiquetasCompanion.insert(codigo: codigo));

  group('gerarLoteEtiquetas', () {
    test('devolve exatamente a quantidade pedida', () async {
      expect(await db.gerarLoteEtiquetas(5), hasLength(5));
    });

    test('os codigos devolvidos sao unicos entre si', () async {
      final codigos = await db.gerarLoteEtiquetas(20);
      expect(codigos.toSet(), hasLength(20));
    });

    test('usa o formato PRD- seguido de 6 digitos com zeros a esquerda',
        () async {
      final codigos = await db.gerarLoteEtiquetas(3);
      for (final c in codigos) {
        expect(c, matches(RegExp(r'^PRD-\d{6}$')), reason: 'codigo invalido: $c');
      }
      expect(codigos.first, 'PRD-000001');
    });

    test('persiste as etiquetas no banco', () async {
      final codigos = await db.gerarLoteEtiquetas(4);
      final salvas = await db.select(db.etiquetas).get();
      expect(salvas.map((e) => e.codigo).toList(), codigos);
    });

    test('etiquetas novas nascem livres, sem produto vinculado', () async {
      await db.gerarLoteEtiquetas(3);
      final salvas = await db.select(db.etiquetas).get();
      expect(salvas.every((e) => e.vinculado == false), isTrue);
      expect(salvas.every((e) => e.produtoId == null), isTrue);
      expect(await db.listarEtiquetasLivres(), hasLength(3));
    });

    test('o segundo lote continua a numeracao, nao reinicia', () async {
      final primeiro = await db.gerarLoteEtiquetas(3);
      final segundo = await db.gerarLoteEtiquetas(2);

      expect(primeiro, ['PRD-000001', 'PRD-000002', 'PRD-000003']);
      expect(segundo, ['PRD-000004', 'PRD-000005']);
      expect(primeiro.toSet().intersection(segundo.toSet()), isEmpty);
    });

    test('quantidade zero devolve lista vazia e nao grava nada', () async {
      expect(await db.gerarLoteEtiquetas(0), isEmpty);
      expect(await db.select(db.etiquetas).get(), isEmpty);
    });

    test('continua a partir do maior numero ja existente no banco', () async {
      await inserirEtiquetaManual('PRD-000010');
      expect(await db.gerarLoteEtiquetas(2), ['PRD-000011', 'PRD-000012']);
    });

    test('ignora etiquetas de sufixo nao numerico ao calcular o proximo',
        () async {
      // Um codigo fora do padrao nao pode zerar a contagem: se zerasse, o lote
      // seguinte tentaria regravar PRD-000001 e violaria a constraint UNIQUE.
      await inserirEtiquetaManual('PRD-000007');
      await inserirEtiquetaManual('LEGADO-ABC');

      final codigos = await db.gerarLoteEtiquetas(2);
      expect(codigos, ['PRD-000008', 'PRD-000009']);
    });

    test('dois lotes simultaneos nao colidem', () async {
      // A leitura do maior numero e a gravacao do lote tem que ser atomicas.
      // Sem transacao, as duas chamadas leem o mesmo maximo, geram os mesmos
      // codigos e a segunda viola a constraint UNIQUE.
      final lotes = await Future.wait([
        db.gerarLoteEtiquetas(5),
        db.gerarLoteEtiquetas(5),
      ]);

      expect({...lotes[0], ...lotes[1]}, hasLength(10));
      expect(await db.select(db.etiquetas).get(), hasLength(10));
    });
  });
}
