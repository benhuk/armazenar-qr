// A migracao v1 -> v2 APAGA dados: etiqueta sem produto deixa de existir.
// Isso e destrutivo e silencioso, entao precisa de teste — e a parte do schema
// que mais custa caro se estiver errada.
import 'package:drift/native.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Recria a tabela `etiquetas` no formato v1 (com `vinculado` e `produto_id`
/// anulavel) e marca o banco como schema 1.
void rebaixarParaV1(raw.Database db) {
  db.execute('DROP TABLE etiquetas;');
  db.execute('''
    CREATE TABLE etiquetas (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      codigo TEXT NOT NULL UNIQUE,
      vinculado INTEGER NOT NULL DEFAULT 0 CHECK (vinculado IN (0, 1)),
      produto_id INTEGER NULL REFERENCES produtos (id),
      criado_em INTEGER NOT NULL
    );
  ''');
  db.execute('PRAGMA user_version = 1;');
}

void main() {
  late raw.Database sqlite;

  setUp(() async {
    sqlite = raw.sqlite3.openInMemory();
    // deixa o drift criar o schema v2 (pega produtos/movimentacoes de graca),
    // depois rebaixa so a tabela que a migracao toca.
    final v2 = AppDatabase.forTesting(
      NativeDatabase.opened(sqlite, closeUnderlyingOnClose: false),
    );
    await v2.criarProduto(ProdutosCompanion.insert(nome: 'Parafuso'));
    await v2.close();
    rebaixarParaV1(sqlite);
  });

  tearDown(() => sqlite.close());

  Future<AppDatabase> abrirEMigrar() async {
    final db = AppDatabase.forTesting(
      NativeDatabase.opened(sqlite, closeUnderlyingOnClose: false),
    );
    await db.listarProdutos(); // primeira query dispara a migracao
    return db;
  }

  test('sobe o schemaVersion para o atual', () async {
    final db = await abrirEMigrar();
    addTearDown(db.close);
    expect(sqlite.select('PRAGMA user_version;').single.values.single,
        db.schemaVersion);
  });

  test('v1 ganha a coluna usada_em, nula (etiqueta ainda disponivel)', () async {
    // `usada_em` chegou na v3. Migrando direto da v1, ela nao pode ser copiada
    // da tabela antiga — tem que entrar como coluna nova.
    sqlite.execute(
      "INSERT INTO etiquetas (codigo, vinculado, produto_id, criado_em) "
      "VALUES ('PRD-000001', 1, 1, 0);",
    );

    final db = await abrirEMigrar();
    addTearDown(db.close);

    final etiqueta = await db.select(db.etiquetas).getSingle();
    expect(etiqueta.usadaEm, isNull);

    // e continua valendo por uma baixa
    await db.registrarMovimentacao(
        produtoId: 1, tipo: 'entrada', quantidade: 5);
    final produto = await db.darBaixaPorCodigo('PRD-000001', 1);
    expect(produto.quantidadeAtual, 4);

    // mas so por uma
    await expectLater(
      db.darBaixaPorCodigo('PRD-000001', 1),
      throwsA(isA<VinculoInvalido>()),
    );
  });

  test('preserva a etiqueta que ja tinha produto', () async {
    sqlite.execute(
      "INSERT INTO etiquetas (codigo, vinculado, produto_id, criado_em) "
      "VALUES ('PRD-000001', 1, 1, 0);",
    );

    final db = await abrirEMigrar();
    addTearDown(db.close);

    final etiquetas = await db.select(db.etiquetas).get();
    expect(etiquetas, hasLength(1));
    expect(etiquetas.single.codigo, 'PRD-000001');
    expect(etiquetas.single.produtoId, 1);
  });

  test('descarta a etiqueta livre, que perdeu sentido na v2', () async {
    sqlite.execute(
      "INSERT INTO etiquetas (codigo, vinculado, produto_id, criado_em) "
      "VALUES ('PRD-000001', 1, 1, 0), ('PRD-000002', 0, NULL, 0);",
    );

    final db = await abrirEMigrar();
    addTearDown(db.close);

    final codigos =
        (await db.select(db.etiquetas).get()).map((e) => e.codigo).toList();
    expect(codigos, ['PRD-000001'], reason: 'a livre nao pode sobreviver');
  });

  test('a coluna vinculado deixa de existir', () async {
    final db = await abrirEMigrar();
    addTearDown(db.close);

    final colunas = sqlite
        .select('PRAGMA table_info(etiquetas);')
        .map((l) => l['name'] as String)
        .toList();
    expect(colunas, isNot(contains('vinculado')));
    expect(colunas, contains('produto_id'));
  });

  test('depois de migrar, gerar etiqueta continua funcionando', () async {
    sqlite.execute(
      "INSERT INTO etiquetas (codigo, vinculado, produto_id, criado_em) "
      "VALUES ('PRD-000005', 1, 1, 0);",
    );

    final db = await abrirEMigrar();
    addTearDown(db.close);

    // a numeracao tem que continuar de onde o banco antigo parou
    expect(await db.gerarLoteEtiquetas(2, 1), ['PRD-000006', 'PRD-000007']);
  });
}
