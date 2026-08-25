import 'package:flutter/material.dart';

import 'etiquetas_base.dart';

/// Tela A — uma etiqueta por unidade.
///
/// Cada QR vale 1: é o caso do item que sai avulso da prateleira. A tela
/// sugere gerar exatamente o que falta pra cobrir o estoque.
class EtiquetasAvulsasScreen extends StatelessWidget {
  const EtiquetasAvulsasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GeradorDeEtiquetas(
      titulo: 'Etiquetas por unidade',
      explicacao: 'Cada etiqueta vale 1 unidade. Ao bipar, sai 1 do estoque.',
      unidadesPorEtiqueta: 1,
      sugerirPeloEstoque: true,
    );
  }
}
