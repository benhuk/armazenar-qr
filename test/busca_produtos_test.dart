// Especificacao do filtro da tela de estoque — Fase 1.
// Funcao PURA, sem Drift: a tela ja recebe a lista pelo stream e so precisa
// filtrar. Assim a busca fica testavel sem banco.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<Produto> criar(String nome, {String? categoria}) async {
    final id = await db.criarProduto(ProdutosCompanion.insert(
      nome: nome,
      categoria: Value(categoria),
    ));
    return (db.select(db.produtos)..where((p) => p.id.equals(id))).getSingle();
  }

  group('filtrarProdutos', () {
    test('termo vazio devolve tudo', () async {
      final lista = [await criar('Parafuso'), await criar('Prego')];
      expect(db.filtrarProdutos(lista, ''), hasLength(2));
    });

    test('so espacos tambem devolve tudo', () async {
      final lista = [await criar('Parafuso')];
      expect(db.filtrarProdutos(lista, '   '), hasLength(1));
    });

    test('acha por pedaco do nome', () async {
      final lista = [await criar('Parafuso'), await criar('Prego')];
      final achados = db.filtrarProdutos(lista, 'araf');
      expect(achados.map((p) => p.nome), ['Parafuso']);
    });

    test('ignora maiuscula e minuscula', () async {
      final lista = [await criar('Parafuso')];
      expect(db.filtrarProdutos(lista, 'PARAFUSO'), hasLength(1));
      expect(db.filtrarProdutos(lista, 'parafuso'), hasLength(1));
    });

    test('acha por categoria', () async {
      final lista = [
        await criar('Parafuso', categoria: 'Fixacao'),
        await criar('Fita', categoria: 'Adesivos'),
      ];
      final achados = db.filtrarProdutos(lista, 'fixa');
      expect(achados.map((p) => p.nome), ['Parafuso']);
    });

    test('produto sem categoria nao quebra a busca', () async {
      final lista = [await criar('Parafuso')];
      expect(db.filtrarProdutos(lista, 'qualquer'), isEmpty);
    });

    test('ignora espacos nas pontas do termo', () async {
      final lista = [await criar('Parafuso')];
      expect(db.filtrarProdutos(lista, '  parafuso  '), hasLength(1));
    });

    test('nada encontrado devolve lista vazia', () async {
      final lista = [await criar('Parafuso')];
      expect(db.filtrarProdutos(lista, 'martelo'), isEmpty);
    });

    test('preserva a ordem original', () async {
      final lista = [
        await criar('Parafuso A'),
        await criar('Prego'),
        await criar('Parafuso B'),
      ];
      final achados = db.filtrarProdutos(lista, 'parafuso');
      expect(achados.map((p) => p.nome), ['Parafuso A', 'Parafuso B']);
    });
  });
}
