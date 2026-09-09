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
import 'invoice_detail_screen.dart';

/// صف بند واحد (اسم البند + مبلغه) مع الـ controllers الخاصة به.
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

/// شاشة إدخال بيانات المستند بعد تصويره/رفعه: تطلب فقط (رقم البوليصة، اسم
/// العميل، المبلغ) كحد أدنى، مع إمكانية فتح "بيانات إضافية" اختيارية.
/// عند الحفظ: يُحفظ العميل تلقائياً في دليل العملاء إن كان اسماً جديداً،
/// وتُحفظ الصور داخل ملف العميل ثم داخل ملف رقم البوليصة، ويُضاف المبلغ إلى
/// الفاتورة الموحّدة الخاصة بهذه البوليصة (فاتورة واحدة تجمع كل الرسوم).
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
  late TextEditingController billOfLadingCtrl;
  late TextEditingController declarationCtrl;
  late TextEditingController vesselCtrl;
  late TextEditingController containerCountCtrl;

  final List<_ItemRow> _items = [];
  String? _itemsError;
  bool _showAdvanced = false;

  List<Client> availableClients = [];
  Client? selectedClient;

  BillOfLading? matchedBOL;
  bool isChecking = false;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    clientNameCtrl = TextEditingController();
    billOfLadingCtrl = TextEditingController(text: widget.ocrResult.billNo);
    declarationCtrl = TextEditingController(text: widget.ocrResult.declarationNo);
    vesselCtrl = TextEditingController(text: widget.ocrResult.vesselName);
    containerCountCtrl = TextEditingController();

    // بند افتراضي واحد يمثّل "المبلغ" - يُملأ تلقائياً من قراءة الصورة إن أمكن.
    if (widget.ocrResult.items.isNotEmpty) {
      widget.ocrResult.items.forEach((desc, amount) {
        _items.add(_ItemRow(desc: desc, amount: amount.toStringAsFixed(2)));
      });
    } else {
      _items.add(_ItemRow(
        desc: DocType.shortTitle(widget.docType),
        amount: widget.ocrResult.totalAmount > 0 ? widget.ocrResult.totalAmount.toStringAsFixed(2) : '',
      ));
    }

    _loadClients();
  }

  Future<void> _loadClients() async {
    final list = await DatabaseService.instance.getClients();
    setState(() => availableClients = list);
  }

  Future<void> _checkExistingBillOfLading() async {
    final billNo = billOfLadingCtrl.text.trim();
    if (billNo.isEmpty || (selectedClient == null && clientNameCtrl.text.trim().isEmpty)) {
      setState(() => matchedBOL = null);
      return;
    }
    setState(() => isChecking = true);
    BillOfLading? found;
    if (selectedClient != null) {
      found = await DatabaseService.instance.findBillOfLading(billNo, selectedClient!.id);
    }
    if (!mounted) return;
    setState(() {
      matchedBOL = found;
      isChecking = false;
      if (found != null) {
        if (vesselCtrl.text.trim().isEmpty) vesselCtrl.text = found!.vesselName;
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
      setState(() => _itemsError = 'أدخل المبلغ (رقم أكبر من صفر) قبل الحفظ');
      return;
    }
    setState(() => _itemsError = null);

    setState(() => isSaving = true);
    try {
      final now = DateFormat('yyyy/MM/dd').format(DateTime.now());
      final billNo = billOfLadingCtrl.text.trim();

      // 1) العميل: إن لم يُختر من الدليل، يُبحث عن اسم مطابق أو يُنشأ عميل جديد تلقائياً.
      final client = selectedClient ?? await DatabaseService.instance.findOrCreateClientByName(clientNameCtrl.text.trim());

      // 2) البوليصة: نبحث عن بوليصة بنفس الرقم لنفس العميل، وإلا تُنشأ جديدة.
      final existingBol = matchedBOL ?? await DatabaseService.instance.findBillOfLading(billNo, client.id);
      final containerCount = int.tryParse(containerCountCtrl.text.trim()) ?? existingBol?.containerCount ?? 0;
      final bolId = existingBol?.id ?? const Uuid().v4();
      final bol = BillOfLading(
        id: bolId,
        billNumber: billNo,
        clientId: client.id,
        clientName: client.name,
        vesselName: vesselCtrl.text.trim().isEmpty ? (existingBol?.vesselName ?? '') : vesselCtrl.text.trim(),
        containerCount: containerCount,
        date: existingBol?.date ?? now,
      );
      await DatabaseService.instance.insertBillOfLading(bol);

      // 3) حفظ صور المستند داخل: ملف العميل (بمعرفه) ثم ملف رقم البوليصة.
      final savedPaths = await _persistImages(client.id, billNo);
      for (var i = 0; i < savedPaths.length; i++) {
        final doc = ShipmentDocument(
          id: const Uuid().v4(),
          billOfLadingId: bolId,
          docType: widget.docType,
          imagePath: savedPaths[i],
          amount: i == 0 ? _itemsTotal : 0.0,
          description: savedPaths.length > 1 ? 'مستند ${i + 1} من ${savedPaths.length}' : '',
          date: now,
        );
        await DatabaseService.instance.insertShipmentDocument(doc);
      }

      // 4) إضافة بنود هذا المستند إلى الفاتورة الموحّدة الخاصة بهذه البوليصة.
      final invoice = await DatabaseService.instance.getOrCreateInvoiceForBillOfLading(
        bolId,
        clientId: client.id,
        clientName: client.name,
        billOfLading: billNo,
        vesselName: bol.vesselName,
        containerCount: containerCount,
        declarationNo: declarationCtrl.text.trim(),
      );
      final newItems = validItems
          .map((it) => InvoiceItem(
                description: it.descCtrl.text.trim(),
                amount: double.tryParse(it.amountCtrl.text.trim()) ?? 0,
                category: widget.docType,
              ))
          .toList();
      await DatabaseService.instance.addItemsToInvoice(invoice, newItems);

      if (!mounted) return;
      setState(() => isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المستند وربطه بملف العميل بنجاح')),
      );

      // ننتقل مباشرة إلى شاشة الفاتورة الموحّدة لهذه البوليصة حتى يمكن مراجعتها
      // أو إضافة أتعاب/دفعات أو إصدار الفاتورة النهائية فوراً.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => InvoiceDetailScreen(billOfLadingId: bolId)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
      );
    }
  }

  Future<List<String>> _persistImages(String clientId, String billNo) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final safeBillNo = billNo.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final targetDir = Directory(p.join(docsDir.path, 'clients', clientId, safeBillNo));
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
    billOfLadingCtrl.dispose();
    declarationCtrl.dispose();
    vesselCtrl.dispose();
    containerCountCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('بيانات $_categoryLabel'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (widget.imageFiles.isNotEmpty) ...[
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.imageFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(widget.imageFiles[i], width: 90, height: 90, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ---- اسم العميل ----
            DropdownButtonFormField<Client>(
              decoration: const InputDecoration(
                labelText: 'اختر عميلاً مسجلاً (اختياري)',
                border: OutlineInputBorder(),
              ),
              items: availableClients.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
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
              decoration: const InputDecoration(
                labelText: 'اسم العميل *',
                helperText: 'إن كان اسماً جديداً سيُضاف تلقائياً إلى دليل العملاء',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب إدخال اسم العميل' : null,
              onChanged: (_) {
                if (selectedClient != null && clientNameCtrl.text.trim() != selectedClient!.name) {
                  setState(() => selectedClient = null);
                }
              },
              onEditingComplete: _checkExistingBillOfLading,
            ),
            const SizedBox(height: 10),

            // ---- رقم البوليصة ----
            TextFormField(
              controller: billOfLadingCtrl,
              decoration: InputDecoration(
                labelText: 'رقم البوليصة *',
                border: const OutlineInputBorder(),
                helperText: widget.ocrResult.billNo.isEmpty
                    ? 'لم يتم العثور على رقم البوليصة في الصورة - أدخله يدوياً'
                    : 'تم العثور على الرقم تلقائياً من الصورة - تحقق منه',
                suffixIcon: isChecking
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'رقم البوليصة مطلوب' : null,
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
                child: const Row(
                  children: [
                    Icon(Icons.link, color: Colors.teal, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'يوجد ملف سابق لهذه البوليصة عند هذا العميل — سيُضاف هذا المستند إلى نفس الفاتورة.',
                        style: TextStyle(fontSize: 12, color: Colors.teal),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // ---- المبلغ (بند أو أكثر) ----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المبلغ:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('إضافة بند آخر'),
                ),
              ],
            ),
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
                          decoration: const InputDecoration(labelText: 'البيان', border: OutlineInputBorder(), isDense: true),
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
                      if (_items.length > 1)
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
                'إجمالي هذا المستند: ${_itemsTotal.toStringAsFixed(2)} SDG',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),

            // ---- بيانات إضافية اختيارية ----
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF003366)),
                  const Text('بيانات إضافية (اختياري)', style: TextStyle(color: Color(0xFF003366), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (_showAdvanced) ...[
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
                  labelText: 'عدد الحاويات',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
            ],
            const SizedBox(height: 25),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003366),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: isSaving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(
                isSaving ? 'جاري الحفظ...' : 'حفظ وربط بملف العميل',
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
