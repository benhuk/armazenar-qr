import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';

class HistoricoScreen extends StatelessWidget {
  const HistoricoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: FutureBuilder<List<Movimentacao>>(
        future: db.listarMovimentacoes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final movimentacoes = snapshot.data!;
          if (movimentacoes.isEmpty) {
            return const Center(child: Text('Nenhuma movimentação ainda.'));
          }
          return ListView.builder(
            itemCount: movimentacoes.length,
            itemBuilder: (context, index) {
              final m = movimentacoes[index];
              final sinal = m.tipo == 'saida' ? '-' : '+';
              return ListTile(
                leading: Icon(
                  m.tipo == 'saida'
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                ),
                // TODO: trocar "produto #id" pelo nome (join com produtos)
                title: Text('$sinal${m.quantidade} — produto #${m.produtoId}'),
                subtitle: Text(m.data.toString()),
              );
            },
          );
        },
      ),
    );
  }
}
