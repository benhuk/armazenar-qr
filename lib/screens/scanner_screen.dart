import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

// TODO: pedir permissão de câmera explicitamente com permission_handler
// antes de abrir esta tela (o mobile_scanner já pede, mas um fluxo próprio
// permite mostrar uma mensagem melhor se for negada).

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _aoDetectar(BarcodeCapture capture) async {
    if (_processando) return;
    final codigo = capture.barcodes.first.rawValue;
    if (codigo == null) return;

    setState(() => _processando = true);
    final db = context.read<AppDatabase>();
    final produto = await db.buscarProdutoPorCodigo(codigo);

    if (!mounted) return;

    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código não encontrado.')),
      );
    } else {
      final quantidade = await _perguntarQuantidade(produto);
      if (quantidade != null && mounted) {
        await _darBaixa(db, codigo, quantidade);
      }
    }

    if (mounted) setState(() => _processando = false);
  }

  /// Modal de confirmação: mostra o produto e o estoque atual, e deixa ajustar
  /// a quantidade. Padrão 1, que é o caso comum de bipar item a item.
  Future<int?> _perguntarQuantidade(Produto produto) {
    final controller = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(produto.nome),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Em estoque: ${produto.quantidadeAtual} ${produto.unidade}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dar baixa de'),
              onSubmitted: (v) =>
                  Navigator.pop(dialogContext, int.tryParse(v)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _darBaixa(AppDatabase db, String codigo, int quantidade) async {
    final mensagem = await () async {
      try {
        final atualizado = await db.darBaixaPorCodigo(codigo, quantidade);
        return 'Baixa de $quantidade em ${atualizado.nome}. '
            'Restam ${atualizado.quantidadeAtual} ${atualizado.unidade}.';
      } on MovimentacaoInvalida catch (e) {
        return e.motivo;
      } on VinculoInvalido catch (e) {
        return e.motivo;
      }
    }();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear')),
      body: MobileScanner(
        controller: _controller,
        onDetect: _aoDetectar,
      ),
    );
  }
}
