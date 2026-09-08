import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/clearance_invoice.dart';
import '../models/client.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import 'package:printing/printing.dart';

class ReviewInvoiceScreen extends StatefulWidget {
  final OCRResult ocrResult;
  final String docType;

  const ReviewInvoiceScreen({super.key, required this.ocrResult, required this.docType});

  @override
  State<ReviewInvoiceScreen> createState() => _ReviewInvoiceScreenState();
}

class _ReviewInvoiceScreenState extends State<ReviewInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController clientNameCtrl;
  late TextEditingController declarationCtrl;
  late TextEditingController vesselCtrl;
  late TextEditingController portFeesCtrl;
  late TextEditingController customsFeesCtrl;
  late TextEditingController agencyCtrl;
  late TextEditingController transportCtrl;
  late TextEditingController miscCtrl;
  late TextEditingController advanceCtrl;

  List<Client> availableClients = [];
  Client? selectedClient;

  @override
  void initState() {
    super.initState();
    clientNameCtrl = TextEditingController(text: widget.ocrResult.clientName);
    declarationCtrl = TextEditingController(text: widget.ocrResult.declarationNo);
    vesselCtrl = TextEditingController(text: widget.ocrResult.vesselName);

    portFeesCtrl = TextEditingController(text: widget.docType == 'ports' ? widget.ocrResult.totalAmount.toString() : '0.0');
    customsFeesCtrl = TextEditingController(text: widget.docType == 'customs' ? widget.ocrResult.totalAmount.toString() : '0.0');

    agencyCtrl = TextEditingController(text: '150000.0'); // أجور التخليص الافتراضية
    transportCtrl = TextEditingController(text: '0.0');
    miscCtrl = TextEditingController(text: '25000.0');
    advanceCtrl = TextEditingController(text: '0.0');

    _loadClients();
  }

  Future<void> _loadClients() async {
    final list = await DatabaseService.instance.getClients();
    setState(() {
      availableClients = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مراجعة وتعديل البيانات قبل الحفظ'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'بيانات الشحنة والعميل (تم القراءة تلقائياً):',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366)),
            ),
            const SizedBox(height: 10),

            // قائمة اختيار العميل المعتمد
            DropdownButtonFormField<Client>(
              decoration: const InputDecoration(
                labelText: 'ربط بطلب عميل مسجل في الدليل',
                border: OutlineInputBorder(),
              ),
              items: availableClients.map((c) {
                return DropdownMenuItem(value: c, child: Text(c.name));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    selectedClient = val;
                    clientNameCtrl.text = val.name;
                    advanceCtrl.text = val.advanceBalance.toString();
                  });
                }
              },
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: clientNameCtrl,
              decoration: const InputDecoration(labelText: 'اسم العميل / الشركة', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: declarationCtrl,
                    decoration: const InputDecoration(labelText: 'رقم الإقرار الجمركي', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: vesselCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الباخرة', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              'المبالغ والرسوم الحسابية (قابلة للتعديل):',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366)),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: portFeesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'رسوم هيئة الموانئ البحرية (SDG)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: customsFeesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الرسوم الجمركية - أسيكودا (SDG)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: agencyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'أجور التخليص والعمالة (SDG)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: transportCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'رسوم النولون والنقل (SDG)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: miscCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'نثريات وتدميغات ونقل مستندات (SDG)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: advanceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبالغ المدفوعة مقدماً من العميل (خصم)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.remove_circle_outline, color: Colors.red),
              ),
            ),
            const SizedBox(height: 25),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text('تأكيد وتوليد فاتورة الـ PDF', style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: () async {
                final invoice = ClearanceInvoice(
                  id: const Uuid().v4(),
                  clientId: selectedClient?.id ?? '',
                  clientName: clientNameCtrl.text,
                  declarationNo: declarationCtrl.text,
                  billOfLading: 'B/L-91743',
                  vesselName: vesselCtrl.text,
                  date: DateFormat('yyyy/MM/dd').format(DateTime.now()),
                  items: [],
                  portFeesTotal: double.tryParse(portFeesCtrl.text) ?? 0,
                  customsFeesTotal: double.tryParse(customsFeesCtrl.text) ?? 0,
                  agencyFee: double.tryParse(agencyCtrl.text) ?? 0,
                  transportFee: double.tryParse(transportCtrl.text) ?? 0,
                  miscFee: double.tryParse(miscCtrl.text) ?? 0,
                  advancePayment: double.tryParse(advanceCtrl.text) ?? 0,
                );

                final pdfBytes = await PDFService.generateInvoicePDF(invoice);

                if (mounted) {
                  await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
