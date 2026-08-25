import 'database.dart';

/// Consultas e cadastro de produtos.
extension ProdutosDao on AppDatabase {
  // --- Produtos -------------------------------------------------------

  Future<List<Produto>> listarProdutos() => select(produtos).get();

  Stream<List<Produto>> watchProdutos() => select(produtos).watch();

  Future<int> criarProduto(ProdutosCompanion produto) =>
      into(produtos).insert(produto);

  /// Filtra [produtos] pelo [termo] digitado na busca.
  ///
  /// Função pura: a tela já recebe a lista pelo stream, aqui é só peneirar.
  /// Casa com pedaço do nome OU da categoria, ignorando maiúsculas e espaços
  /// nas pontas do termo. Termo vazio (ou só espaços) devolve a lista inteira.
  /// Produto sem categoria não pode quebrar a busca. A ordem original é
  /// preservada.
  List<Produto> filtrarProdutos(List<Produto> produtos, String termo) {
    final alvo = termo.trim().toLowerCase();
    if (alvo.isEmpty) return produtos;

    return produtos.where((produto) {
      final peloNome = produto.nome.toLowerCase().contains(alvo);
      final pelaCategoria =
          produto.categoria?.toLowerCase().contains(alvo) ?? false;
      return peloNome || pelaCategoria;
    }).toList();
  }
}
