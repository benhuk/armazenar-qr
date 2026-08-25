import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

class EstoqueScreen extends StatelessWidget {
  const EstoqueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('Estoque')),
      // TODO: busca por nome/categoria (TextField no AppBar filtrando a stream)
      body: StreamBuilder<List<Produto>>(
        stream: db.watchProdutos(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final produtos = snapshot.data!;
          if (produtos.isEmpty) {
            return const Center(
              child: Text('Nenhum produto cadastrado ainda.'),
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
