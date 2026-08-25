import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/database.dart';
import 'screens/backup_screen.dart';
import 'screens/cadastro_produto_screen.dart';
import 'screens/estoque_screen.dart';
import 'screens/etiquetas_avulsas_screen.dart';
import 'screens/etiquetas_caixa_screen.dart';
import 'screens/historico_screen.dart';
import 'screens/scanner_screen.dart';

void main() {
  runApp(const EstoqueApp());
}

class EstoqueApp extends StatelessWidget {
  const EstoqueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<AppDatabase>(
      create: (_) => AppDatabase(),
      dispose: (_, db) => db.close(),
      child: MaterialApp(
        title: 'Estoque QR',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estoque QR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MenuCard(
            icon: Icons.inventory_2_outlined,
            titulo: 'Estoque',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EstoqueScreen()),
            ),
          ),
          _MenuCard(
            icon: Icons.qr_code_scanner,
            titulo: 'Escanear / dar baixa',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScannerScreen()),
            ),
          ),
          _MenuCard(
            icon: Icons.add_box_outlined,
            titulo: 'Cadastrar produto',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CadastroProdutoScreen()),
            ),
          ),
          _MenuCard(
            icon: Icons.label_outline,
            titulo: 'Etiquetas por unidade',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const EtiquetasAvulsasScreen()),
            ),
          ),
          _MenuCard(
            icon: Icons.inventory_2_outlined,
            titulo: 'Etiquetas por caixa',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EtiquetasCaixaScreen()),
            ),
          ),
          _MenuCard(
            icon: Icons.history,
            titulo: 'Histórico',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoricoScreen()),
            ),
          ),
          _MenuCard(
            icon: Icons.backup_outlined,
            titulo: 'Backup',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.titulo,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(titulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
