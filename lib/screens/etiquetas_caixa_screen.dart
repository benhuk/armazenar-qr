import 'package:flutter/material.dart';

import 'etiquetas_base.dart';

/// Tela B — uma etiqueta por caixa fechada.
///
/// A etiqueta vale N unidades, definido aqui. Bipar dá baixa das N de uma vez,
/// sem perguntar nada — é a etiqueta que carrega o número.
class EtiquetasCaixaScreen extends StatelessWidget {
  const EtiquetasCaixaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GeradorDeEtiquetas(
      titulo: 'Etiquetas por caixa',
      explicacao:
          'Cada etiqueta vale a quantidade da caixa. Ao bipar, sai tudo de uma vez.',
      unidadesPorEtiqueta: null, // o usuario escolhe
      sugerirPeloEstoque: false,
    );
  }
}
