// Passo zero do pipeline (§9): confirma que `flutter test --machine` roda,
// que o banco em memoria sobe, e que o parser entende a saida.
// Tem um teste que passa e um que falha de proposito, pra validar os dois ramos.
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('banco em memoria sobe e responde', () async {
    expect(await db.listarProdutos(), isEmpty);
  });

  test('FALHA_PROPOSITAL: valida o ramo de erro do parser', () {
    expect(1, 2, reason: 'este teste deve falhar — e esperado');
  });
}
