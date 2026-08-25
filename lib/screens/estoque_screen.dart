import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

class EstoqueScreen extends StatefulWidget {
  const EstoqueScreen({super.key});

  @override
  State<EstoqueScreen> createState() => _EstoqueScreenState();
}

class _EstoqueScreenState extends State<EstoqueScreen> {
  final _buscaController = TextEditingController();
  String _termo = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou categoria',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _termo.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscaController.clear();
                          setState(() => _termo = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _termo = v),
            ),
          ),
        ),
      ),
      // A stream continua trazendo tudo; o filtro é aplicado sobre a lista,
      // pra busca não perder a atualização ao vivo do estoque.
      body: StreamBuilder<List<Produto>>(
        stream: db.watchProdutos(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todos = snapshot.data!;
          if (todos.isEmpty) {
            return const Center(
              child: Text('Nenhum produto cadastrado ainda.'),
            );
          }

          final produtos = db.filtrarProdutos(todos, _termo);
          if (produtos.isEmpty) {
            return Center(
              child: Text('Nada encontrado para "$_termo".'),
            );
          }

          return ListView.builder(
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              final p = produtos[index];
              return ListTile(
                title: Text(p.nome),
                subtitle: Text(p.categoria ?? 'Sem categoria'),
                trailing: Text('${p.quantidadeAtual} ${p.unidade}'),
              );
            },
          );
        },
      ),
    );
  }
}
