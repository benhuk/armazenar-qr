import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

// Permissão de câmera: verificado no aparelho — o mobile_scanner já mostra o
// diálogo do sistema ao abrir esta tela, não precisa de permission_handler.

/// Resultado da última leitura, para mostrar na tela parada.
class _Leitura {
  const _Leitura({required this.ok, required this.mensagem, this.produto});

  final bool ok;
  final String mensagem;
  final Produto? produto;
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _lanterna = false;
  _Leitura? _leitura;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Cada etiqueta vale por uma unidade, então não há o que perguntar: lê,
  /// baixa 1 e PARA. Continuar lendo com o mesmo QR na frente da câmera era o
  /// que causava baixas repetidas.
  Future<void> _aoDetectar(BarcodeCapture capture) async {
    if (_leitura != null) return; // ja parou, aguardando "Escanear outra"
    final codigo = capture.barcodes.first.rawValue;
    if (codigo == null) return;

    await _controller.stop();
    if (!mounted) return;
    setState(() => _leitura =
        const _Leitura(ok: true, mensagem: 'Processando...'));

    final db = context.read<AppDatabase>();
    late final _Leitura resultado;
    try {
      final produto = await db.darBaixaPorCodigo(codigo, 1);
      resultado = _Leitura(
        ok: true,
        mensagem: 'Baixa de 1 registrada.',
        produto: produto,
      );
    } on MovimentacaoInvalida catch (e) {
      resultado = _Leitura(ok: false, mensagem: e.motivo);
    } on VinculoInvalido catch (e) {
      resultado = _Leitura(ok: false, mensagem: e.motivo);
    }

    if (mounted) setState(() => _leitura = resultado);
  }

  Future<void> _escanearOutra() async {
    setState(() => _leitura = null);
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final leitura = _leitura;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear'),
        actions: [
          // Etiqueta em prateleira costuma estar na sombra.
          if (leitura == null)
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
      body: leitura == null ? _camera() : _resultado(leitura),
    );
  }

  Widget _camera() => Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _aoDetectar),
          // Sem moldura nem instrução a tela fica só preta e parece travada —
          // não existe botão de disparo: a leitura é automática.
          const _MiraDoScanner(),
        ],
      );

  Widget _resultado(_Leitura leitura) {
    final cor = leitura.ok ? Colors.green.shade700 : Colors.red.shade700;
    final produto = leitura.produto;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            leitura.ok ? Icons.check_circle : Icons.error,
            size: 88,
            color: cor,
          ),
          const SizedBox(height: 24),
          if (produto != null) ...[
            Text(
              produto.nome,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Restam ${produto.quantidadeAtual} ${produto.unidade}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: cor),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            leitura.mensagem,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            onPressed: _escanearOutra,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear outra'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Concluir'),
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
