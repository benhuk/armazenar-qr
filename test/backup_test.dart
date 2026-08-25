// Especificacao de BackupService — Fase 1.
// Serializacao pura, sem invariante estrutural: melhor candidato pro loop local.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:estoque_qr/data/backup_service.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BackupService backup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backup = BackupService(db);
  });
  tearDown(() async => db.close());

  Future<int> criarProduto(String nome, {int estoque = 0}) => db.criarProduto(
        ProdutosCompanion.insert(
          nome: nome,
          quantidadeAtual: Value(estoque),
        ),
      );

  group('exportarJson', () {
    test('exporta produtos e movimentacoes', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 3, observacao: 'venda');

      final dados = jsonDecode(await backup.exportarJson()) as Map;
      expect(dados['versao'], 1);
      expect(dados['produtos'], hasLength(1));
      expect(dados['movimentacoes'], hasLength(1));
    });

    test('banco vazio exporta listas vazias, nao falha', () async {
      final dados = jsonDecode(await backup.exportarJson()) as Map;
      expect(dados['produtos'], isEmpty);
      expect(dados['movimentacoes'], isEmpty);
    });
  });

  group('importarJson', () {
    test('round-trip: exportar e importar reconstroi o estado', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 3, observacao: 'venda');
      final json = await backup.exportarJson();

      // banco novo, vazio
      final outro = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(outro.close);
      await BackupService(outro).importarJson(json);

      final produtos = await outro.listarProdutos();
      expect(produtos, hasLength(1));
      expect(produtos.single.nome, 'Parafuso');
      expect(produtos.single.quantidadeAtual, 7);

      final movs = await outro.listarMovimentacoes();
      expect(movs, hasLength(1));
      expect(movs.single.tipo, 'saida');
      expect(movs.single.quantidade, 3);
      expect(movs.single.observacao, 'venda');
    });

    test('preserva o vinculo entre movimentacao e produto', () async {
      final a = await criarProduto('Parafuso', estoque: 5);
      final b = await criarProduto('Prego', estoque: 5);
      await db.registrarMovimentacao(
          produtoId: b, tipo: 'entrada', quantidade: 2);
      final json = await backup.exportarJson();

      final outro = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(outro.close);
      await BackupService(outro).importarJson(json);

      final produtos = await outro.listarProdutos();
      final prego = produtos.firstWhere((p) => p.nome == 'Prego');
      final movs = await outro.listarMovimentacoes();
      expect(movs.single.produtoId, prego.id,
          reason: 'a movimentacao tem que continuar apontando pro Prego');
      expect(a, isNot(b));
    });

    test('importar substitui o conteudo, nao duplica', () async {
      await criarProduto('Parafuso', estoque: 1);
      final json = await backup.exportarJson();

      await backup.importarJson(json);
      await backup.importarJson(json);

      expect(await db.listarProdutos(), hasLength(1));
    });

    test('recusa JSON malformado', () async {
      await expectLater(
        backup.importarJson('nao sou json'),
        throwsA(isA<BackupInvalido>()),
      );
    });

    test('recusa versao desconhecida', () async {
      final json = jsonEncode({'versao': 99, 'produtos': [], 'movimentacoes': []});
      await expectLater(
        backup.importarJson(json),
        throwsA(isA<BackupInvalido>()),
      );
    });

    test('importacao recusada nao altera o banco', () async {
      await criarProduto('Parafuso', estoque: 1);
      await expectLater(
        backup.importarJson('{"versao": 99}'),
        throwsA(isA<BackupInvalido>()),
      );
      expect(await db.listarProdutos(), hasLength(1));
    });
  });
}
