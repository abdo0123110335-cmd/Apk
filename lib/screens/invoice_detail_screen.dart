import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:printing/printing.dart';
import '../models/bill_of_lading.dart';
import '../models/clearance_invoice.dart';
import '../models/shipment_document.dart';
import '../models/payment.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';

/// شاشة الفاتورة الموحّدة الخاصة ببوليصة واحدة (داخل ملف عميل واحد).
/// تعرض: كل المستندات المحفوظة لهذه البوليصة، بنود الفاتورة القابلة للتعديل،
/// إمكانية إضافة أتعاب الكشف أو أي رسوم أخرى، إمكانية إضافة دفعات تُخصم من
/// المبلغ المطلوب، وإصدار الفاتورة النهائية كـ PDF.
class InvoiceDetailScreen extends StatefulWidget {
  final String billOfLadingId;
  const InvoiceDetailScreen({super.key, required this.billOfLadingId});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  bool isLoading = true;
  BillOfLading? bol;
  ClearanceInvoice? invoice;
  List<ShipmentDocument> documents = [];
  List<Payment> payments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    final loadedBol = await DatabaseService.instance.getBillOfLadingById(widget.billOfLadingId);
    if (loadedBol == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }
    final loadedInvoice = await DatabaseService.instance.getOrCreateInvoiceForBillOfLading(
      widget.billOfLadingId,
      clientId: loadedBol.clientId,
      clientName: loadedBol.clientName,
      billOfLading: loadedBol.billNumber,
      vesselName: loadedBol.vesselName,
      containerCount: loadedBol.containerCount,
    );
    final docs = await DatabaseService.instance.getDocumentsForBillOfLading(widget.billOfLadingId);
    final pays = await DatabaseService.instance.getPaymentsForBillOfLading(widget.billOfLadingId);
    if (!mounted) return;
    setState(() {
      bol = loadedBol;
      invoice = loadedInvoice;
      documents = docs;
      payments = pays;
      isLoading = false;
    });
  }

  double get _paymentsSum => payments.fold<double>(0, (s, p) => s + p.amount);

  Future<void> _persistInvoice() async {
    if (invoice == null) return;
    invoice!.recomputeCategoryTotals();
    await DatabaseService.instance.saveInvoiceWithItems(invoice!);
  }

  // ---------------- بنود الفاتورة ----------------

  Future<void> _showItemDialog({InvoiceItem? existing, String? defaultCategory}) async {
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final amountCtrl = TextEditingController(text: existing != null ? existing.amount.toStringAsFixed(2) : '');
    String category = existing?.category ?? defaultCategory ?? ItemCategory.fee;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'إضافة بند' : 'تعديل البند'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'البيان', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'الفئة', border: OutlineInputBorder()),
                items: ItemCategory.all
                    .map((c) => DropdownMenuItem(value: c, child: Text(ItemCategory.label(c))))
                    .toList(),
                onChanged: (v) => setDialogState(() => category = v ?? category),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final desc = descCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (desc.isEmpty || amount <= 0) {
      _showSnack('أدخل بياناً ومبلغاً صحيحين');
      return;
    }

    setState(() {
      if (existing != null) {
        existing.description = desc;
        existing.amount = amount;
        existing.category = category;
      } else {
        invoice!.items.add(InvoiceItem(description: desc, amount: amount, category: category));
      }
    });
    await _persistInvoice();
  }

  Future<void> _quickAddFee() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'أتعاب الكشف');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة أتعاب الكشف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'البيان', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (result != true) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      _showSnack('أدخل مبلغاً صحيحاً');
      return;
    }
    setState(() {
      invoice!.items.add(InvoiceItem(
        description: noteCtrl.text.trim().isEmpty ? 'أتعاب الكشف' : noteCtrl.text.trim(),
        amount: amount,
        category: ItemCategory.fee,
      ));
    });
    await _persistInvoice();
  }

  Future<void> _deleteItem(InvoiceItem item) async {
    setState(() => invoice!.items.remove(item));
    await _persistInvoice();
  }

  // ---------------- الدفعات ----------------

  Future<void> _addPayment() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة دفعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ المدفوع', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != true) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      _showSnack('أدخل مبلغاً صحيحاً');
      return;
    }
    final payment = Payment(
      id: const Uuid().v4(),
      billOfLadingId: widget.billOfLadingId,
      clientId: bol?.clientId ?? '',
      amount: amount,
      note: noteCtrl.text.trim(),
      date: DateFormat('yyyy/MM/dd').format(DateTime.now()),
    );
    await DatabaseService.instance.insertPayment(payment);
    if (!mounted) return;
    setState(() => payments.add(payment));
  }

  Future<void> _deletePayment(Payment payment) async {
    await DatabaseService.instance.deletePayment(payment.id);
    if (!mounted) return;
    setState(() => payments.remove(payment));
  }

  // ---------------- المستندات ----------------

  void _viewImage(ShipmentDocument doc) {
    final file = File(doc.imagePath);
    if (!file.existsSync()) {
      _showSnack('تعذر العثور على الصورة، ربما تم نقلها أو حذفها');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(file, fit: BoxFit.contain),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- الفاتورة النهائية ----------------

  Future<void> _issueFinalInvoice() async {
    if (invoice == null) return;
    final bytes = await PDFService.generateInvoicePDF(invoice!, payments: payments, isFinal: true);
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (bol == null || invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الفاتورة')),
        body: const Center(child: Text('تعذر العثور على بيانات هذه البوليصة')),
      );
    }

    final b = bol!;
    final inv = invoice!;
    final net = inv.netPayableAfterPayments(_paymentsSum);

    final docsByType = <String, List<ShipmentDocument>>{};
    for (final d in documents) {
      docsByType.putIfAbsent(d.docType, () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(title: Text('بوليصة رقم: ${b.billNumber}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              color: const Color(0xFF003366),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.clientName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (b.vesselName.isNotEmpty) 'الباخرة: ${b.vesselName}',
                        if (b.containerCount > 0) '${b.containerCount} حاوية',
                        'التاريخ: ${b.date}',
                      ].join(' • '),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ---- المستندات المحفوظة ----
            if (docsByType.isNotEmpty) ...[
              const Text('المستندات المحفوظة:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366))),
              const SizedBox(height: 8),
              ...docsByType.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DocType.shortTitle(entry.key), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: entry.value.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final d = entry.value[i];
                              final file = File(d.imagePath);
                              return GestureDetector(
                                onTap: () => _viewImage(d),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: file.existsSync()
                                      ? Image.file(file, width: 80, height: 80, fit: BoxFit.cover)
                                      : Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey.shade300,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: 28),
            ],

            // ---- بنود الفاتورة ----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('بنود الفاتورة:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _quickAddFee,
                      icon: const Icon(Icons.assignment_ind, size: 18),
                      label: const Text('أتعاب الكشف'),
                    ),
                    TextButton.icon(
                      onPressed: () => _showItemDialog(),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('إضافة بند'),
                    ),
                  ],
                ),
              ],
            ),
            if (inv.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('لا توجد بنود بعد.', style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              ...inv.items.map((item) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(item.description),
                      subtitle: Text(ItemCategory.label(item.category), style: const TextStyle(fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${item.amount.toStringAsFixed(2)} SDG', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                            onPressed: () => _showItemDialog(existing: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            onPressed: () => _deleteItem(item),
                          ),
                        ],
                      ),
                    ),
                  )),

            const Divider(height: 28),

            // ---- الدفعات ----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المدفوعات:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                TextButton.icon(
                  onPressed: _addPayment,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('إضافة دفعة'),
                ),
              ],
            ),
            if (payments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('لا توجد دفعات مسجلة بعد.', style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              ...payments.map((p) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: Colors.green.shade50,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                      title: Text('${p.amount.toStringAsFixed(2)} SDG'),
                      subtitle: Text('${p.date}${p.note.isNotEmpty ? ' • ${p.note}' : ''}', style: const TextStyle(fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        onPressed: () => _deletePayment(p),
                      ),
                    ),
                  )),

            const SizedBox(height: 20),

            // ---- الإجماليات ----
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _totalsRow('إجمالي المصاريف:', inv.grandTotal),
                  if (inv.advancePayment > 0) ...[
                    const Divider(),
                    _totalsRow('خصم مقدم سابق:', -inv.advancePayment, color: Colors.red),
                  ],
                  if (_paymentsSum > 0) ...[
                    const Divider(),
                    _totalsRow('إجمالي الدفعات المسددة:', -_paymentsSum, color: Colors.red),
                  ],
                  const Divider(),
                  _totalsRow('الصافي المطلوب سداده:', net, bold: true, color: const Color(0xFF003366)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0099CC),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text('إصدار الفاتورة النهائية', style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: _issueFinalInvoice,
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(String label, double value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 15 : 13, color: color)),
        Text(
          '${value.toStringAsFixed(2)} SDG',
          style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 15 : 13, color: color),
        ),
      ],
    );
  }
}
