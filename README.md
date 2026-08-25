# Estoque QR

Estrutura inicial do app (o plano completo está em `plano.md`, na conversa).

## Rodar

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

O `build_runner` gera `lib/data/database.g.dart`, que ainda não existe —
sem esse passo o projeto não compila.

## O que já está pronto

- Schema do banco (Drift): `produtos`, `movimentacoes`, `etiquetas`
- Tela de Estoque — lista os produtos direto do banco (stream)
- Tela de Gerar etiquetas — gera os códigos e monta o PDF em grade pra
  imprimir (QR direto no PDF, sem imagem intermediária)
- Tela de Histórico — lista as movimentações
- Tela de Cadastro — formulário funcional, salva o produto
- Tela de Scanner — já lê o QR e busca o produto no banco

## O que falta (marcado com `// TODO` no código)

- No cadastro: vincular a uma etiqueta livre já impressa (ou gerar uma nova
  na hora)
- No scanner: modal pra confirmar a quantidade antes da baixa (hoje só
  identifica o produto)
- Na tela de etiquetas: tamanho/colunas configuráveis
- No histórico: mostrar o nome do produto em vez do id
- Backup: `lib/data/backup_service.dart` só exporta; falta importar e
  salvar/compartilhar o arquivo

## Permissões

Antes de rodar em Android/iOS, adicionar a permissão de câmera:

- **Android**: `<uses-permission android:name="android.permission.CAMERA"/>`
  em `android/app/src/main/AndroidManifest.xml`
- **iOS**: `NSCameraUsageDescription` em `ios/Runner/Info.plist`
