import 'package:flutter/material.dart';
import '../models/client.dart';
import '../services/database_service.dart';
import 'add_client_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Client> clients = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    final list = await DatabaseService.instance.getClients();
    setState(() {
      clients = list;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة العملاء'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF003366),
        child: const Icon(Icons.person_add, color: Colors.white),
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddClientScreen()),
          );
          if (res == true) _loadClients();
        },
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : clients.isEmpty
              ? const Center(child: Text('لا يوجد عملاء مضافين حالياً. اضغط + لإضافة عميل جديد.'))
              : ListView.builder(
                  itemCount: clients.length,
                  itemBuilder: (context, index) {
                    final c = clients[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF0099CC),
                          child: Icon(Icons.business, color: Colors.white),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('هاتف: ${c.phone} | الرقم الضريبي: ${c.taxNumber}'),
                        trailing: Text(
                          '${c.advanceBalance.toStringAsFixed(0)} SDG',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
