import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// Os métodos moram em extensions, por assunto. Reexportadas aqui para que
// `import 'database.dart'` continue trazendo a API inteira — e para que cada
// arquivo fique pequeno o bastante para caber no contexto do agente local.
export 'backup_dao.dart';
export 'etiquetas_dao.dart';
export 'movimentacoes_dao.dart';
export 'produtos_dao.dart';

part 'database.g.dart';

/// Movimentação recusada: quantidade inválida, tipo desconhecido, produto
/// inexistente ou saída maior que o estoque disponível.
class MovimentacaoInvalida implements Exception {
  MovimentacaoInvalida(this.motivo);
  final String motivo;
  @override
  String toString() => 'MovimentacaoInvalida: $motivo';
}

/// Vínculo recusado: código inexistente, produto inexistente ou etiqueta que
/// já está vinculada a outro produto.
class VinculoInvalido implements Exception {
  VinculoInvalido(this.motivo);
  final String motivo;
  @override
  String toString() => 'VinculoInvalido: $motivo';
}

// ---------------------------------------------------------------------------
// Tabelas
// ---------------------------------------------------------------------------

@DataClassName('Produto')
class Produtos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nome => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get categoria => text().nullable()();
  IntColumn get quantidadeAtual => integer().withDefault(const Constant(0))();
  TextColumn get unidade => text().withDefault(const Constant('un'))();
  DateTimeColumn get criadoEm => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Movimentacao')
class Movimentacoes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get produtoId => integer().references(Produtos, #id)();
  TextColumn get tipo => text()(); // 'entrada' ou 'saida'
  IntColumn get quantidade => integer()();
  DateTimeColumn get data => dateTime().withDefault(currentDateAndTime)();
  TextColumn get observacao => text().nullable()();
}

@DataClassName('Etiqueta')
class Etiquetas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get codigo => text().unique()();
  // Etiqueta so existe atrelada a um produto: obrigatorio, nao anulavel.
  IntColumn get produtoId => integer().references(Produtos, #id)();
  DateTimeColumn get criadoEm => dateTime().withDefault(currentDateAndTime)();
  // Etiqueta vale por uma baixa so: aqui fica quando ela foi consumida.
  // Nulo = ainda disponivel.
  DateTimeColumn get usadaEm => dateTime().nullable()();
  // Quantas unidades esta etiqueta representa. 1 para item avulso; mais de 1
  // para caixa fechada. E a etiqueta que decide a baixa, nao quem escaneia.
  IntColumn get unidades => integer().withDefault(const Constant(1))();
}

/// Uma movimentação com o nome do produto resolvido, para o histórico.
class MovimentacaoComProduto {
  const MovimentacaoComProduto({
    required this.movimentacao,
    required this.nomeProduto,
  });

  final Movimentacao movimentacao;
  final String nomeProduto;
}

/// Quadro das etiquetas de um produto, para as telas de geração.
class ResumoEtiquetas {
  const ResumoEtiquetas({
    required this.disponiveis,
    required this.usadas,
    required this.unidadesCobertas,
  });

  /// Etiquetas geradas e ainda não consumidas.
  final int disponiveis;

  /// Etiquetas já bipadas.
  final int usadas;

  /// Soma de `unidades` das disponíveis — quanto do estoque elas cobrem.
  final int unidadesCobertas;
}

// ---------------------------------------------------------------------------
// Banco
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Produtos, Movimentacoes, Etiquetas])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'estoque_qr'));

  /// Construtor para testes: recebe um executor em memoria
  /// (`NativeDatabase.memory()`), sem tocar em disco nem no path_provider.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: etiqueta só existe atrelada a um produto. As livres
            // (produto_id NULL) perderam sentido e são descartadas — sem isso
            // a coluna não pode virar NOT NULL. A coluna `vinculado` sai
            // junto: com produto obrigatório, ela seria sempre true.
            await m.database
                .customStatement('DELETE FROM etiquetas WHERE produto_id IS NULL');
            // `usada_em` (v3) não existe na v1: entra como coluna nova aqui,
            // senão o TableMigration tenta copiá-la da tabela antiga. Ele usa
            // a definição ATUAL da tabela, não a da v2.
            await m.alterTable(
              TableMigration(
                etiquetas,
                newColumns: [etiquetas.usadaEm, etiquetas.unidades],
              ),
            );
          } else if (from < 3) {
            // v3: etiqueta passa a valer por uma baixa só. As que já existem
            // ficam com usada_em nulo, ou seja, continuam disponíveis.
            await m.addColumn(etiquetas, etiquetas.usadaEm);
          }
          if (from >= 2 && from < 4) {
            // v4: etiqueta passa a carregar quantas unidades vale. As antigas
            // valem 1, que é o default da coluna.
            await m.addColumn(etiquetas, etiquetas.unidades);
          }
        },
      );
}
