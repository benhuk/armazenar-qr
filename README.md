# Estoque QR — o app

A documentação completa (instalar, rodar, gerar APK, o que subir no GitHub)
está no [README da raiz do repositório](../README.md).

## Atalho

```bash
flutter pub get
flutter pub run build_runner build --force-jit   # gera database.g.dart
flutter run -d <device>
```

O `--force-jit` não é opcional: o `sqlite3` usa build hooks, que a compilação
AOT do build_runner não suporta.

## Testes

```bash
flutter test     # 100 testes
dart analyze
```

Os testes usam banco em memória (`AppDatabase.forTesting(NativeDatabase.memory())`),
sem tocar em disco nem no `path_provider`. Não há teste de widget: a lógica que
importa mora na camada de dados, e é lá que ela é verificada.

## Ao mexer no schema

1. Altere a tabela em `lib/data/database.dart`
2. Suba o `schemaVersion`
3. Acrescente o passo em `MigrationStrategy.onUpgrade`
4. Cubra o caminho novo em `test/migracao_test.dart`
5. Rode o `build_runner` de novo

A migração apaga e reescreve dados. O teste dela existe porque isso é
irreversível no aparelho de quem já usa o app.
