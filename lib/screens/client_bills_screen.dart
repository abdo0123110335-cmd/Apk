import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/bill_of_lading.dart';
import '../services/database_service.dart';
import 'invoice_detail_screen.dart';

/// يعرض كل بوالص الشحن (البوالص) الخاصة بعميل واحد. الضغط على بوليصة يفتح
/// فاتورتها الموحّدة مع كل المستندات والرسوم والدفعات المرتبطة بها.
class ClientBillsScreen extends StatefulWidget {
  final Client client;
  const ClientBillsScreen({super.key, required this.client});

  @override
  State<ClientBillsScreen> createState() => _ClientBillsScreenState();
}

class _ClientBillsScreenState extends State<ClientBillsScreen> {
  bool isLoading = true;
  List<BillOfLading> bills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.instance.getBillOfLadingsForClient(widget.client.id);
    if (!mounted) return;
    setState(() {
      bills = list;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ملف العميل: ${widget.client.name}')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : bills.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'لا توجد بوالص مسجلة لهذا العميل بعد.\nستظهر هنا كل بوليصة بعد تصوير أول مستند لها.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: bills.length,
                    itemBuilder: (context, index) {
                      final bill = bills[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF003366),
                            child: Icon(Icons.folder, color: Colors.white),
                          ),
                          title: Text('بوليصة رقم: ${bill.billNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            [
                              if (bill.vesselName.isNotEmpty) bill.vesselName,
                              if (bill.containerCount > 0) '${bill.containerCount} حاوية',
                              bill.date,
                            ].join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => InvoiceDetailScreen(billOfLadingId: bill.id)),
                            );
                            _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
