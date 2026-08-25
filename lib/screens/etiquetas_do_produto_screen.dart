import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

/// Lista as etiquetas de um produto, mostrando quais já foram bipadas.
///
/// O dado de consumo (`usadaEm`) já existia no banco, mas nenhuma tela o
/// mostrava — então não havia como saber quais etiquetas ainda valem.
class EtiquetasDoProdutoScreen extends StatefulWidget {
  const EtiquetasDoProdutoScreen({super.key});

  @override
  State<EtiquetasDoProdutoScreen> createState() =>
      _EtiquetasDoProdutoScreenState();
}

class _EtiquetasDoProdutoScreenState extends State<EtiquetasDoProdutoScreen> {
  int? _produtoId;
  List<Etiqueta>? _etiquetas;
  ResumoEtiquetas? _resumo;

  Future<void> _carregar(int? id) async {
    setState(() {
      _produtoId = id;
      _etiquetas = null;
      _resumo = null;
    });
    if (id == null) return;

    final db = context.read<AppDatabase>();
    final lista = await db.listarEtiquetasDoProduto(id);
    final resumo = await db.resumoEtiquetas(id);
    if (!mounted) return;
    setState(() {
      _etiquetas = lista;
      _resumo = resumo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final etiquetas = _etiquetas;
    final resumo = _resumo;

    return Scaffold(
      appBar: AppBar(title: const Text('Etiquetas do produto')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<List<Produto>>(
              stream: context.read<AppDatabase>().watchProdutos(),
              builder: (context, snapshot) {
                final produtos = snapshot.data ?? const <Produto>[];
                if (produtos.isEmpty) {
                  return const Text('Nenhum produto cadastrado ainda.');
                }
                return DropdownButtonFormField<int>(
                  initialValue: _produtoId,
                  decoration: const InputDecoration(labelText: 'Produto'),
                  items: [
                    for (final p in produtos)
                      DropdownMenuItem(value: p.id, child: Text(p.nome)),
                  ],
                  onChanged: _carregar,
                );
              },
            ),
          ),
          if (resumo != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${resumo.disponiveis} disponíveis · ${resumo.usadas} usadas · '
                '${resumo.unidadesCobertas} unidades cobertas',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const Divider(height: 24),
          Expanded(
            child: _produtoId == null
                ? const Center(child: Text('Escolha um produto.'))
                : etiquetas == null
                    ? const Center(child: CircularProgressIndicator())
                    : etiquetas.isEmpty
                        ? const Center(
                            child: Text('Esse produto ainda não tem etiqueta.'))
                        : ListView.builder(
                            itemCount: etiquetas.length,
                            itemBuilder: (context, i) =>
                                _LinhaEtiqueta(etiqueta: etiquetas[i]),
                          ),
          ),
        ],
      ),
    );
  }
}

class _LinhaEtiqueta extends StatelessWidget {
  const _LinhaEtiqueta({required this.etiqueta});

  final Etiqueta etiqueta;

  @override
  Widget build(BuildContext context) {
    final usada = etiqueta.usadaEm != null;
    return ListTile(
      leading: Icon(
        usada ? Icons.check_circle : Icons.qr_code_2,
        color: usada ? Colors.grey : Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        etiqueta.codigo,
        style: TextStyle(
          decoration: usada ? TextDecoration.lineThrough : null,
          color: usada ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        etiqueta.unidades == 1 ? '1 unidade' : '${etiqueta.unidades} unidades',
      ),
      trailing: Text(
        usada ? 'usada' : 'disponível',
        style: TextStyle(color: usada ? Colors.grey : Colors.green.shade700),
      ),
    );
  }
}
