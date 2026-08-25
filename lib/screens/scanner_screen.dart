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
      // TODO: abrir um modal pra confirmar a quantidade (padrão 1,
      // editável) antes de chamar:
      // db.registrarMovimentacao(produtoId: produto.id, tipo: 'saida', quantidade: n);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Produto: ${produto.nome}')),
      );
    }

    setState(() => _processando = false);
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
