// Especificacao do backup em ARQUIVO — Fase 1.
// O BackupService ja serializa, mas nenhuma tela o alcanca: hoje nao existe
// forma de tirar os dados do aparelho. Sem isso, perder o celular perde tudo.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:estoque_qr/data/backup_service.dart';
import 'package:estoque_qr/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BackupService backup;
  late Directory pasta;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backup = BackupService(db);
    pasta = await Directory.systemTemp.createTemp('estoque_qr_backup_test');
  });

  tearDown(() async {
    await db.close();
    if (pasta.existsSync()) pasta.deleteSync(recursive: true);
  });

  Future<int> criarProduto(String nome, {int estoque = 0}) => db.criarProduto(
        ProdutosCompanion.insert(
          nome: nome,
          quantidadeAtual: Value(estoque),
        ),
      );

  group('nomeDoArquivo', () {
    test('usa a data e a hora, com extensao .json', () {
      final nome = backup.nomeDoArquivo(DateTime(2026, 8, 25, 14, 7));
      expect(nome, 'estoque_qr_2026-08-25_1407.json');
    });

    test('preenche mes, dia, hora e minuto com dois digitos', () {
      final nome = backup.nomeDoArquivo(DateTime(2026, 1, 2, 3, 4));
      expect(nome, 'estoque_qr_2026-01-02_0304.json');
    });

    test('dois backups no mesmo minuto tem o mesmo nome', () {
      // Deliberado: sobrescrever o do mesmo minuto e melhor do que encher a
      // pasta de arquivos quase identicos.
      final quando = DateTime(2026, 8, 25, 14, 7, 30);
      final outro = DateTime(2026, 8, 25, 14, 7, 59);
      expect(backup.nomeDoArquivo(quando), backup.nomeDoArquivo(outro));
    });
  });

  group('exportarParaArquivo', () {
    test('cria o arquivo na pasta indicada', () async {
      await criarProduto('Parafuso', estoque: 4);

      final arquivo = await backup.exportarParaArquivo(pasta);

      expect(arquivo.existsSync(), isTrue);
      expect(arquivo.parent.path, pasta.path);
      expect(arquivo.path, endsWith('.json'));
    });

    test('o conteudo do arquivo e o mesmo JSON do exportarJson', () async {
      await criarProduto('Parafuso', estoque: 4);

      final arquivo = await backup.exportarParaArquivo(pasta);
      final dados = jsonDecode(await arquivo.readAsString()) as Map;

      expect(dados['versao'], BackupService.versaoSuportada);
      expect(dados['produtos'], hasLength(1));
    });

    test('funciona com o banco vazio', () async {
      final arquivo = await backup.exportarParaArquivo(pasta);
      final dados = jsonDecode(await arquivo.readAsString()) as Map;
      expect(dados['produtos'], isEmpty);
    });
  });

  group('importarDeArquivo', () {
    test('round-trip: exportar pra arquivo e importar de volta', () async {
      final id = await criarProduto('Parafuso', estoque: 10);
      await db.registrarMovimentacao(
          produtoId: id, tipo: 'saida', quantidade: 3);
      final arquivo = await backup.exportarParaArquivo(pasta);

      final outro = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(outro.close);
      await BackupService(outro).importarDeArquivo(arquivo);

      final produtos = await outro.listarProdutos();
      expect(produtos, hasLength(1));
      expect(produtos.single.nome, 'Parafuso');
      expect(produtos.single.quantidadeAtual, 7);
    });

    test('recusa arquivo que nao existe', () async {
      await expectLater(
        backup.importarDeArquivo(File('${pasta.path}/nao_existe.json')),
        throwsA(isA<BackupInvalido>()),
      );
    });

    test('recusa arquivo com conteudo invalido', () async {
      final ruim = File('${pasta.path}/ruim.json')
        ..writeAsStringSync('nao sou json');

      await expectLater(
        backup.importarDeArquivo(ruim),
        throwsA(isA<BackupInvalido>()),
      );
    });

    test('arquivo invalido nao altera o banco', () async {
      await criarProduto('Parafuso', estoque: 1);
      final ruim = File('${pasta.path}/ruim.json')
        ..writeAsStringSync('{"versao": 99}');

      await expectLater(
        backup.importarDeArquivo(ruim),
        throwsA(isA<BackupInvalido>()),
      );
      expect(await db.listarProdutos(), hasLength(1));
    });
  });
}
