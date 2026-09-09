import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/clearance_invoice.dart';
import '../models/client.dart';
import '../models/bill_of_lading.dart';
import '../models/shipment_document.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import 'package:printing/printing.dart';

/// صف بند واحد في الفاتورة (اسم البند + مبلغه) مع الـ controllers الخاصة به.
class _ItemRow {
  final TextEditingController descCtrl;
  final TextEditingController amountCtrl;
  _ItemRow({String desc = '', String amount = ''})
      : descCtrl = TextEditingController(text: desc),
        amountCtrl = TextEditingController(text: amount);

  void dispose() {
    descCtrl.dispose();
    amountCtrl.dispose();
  }
}

class ReviewInvoiceScreen extends StatefulWidget {
  final OCRResult ocrResult;
  final String docType;
  final List<File> imageFiles;

  const ReviewInvoiceScreen({
    super.key,
    required this.ocrResult,
    required this.docType,
    required this.imageFiles,
  });

  @override
  State<ReviewInvoiceScreen> createState() => _ReviewInvoiceScreenState();
}

class _ReviewInvoiceScreenState extends State<ReviewInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController clientNameCtrl;
  late TextEditingController declarationCtrl;
  late TextEditingController vesselCtrl;
  late TextEditingController billOfLadingCtrl;
  late TextEditingController containerCountCtrl;
  late TextEditingController agencyCtrl;
  late TextEditingController transportCtrl;
  late TextEditingController miscCtrl;
  late TextEditingController advanceCtrl;

  final List<_ItemRow> _items = [];
  String? _itemsError;

  List<Client> availableClients = [];
  Client? selectedClient;

  BillOfLading? matchedBOL;
  int previousInvoicesCount = 0;
  bool isChecking = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    clientNameCtrl = TextEditingController();
    declarationCtrl = TextEditingController(text: widget.ocrResult.declarationNo);
    vesselCtrl = TextEditingController(text: widget.ocrResult.vesselName);
    billOfLadingCtrl = TextEditingController(text: widget.ocrResult.billNo);
    containerCountCtrl = TextEditingController(text: '1');

    agencyCtrl = TextEditingController(text: '150000.0'); // أجور التخليص الافتراضية
    transportCtrl = TextEditingController(text: '0.0');
    miscCtrl = TextEditingController(text: '25000.0');
    advanceCtrl = TextEditingController(text: '0.0');

    // نضيف البنود المقترحة من قراءة الصورة الحقيقية (قابلة للتعديل أو الحذف)
    widget.ocrResult.items.forEach((desc, amount) {
      _items.add(_ItemRow(desc: desc, amount: amount.toStringAsFixed(2)));
    });
    if (widget.ocrResult.totalAmount > 0 && widget.ocrResult.items.isEmpty) {
      _items.add(_ItemRow(desc: 'إجمالي المستند', amount: widget.ocrResult.totalAmount.toStringAsFixed(2)));
    }

    _loadClients();
  }

  Future<void> _loadClients() async {
    final list = await DatabaseService.instance.getClients();
    setState(() => availableClients = list);
  }

  String get _effectiveClientId =>
      selectedClient?.id ?? 'adhoc-${clientNameCtrl.text.trim().toLowerCase()}';

  Future<void> _checkExistingBillOfLading() async {
    final billNo = billOfLadingCtrl.text.trim();
    if (billNo.isEmpty) {
      setState(() {
        matchedBOL = null;
        previousInvoicesCount = 0;
      });
      return;
    }
    setState(() => isChecking = true);
    final found = await DatabaseService.instance.findBillOfLading(billNo, _effectiveClientId);
    List<ClearanceInvoice> prevInvoices = [];
    if (found != null) {
      prevInvoices = await DatabaseService.instance.getInvoicesForBillOfLading(found.id);
    }
    if (!mounted) return;
    setState(() {
      matchedBOL = found;
      previousInvoicesCount = prevInvoices.length;
      isChecking = false;
      if (found != null) {
        if (vesselCtrl.text.trim().isEmpty) vesselCtrl.text = found.vesselName;
        if (found.containerCount > 0) containerCountCtrl.text = found.containerCount.toString();
      }
    });
  }

  void _addItemRow() {
    setState(() => _items.add(_ItemRow()));
  }

  void _removeItemRow(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double get _itemsTotal {
    double total = 0;
    for (final item in _items) {
      total += double.tryParse(item.amountCtrl.text.trim()) ?? 0;
    }
    return total;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final validItems = _items
        .where((it) =>
            it.descCtrl.text.trim().isNotEmpty && (double.tryParse(it.amountCtrl.text.trim()) ?? 0) > 0)
        .toList();

    if (validItems.isEmpty) {
      setState(() => _itemsError = 'أضف بنداً واحداً على الأقل باسم ومبلغ صحيحين قبل الحفظ');
      return;
    }
    setState(() => _itemsError = null);

    setState(() => isSaving = true);
    try {
      final now = DateFormat('yyyy/MM/dd').format(DateTime.now());
      final clientId = _effectiveClientId;
      final containerCount = int.tryParse(containerCountCtrl.text.trim()) ?? 0;
      final billNo = billOfLadingCtrl.text.trim();

      // إعادة التحقق من وجود بوليصة مطابقة قبل الحفظ مباشرة (احتياطاً)
      final existing = matchedBOL ?? await DatabaseService.instance.findBillOfLading(billNo, clientId);

      final bolId = existing?.id ?? const Uuid().v4();
      final bol = BillOfLading(
        id: bolId,
        billNumber: billNo,
        clientId: clientId,
        clientName: clientNameCtrl.text.trim(),
        vesselName: vesselCtrl.text.trim(),
        containerCount: containerCount,
        date: existing?.date ?? now,
      );
      await DatabaseService.instance.insertBillOfLading(bol);

      final categoryTotal = validItems.fold<double>(
        0, (sum, it) => sum + (double.tryParse(it.amountCtrl.text.trim()) ?? 0));

      // حفظ الصور بشكل دائم على الجهاز وربطها بنفس ملف البوليصة
      final savedPaths = await _persistImages(bolId);
      for (var i = 0; i < savedPaths.length; i++) {
        final doc = ShipmentDocument(
          id: const Uuid().v4(),
          billOfLadingId: bolId,
          docType: widget.docType,
          imagePath: savedPaths[i],
          amount: i == 0 ? categoryTotal : 0.0,
          description: savedPaths.length > 1 ? 'مستند ${i + 1} من ${savedPaths.length}' : '',
          date: now,
        );
        await DatabaseService.instance.insertShipmentDocument(doc);
      }

      final invoiceItems = validItems
          .map((it) => InvoiceItem(
                description: it.descCtrl.text.trim(),
                amount: double.tryParse(it.amountCtrl.text.trim()) ?? 0,
                category: widget.docType,
              ))
          .toList();

      final invoice = ClearanceInvoice(
        id: const Uuid().v4(),
        billOfLadingId: bolId,
        clientId: selectedClient?.id ?? '',
        clientName: clientNameCtrl.text.trim(),
        declarationNo: declarationCtrl.text.trim(),
        billOfLading: billNo,
        vesselName: vesselCtrl.text.trim(),
        containerCount: containerCount,
        date: now,
        docTypes: [widget.docType],
        items: invoiceItems,
        portFeesTotal: widget.docType == 'ports' ? categoryTotal : 0,
        customsFeesTotal: widget.docType == 'customs' ? categoryTotal : 0,
        storageFeesTotal: widget.docType == 'storage' ? categoryTotal : 0,
        permitFeesTotal: widget.docType == 'permit' ? categoryTotal : 0,
        agencyFee: double.tryParse(agencyCtrl.text) ?? 0,
        transportFee: double.tryParse(transportCtrl.text) ?? 0,
        miscFee: double.tryParse(miscCtrl.text) ?? 0,
        advancePayment: double.tryParse(advanceCtrl.text) ?? 0,
      );

      await DatabaseService.instance.saveInvoiceWithItems(invoice);

      final pdfBytes = await PDFService.generateInvoicePDF(invoice);

      if (!mounted) return;
      setState(() => isSaving = false);

      await Printing.layoutPdf(onLayout: (format) async => pdfBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الفاتورة والمستندات في الأرشيف بنجاح')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
      );
    }
  }

  Future<List<String>> _persistImages(String bolId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(docsDir.path, 'bol_documents', bolId));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final paths = <String>[];
    for (final file in widget.imageFiles) {
      final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
      final newPath = p.join(targetDir.path, '${widget.docType}_${const Uuid().v4()}$ext');
      final saved = await file.copy(newPath);
      paths.add(saved.path);
    }
    return paths;
  }

  String get _categoryLabel => DocType.label(widget.docType);

  @override
  void dispose() {
    clientNameCtrl.dispose();
    declarationCtrl.dispose();
    vesselCtrl.dispose();
    billOfLadingCtrl.dispose();
    containerCountCtrl.dispose();
    agencyCtrl.dispose();
    transportCtrl.dispose();
    miscCtrl.dispose();
    advanceCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
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
              'بيانات الشحنة والعميل:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366)),
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<Client>(
              decoration: const InputDecoration(
                labelText: 'ربط بعميل مسجل في الدليل',
                border: OutlineInputBorder(),
              ),
              items: availableClients.map((c) {
                return DropdownMenuItem(value: c, child: Text(c.name));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  selectedClient = val;
                  if (val != null) clientNameCtrl.text = val.name;
                });
                _checkExistingBillOfLading();
              },
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: clientNameCtrl,
              decoration: const InputDecoration(labelText: 'اسم العميل / الشركة', border: OutlineInputBorder()),
              validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب إدخال اسم العميل' : null,
              onEditingComplete: _checkExistingBillOfLading,
            ),
            const SizedBox(height: 10),

            // رقم البوليصة - إلزامي: يُقرأ تلقائياً إن وُجد بالصورة، وإلا يجب إدخاله يدوياً
            TextFormField(
              controller: billOfLadingCtrl,
              decoration: InputDecoration(
                labelText: 'رقم البوليصة (B/L) *',
                border: const OutlineInputBorder(),
                helperText: widget.ocrResult.billNo.isEmpty
                    ? 'لم يتم العثور على رقم البوليصة في الصورة - الرجاء إدخاله يدوياً'
                    : 'تم العثور على الرقم تلقائياً من الصورة - تحقق منه وعدّله عند الحاجة',
                suffixIcon: isChecking
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'رقم البوليصة مطلوب لحفظ وربط المستندات' : null,
              onEditingComplete: _checkExistingBillOfLading,
              onChanged: (_) {
                if (matchedBOL != null) setState(() => matchedBOL = null);
              },
            ),

            if (matchedBOL != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  border: Border.all(color: Colors.teal.shade200),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Colors.teal, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم العثور على بوليصة سابقة لنفس العميل — سيُضاف هذا المستند إلى نفس الملف'
                        '${previousInvoicesCount > 0 ? ' (يوجد $previousInvoicesCount فاتورة سابقة عليها)' : ''}.\n'
                        'ملاحظة: إن كانت أجور التخليص والنثريات محسوبة مسبقاً على هذه البوليصة، عدّل قيمتها أدناه لتفادي التكرار.',
                        style: const TextStyle(fontSize: 12, color: Colors.teal),
                      ),
                    ),
                  ],
                ),
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
            const SizedBox(height: 10),

            TextFormField(
              controller: containerCountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'عدد الحاويات *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'أدخل عدد الحاويات (رقم أكبر من صفر)';
                return null;
              },
            ),
            const SizedBox(height: 10),

            Text(
              'مستندات هذه الفاتورة: ${widget.imageFiles.length} ${widget.imageFiles.length == 1 ? 'صورة' : 'صور'} مرفقة (ستُحفظ مع ملف البوليصة)',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 20),

            // ------- بنود الفاتورة (اسم البند + المبلغ) -------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'بنود $_categoryLabel:',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366)),
                ),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('إضافة بند'),
                ),
              ],
            ),
            if (widget.ocrResult.items.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'البنود التالية مقترحة من قراءة الصورة تلقائياً - راجعها وعدّلها أو احذفها قبل الحفظ.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),

            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'لا توجد بنود بعد. اضغط "إضافة بند" لكتابة اسم البند ومبلغه يدوياً.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: item.descCtrl,
                            decoration: const InputDecoration(labelText: 'اسم البند', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: item.amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder(), isDense: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _removeItemRow(index),
                        ),
                      ],
                    ),
                  );
                },
              ),

            if (_itemsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(_itemsError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'إجمالي بنود $_categoryLabel: ${_itemsTotal.toStringAsFixed(2)} SDG',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'رسوم إضافية عامة (قابلة للتعديل):',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366)),
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
              icon: isSaving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: Text(
                isSaving ? 'جاري الحفظ...' : 'تأكيد وحفظ وتوليد فاتورة الـ PDF',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              onPressed: isSaving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
