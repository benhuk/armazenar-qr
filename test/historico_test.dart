// Especificacao do historico com nome do produto — Fase 1.
// Hoje a tela mostra "produto #3"; precisa do nome. A juncao e feita em Dart,
// nao em SQL: sao poucas linhas e fica testavel sem depender de join do Drift.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> criar(String nome, {int estoque = 100}) => db.criarProduto(
        ProdutosCompanion.insert(
          nome: nome,
          quantidadeAtual: Value(estoque),
        ),
      );

  group('listarMovimentacoesDetalhadas', () {
    test('banco vazio devolve lista vazia', () async {
      expect(await db.listarMovimentacoesDetalhadas(), isEmpty);
    });

    test('traz o nome do produto junto da movimentacao', () async {
      final id = await criar('Parafuso');
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 3);

      final lista = await db.listarMovimentacoesDetalhadas();

      expect(lista, hasLength(1));
      expect(lista.single.nomeProduto, 'Parafuso');
      expect(lista.single.movimentacao.quantidade, 3);
      expect(lista.single.movimentacao.tipo, 'saida');
    });

    test('cada movimentacao recebe o nome do SEU produto', () async {
      final a = await criar('Parafuso');
      final b = await criar('Prego');
      await db.registrarMovimentacao(
          produtoId: a, tipo: 'saida', quantidade: 1);
      await db.registrarMovimentacao(
          produtoId: b, tipo: 'entrada', quantidade: 2);

      final lista = await db.listarMovimentacoesDetalhadas();
      final porNome = {
        for (final m in lista) m.nomeProduto: m.movimentacao.quantidade
      };

      expect(porNome, {'Parafuso': 1, 'Prego': 2});
    });

    test('filtra por produto quando pedido', () async {
      final a = await criar('Parafuso');
      final b = await criar('Prego');
      await db.registrarMovimentacao(
          produtoId: a, tipo: 'saida', quantidade: 1);
      await db.registrarMovimentacao(
          produtoId: b, tipo: 'saida', quantidade: 1);

      final lista = await db.listarMovimentacoesDetalhadas(produtoId: a);

      expect(lista, hasLength(1));
      expect(lista.single.nomeProduto, 'Parafuso');
    });

    test('mantem a ordem de listarMovimentacoes: mais recente primeiro',
        () async {
      final id = await criar('Parafuso');
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 1, observacao: 'primeira');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 1, observacao: 'segunda');

      final lista = await db.listarMovimentacoesDetalhadas();

      expect(lista.first.movimentacao.observacao, 'segunda');
      expect(lista.last.movimentacao.observacao, 'primeira');
    });
  });
}
