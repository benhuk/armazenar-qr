import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

/// Base das duas telas de geração.
///
/// A diferença entre elas é só quanto cada etiqueta vale: fixo em 1 (avulsa)
/// ou escolhido pelo usuário (caixa). O resto — escolher produto, ver o que já
/// existe, montar o PDF — é igual.
class GeradorDeEtiquetas extends StatefulWidget {
  const GeradorDeEtiquetas({
    super.key,
    required this.titulo,
    required this.explicacao,
    required this.unidadesPorEtiqueta,
    required this.sugerirPeloEstoque,
  });

  final String titulo;
  final String explicacao;

  /// Fixo (tela avulsa) ou nulo, quando o usuário escolhe (tela caixa).
  final int? unidadesPorEtiqueta;

  /// Se true, sugere a quantidade que falta pra cobrir o estoque.
  final bool sugerirPeloEstoque;

  @override
  State<GeradorDeEtiquetas> createState() => _GeradorDeEtiquetasState();
}

class _GeradorDeEtiquetasState extends State<GeradorDeEtiquetas> {
  final _quantidadeController = TextEditingController(text: '1');
  final _unidadesController = TextEditingController(text: '12');
  int? _produtoId;
  bool _gerando = false;
  ResumoEtiquetas? _resumo;
  int? _semEtiqueta;

  @override
  void dispose() {
    _quantidadeController.dispose();
    _unidadesController.dispose();
    super.dispose();
  }

  Future<void> _aoTrocarProduto(int? id) async {
    setState(() {
      _produtoId = id;
      _resumo = null;
      _semEtiqueta = null;
    });
    if (id == null) return;

    final db = context.read<AppDatabase>();
    final resumo = await db.resumoEtiquetas(id);
    final falta = await db.unidadesSemEtiqueta(id);
    if (!mounted) return;

    setState(() {
      _resumo = resumo;
      _semEtiqueta = falta;
      // Na tela avulsa, o número óbvio é o que falta cobrir.
      if (widget.sugerirPeloEstoque && falta > 0) {
        _quantidadeController.text = '$falta';
      }
    });
  }

  int get _unidades =>
      widget.unidadesPorEtiqueta ??
      (int.tryParse(_unidadesController.text) ?? 0);

  Future<void> _gerarEImprimir() async {
    final quantidade = int.tryParse(_quantidadeController.text) ?? 0;
    final produtoId = _produtoId;
    if (quantidade <= 0 || produtoId == null || _unidades <= 0) return;

    setState(() => _gerando = true);
    final db = context.read<AppDatabase>();

    final List<String> codigos;
    try {
      codigos = await db.gerarLoteEtiquetas(
        quantidade,
        produtoId,
        unidades: _unidades,
      );
    } on VinculoInvalido catch (e) {
      _falhar(e.motivo);
      return;
    } on MovimentacaoInvalida catch (e) {
      _falhar(e.motivo);
      return;
    }

    await Printing.layoutPdf(
      onLayout: (_) => _montarPdf(codigos, _unidades).save(),
    );

    if (mounted) setState(() => _gerando = false);
    await _aoTrocarProduto(produtoId); // atualiza o resumo
  }

  void _falhar(String motivo) {
    if (!mounted) return;
    setState(() => _gerando = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(motivo)));
  }

  pw.Document _montarPdf(List<String> codigos, int unidades) {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.GridView(
            crossAxisCount: 3,
            childAspectRatio: 1,
            children: [
              for (final codigo in codigos)
                pw.Column(
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
                    // Sem isso, etiqueta de caixa e avulsa ficam
                    // indistinguíveis no papel.
                    if (unidades > 1)
                      pw.Text('$unidades un.',
                          style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    final resumo = _resumo;
    final podeGerar = !_gerando && _produtoId != null && _unidades > 0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.explicacao,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
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
                    DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.nome}  (${p.quantidadeAtual} ${p.unidade})'),
                    ),
                ],
                onChanged: _aoTrocarProduto,
              );
            },
          ),
          if (resumo != null) ...[
            const SizedBox(height: 12),
            _QuadroResumo(resumo: resumo, semEtiqueta: _semEtiqueta ?? 0),
          ],
          const SizedBox(height: 16),
          if (widget.unidadesPorEtiqueta == null) ...[
            TextField(
              controller: _unidadesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Unidades por caixa',
                helperText: 'Quanto cada etiqueta dá baixa ao ser bipada',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _quantidadeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: widget.unidadesPorEtiqueta == null
                  ? 'Quantas caixas'
                  : 'Quantas etiquetas',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: podeGerar ? _gerarEImprimir : null,
            icon: const Icon(Icons.print),
            label: Text(_gerando ? 'Gerando...' : 'Gerar e imprimir'),
          ),
        ],
      ),
    );
  }
}

class _QuadroResumo extends StatelessWidget {
  const _QuadroResumo({required this.resumo, required this.semEtiqueta});

  final ResumoEtiquetas resumo;
  final int semEtiqueta;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _linha(context, 'Etiquetas disponíveis', '${resumo.disponiveis}'),
            _linha(context, 'Já bipadas', '${resumo.usadas}'),
            _linha(context, 'Unidades cobertas', '${resumo.unidadesCobertas}'),
            _linha(context, 'Estoque sem etiqueta', '$semEtiqueta',
                destaque: semEtiqueta > 0),
          ],
        ),
      ),
    );
  }

  Widget _linha(BuildContext context, String rotulo, String valor,
      {bool destaque = false}) {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: estilo),
          Text(
            valor,
            style: estilo?.copyWith(
              fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
