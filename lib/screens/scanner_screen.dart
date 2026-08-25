import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

// Permissão de câmera: verificado no aparelho — o mobile_scanner já mostra o
// diálogo do sistema ao abrir esta tela, não precisa de permission_handler.

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processando = false;
  bool _lanterna = false;
  String? _ultimoCodigo;
  DateTime? _ultimaLeitura;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _aoDetectar(BarcodeCapture capture) async {
    if (_processando) return;
    final codigo = capture.barcodes.first.rawValue;
    if (codigo == null) return;

    // O scanner le em fluxo continuo: depois de confirmar, o mesmo QR ainda
    // esta na frente da camera e seria relido no ato. Ignora repeticao do
    // mesmo codigo por alguns segundos — tempo de tirar a etiqueta do quadro.
    final agora = DateTime.now();
    if (codigo == _ultimoCodigo &&
        _ultimaLeitura != null &&
        agora.difference(_ultimaLeitura!) < const Duration(seconds: 3)) {
      return;
    }
    _ultimoCodigo = codigo;
    _ultimaLeitura = agora;

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

    // recomeca a contagem a partir do fim do processamento, nao do inicio
    _ultimaLeitura = DateTime.now();
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
      appBar: AppBar(
        title: const Text('Escanear'),
        actions: [
          // Etiqueta em prateleira costuma estar na sombra.
          IconButton(
            tooltip: _lanterna ? 'Desligar lanterna' : 'Ligar lanterna',
            icon: Icon(_lanterna ? Icons.flashlight_on : Icons.flashlight_off),
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) setState(() => _lanterna = !_lanterna);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _aoDetectar),
          // Sem moldura nem instrução, a tela fica só preta e parece travada —
          // não existe botão de disparo: a leitura é contínua.
          const _MiraDoScanner(),
          if (_processando)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Moldura de mira com a instrução de uso.
class _MiraDoScanner extends StatelessWidget {
  const _MiraDoScanner();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 24),
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xAA000000),
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Aponte para o QR da etiqueta',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
