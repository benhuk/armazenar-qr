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
      body: FutureBuilder<List<MovimentacaoComProduto>>(
        future: db.listarMovimentacoesDetalhadas(),
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
              final detalhe = movimentacoes[index];
              final m = detalhe.movimentacao;
              final sinal = m.tipo == 'saida' ? '-' : '+';
              return ListTile(
                leading: Icon(
                  m.tipo == 'saida'
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                ),
                title: Text('$sinal${m.quantidade} — ${detalhe.nomeProduto}'),
                subtitle: Text(_quando(m.data) +
                    (m.observacao == null ? '' : ' · ${m.observacao}')),
              );
            },
          );
        },
      ),
    );
  }
}

/// Data legível, sem depender do pacote intl.
String _quando(DateTime d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
}
