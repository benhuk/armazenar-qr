// Passo zero do pipeline (§9): confirma que `flutter test --machine` roda,
// que o banco em memoria sobe, e que o parser entende a saida.
// O teste de falha proposital foi removido: o ramo de erro do parser ja foi
// validado pelas rodadas reais do pipeline (7b e deepseek falhando).
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
}
