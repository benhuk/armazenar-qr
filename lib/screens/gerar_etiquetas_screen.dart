import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

class GerarEtiquetasScreen extends StatefulWidget {
  const GerarEtiquetasScreen({super.key});

  @override
  State<GerarEtiquetasScreen> createState() => _GerarEtiquetasScreenState();
}

class _GerarEtiquetasScreenState extends State<GerarEtiquetasScreen> {
  final _quantidadeController = TextEditingController(text: '20');
  bool _gerando = false;
  int? _produtoId;

  @override
  void dispose() {
    _quantidadeController.dispose();
    super.dispose();
  }

  Future<void> _gerarEImprimir() async {
    final quantidade = int.tryParse(_quantidadeController.text) ?? 0;
    final produtoId = _produtoId;
    if (quantidade <= 0 || produtoId == null) return;

    setState(() => _gerando = true);

    final db = context.read<AppDatabase>();
    final List<String> codigos;
    try {
      codigos = await db.gerarLoteEtiquetas(quantidade, produtoId);
    } on VinculoInvalido catch (e) {
      if (mounted) {
        setState(() => _gerando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.motivo)));
      }
      return;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        // TODO: layout configurável (colunas, tamanho da etiqueta em mm)
        build: (context) => [
          pw.GridView(
            crossAxisCount: 3,
            childAspectRatio: 1,
            children: codigos
                .map(
                  (codigo) => pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: codigo,
                        width: 80,
                        height: 80,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(codigo, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => doc.save());

    if (mounted) setState(() => _gerando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gerar etiquetas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Etiqueta só existe atrelada a um produto: sem produto escolhido,
            // não há o que gerar.
            StreamBuilder<List<Produto>>(
              stream: context.read<AppDatabase>().watchProdutos(),
              builder: (context, snapshot) {
                final produtos = snapshot.data ?? const <Produto>[];
                if (produtos.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Cadastre um produto antes de gerar etiquetas.'),
                  );
                }
                return DropdownButtonFormField<int>(
                  initialValue: _produtoId,
                  decoration: const InputDecoration(labelText: 'Produto'),
                  items: [
                    for (final p in produtos)
                      DropdownMenuItem(value: p.id, child: Text(p.nome)),
                  ],
                  onChanged: (v) => setState(() => _produtoId = v),
                );
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantidadeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade de etiquetas',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _gerando || _produtoId == null ? null : _gerarEImprimir,
              icon: const Icon(Icons.print),
              label: Text(_gerando ? 'Gerando...' : 'Gerar e imprimir'),
            ),
          ],
        ),
      ),
    );
  }
}
