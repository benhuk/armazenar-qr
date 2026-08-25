import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

class CadastroProdutoScreen extends StatefulWidget {
  const CadastroProdutoScreen({super.key});

  @override
  State<CadastroProdutoScreen> createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _quantidadeController = TextEditingController(text: '0');

  @override
  void dispose() {
    _nomeController.dispose();
    _categoriaController.dispose();
    _quantidadeController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final db = context.read<AppDatabase>();
    final id = await db.criarProduto(
      ProdutosCompanion.insert(
        nome: _nomeController.text,
        categoria: Value(_categoriaController.text),
        quantidadeAtual: Value(int.tryParse(_quantidadeController.text) ?? 0),
      ),
    );

    // TODO: vincular a uma etiqueta livre (db.listarEtiquetasLivres() +
    // db.vincularEtiqueta(codigo, id)) ou gerar uma etiqueta nova aqui.

    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastrar produto')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoriaController,
              decoration: const InputDecoration(labelText: 'Categoria'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantidadeController,
              decoration:
                  const InputDecoration(labelText: 'Quantidade inicial'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            // TODO: seletor de etiqueta livre / botão "gerar etiqueta agora"
            const SizedBox(height: 24),
            FilledButton(onPressed: _salvar, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}
