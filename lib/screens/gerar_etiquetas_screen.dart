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

  @override
  void dispose() {
    _quantidadeController.dispose();
    super.dispose();
  }

  Future<void> _gerarEImprimir() async {
    final quantidade = int.tryParse(_quantidadeController.text) ?? 0;
    if (quantidade <= 0) return;

    setState(() => _gerando = true);

    final db = context.read<AppDatabase>();
    final codigos = await db.gerarLoteEtiquetas(quantidade);

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
            TextField(
              controller: _quantidadeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade de etiquetas',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _gerando ? null : _gerarEImprimir,
              icon: const Icon(Icons.print),
              label: Text(_gerando ? 'Gerando...' : 'Gerar e imprimir'),
            ),
          ],
        ),
      ),
    );
  }
}
