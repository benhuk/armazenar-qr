import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../data/database.dart';

/// Exportar e restaurar o backup.
///
/// O app é 100% local: sem esta tela não existe forma de tirar os dados do
/// aparelho, e perder o celular perde tudo.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _ocupado = false;
  String? _ultimoArquivo;

  BackupService _servico() => BackupService(context.read<AppDatabase>());

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      final pasta = await getApplicationDocumentsDirectory();
      final arquivo = await _servico().exportarParaArquivo(pasta);

      if (!mounted) return;
      setState(() => _ultimoArquivo = arquivo.path);

      // Sem compartilhar, o arquivo fica no armazenamento privado do app e o
      // usuário não alcança — o backup não sairia do aparelho.
      await Share.shareXFiles(
        [XFile(arquivo.path)],
        text: 'Backup do Estoque QR',
      );
    } catch (e) {
      _avisar('Falha ao exportar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _restaurar() async {
    final caminho = await _perguntarCaminho();
    if (caminho == null || !mounted) return;

    final confirmado = await _confirmarSubstituicao();
    if (confirmado != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await _servico().importarDeArquivo(File(caminho));
      _avisar('Backup restaurado.');
    } on BackupInvalido catch (e) {
      _avisar(e.motivo);
    } catch (e) {
      _avisar('Falha ao restaurar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<String?> _perguntarCaminho() {
    final controller = TextEditingController(text: _ultimoArquivo ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar de'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Caminho do arquivo .json',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmarSubstituicao() => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Substituir tudo?'),
          content: const Text(
            'Restaurar apaga os produtos e movimentações que estão no '
            'aparelho e põe os do backup no lugar. Não dá pra desfazer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Substituir'),
            ),
          ],
        ),
      );

  void _avisar(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Os dados ficam só neste aparelho. Exporte de vez em quando '
              'e guarde o arquivo em outro lugar.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _ocupado ? null : _exportar,
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar e compartilhar'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _restaurar,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restaurar de um arquivo'),
            ),
            if (_ultimoArquivo != null) ...[
              const SizedBox(height: 24),
              Text('Último arquivo gerado:',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(
                _ultimoArquivo!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
