import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/bill_of_lading.dart';
import '../models/shipment_document.dart';
import '../models/clearance_invoice.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';

class InvoiceArchiveScreen extends StatefulWidget {
  const InvoiceArchiveScreen({super.key});

  @override
  State<InvoiceArchiveScreen> createState() => _InvoiceArchiveScreenState();
}

class _InvoiceArchiveScreenState extends State<InvoiceArchiveScreen> {
  bool isLoading = true;
  List<BillOfLading> bills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseService.instance.getBillOfLadings();
    setState(() {
      bills = list;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أرشيف الفواتير والبوالص')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : bills.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'لا توجد فواتير محفوظة بعد.\nستظهر هنا كل بوليصة مع كل المستندات والفواتير المرتبطة بها بعد أول عملية مسح.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: bills.length,
                    itemBuilder: (context, index) => _BillOfLadingTile(bill: bills[index]),
                  ),
                ),
    );
  }
}

class _BillOfLadingTile extends StatefulWidget {
  final BillOfLading bill;
  const _BillOfLadingTile({required this.bill});

  @override
  State<_BillOfLadingTile> createState() => _BillOfLadingTileState();
}

class _BillOfLadingTileState extends State<_BillOfLadingTile> {
  List<ShipmentDocument>? documents;
  List<ClearanceInvoice>? invoices;

  Future<void> _loadDetails() async {
    if (documents != null) return;
    final docs = await DatabaseService.instance.getDocumentsForBillOfLading(widget.bill.id);
    final invs = await DatabaseService.instance.getInvoicesForBillOfLading(widget.bill.id);
    if (!mounted) return;
    setState(() {
      documents = docs;
      invoices = invs;
    });
  }

  Future<void> _reprint(ClearanceInvoice invoice) async {
    final bytes = await PDFService.generateInvoicePDF(invoice);
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        onExpansionChanged: (open) {
          if (open) _loadDetails();
        },
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF003366),
          child: Icon(Icons.directions_boat, color: Colors.white, size: 18),
        ),
        title: Text('بوليصة رقم: ${bill.billNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${bill.clientName} • ${bill.vesselName} • ${bill.containerCount} حاوية'),
        children: [
          if (documents == null)
            const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
          else ...[
            if (documents!.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Align(alignment: Alignment.centerRight, child: Text('المستندات المرفقة:')),
              ),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  itemCount: documents!.length,
                  itemBuilder: (context, i) {
                    final d = documents![i];
                    final file = File(d.imagePath);
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: file.existsSync()
                                ? Image.file(file, width: 70, height: 70, fit: BoxFit.cover)
                                : Container(
                                    width: 70,
                                    height: 70,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.broken_image),
                                  ),
                          ),
                          Text(DocType.shortTitle(d.docType), style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            if (invoices != null && invoices!.isNotEmpty) ...[
              const Divider(),
              ...invoices!.map((inv) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF003366)),
                    title: Text(
                      inv.docTypes.isNotEmpty ? DocType.shortTitle(inv.docTypes.first) : 'فاتورة',
                    ),
                    subtitle: Text('الصافي: ${inv.netPayable.toStringAsFixed(2)} SDG • ${inv.date}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.print),
                      onPressed: () => _reprint(inv),
                    ),
                  )),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
