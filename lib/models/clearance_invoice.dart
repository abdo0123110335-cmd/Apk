/// فئات بنود الفاتورة. الأربعة الأولى مرتبطة بأنواع المستندات الممسوحة ضوئياً
/// (نفس قيم DocType)، بينما 'fee' تمثل أتعاب الكشف/الخدمات و 'transport' و
/// 'misc' و 'other' لأي بند إضافي يُضاف يدوياً من داخل الفاتورة.
class ItemCategory {
  static const ports = 'ports';
  static const customs = 'customs';
  static const storage = 'storage';
  static const permit = 'permit';
  static const fee = 'fee'; // أتعاب الكشف / خدمات التخليص
  static const transport = 'transport';
  static const misc = 'misc';
  static const other = 'other';

  static const all = [ports, customs, storage, permit, fee, transport, misc, other];

  static String label(String category) {
    switch (category) {
      case ports:
        return 'رسوم هيئة الموانئ';
      case customs:
        return 'رسوم الجمارك (أسيكودا)';
      case storage:
        return 'أرضيات الشركة';
      case permit:
        return 'إذن الشركة';
      case fee:
        return 'أتعاب الكشف والخدمات';
      case transport:
        return 'نقل ونولون';
      case misc:
        return 'نثريات ومصروفات';
      default:
        return 'بند آخر';
    }
  }
}

class InvoiceItem {
  String description;
  double amount;
  String category; // انظر ItemCategory أعلاه

  InvoiceItem({
    required this.description,
    required this.amount,
    required this.category,
  });

  Map<String, dynamic> toMap() => {
    'description': description,
    'amount': amount,
    'category': category,
  };

  factory InvoiceItem.fromMap(Map<String, dynamic> map) => InvoiceItem(
    description: map['description'],
    amount: (map['amount'] as num).toDouble(),
    category: map['category'],
  );
}

class ClearanceInvoice {
  String id;
  String billOfLadingId;
  String clientId;
  String clientName;
  String declarationNo;
  String billOfLading;
  String vesselName;
  int containerCount;
  String date;

  /// أنواع المستندات المشمولة فعلياً في هذه الفاتورة بالذات (ports/customs/storage/permit)
  /// تُستخدم لطباعة السطور الخاصة بها فقط وعدم خلط كل الرسوم في فاتورة واحدة.
  List<String> docTypes;

  List<InvoiceItem> items;
  double portFeesTotal;
  double customsFeesTotal;
  double storageFeesTotal;
  double permitFeesTotal;
  double agencyFee;
  double transportFee;
  double miscFee;
  double advancePayment;

  ClearanceInvoice({
    required this.id,
    this.billOfLadingId = '',
    required this.clientId,
    required this.clientName,
    required this.declarationNo,
    required this.billOfLading,
    required this.vesselName,
    this.containerCount = 0,
    required this.date,
    this.docTypes = const [],
    required this.items,
    this.portFeesTotal = 0,
    this.customsFeesTotal = 0,
    this.storageFeesTotal = 0,
    this.permitFeesTotal = 0,
    this.agencyFee = 0,
    this.transportFee = 0,
    this.miscFee = 0,
    this.advancePayment = 0,
  });

  /// المجموع الفعلي = مجموع كل بنود الفاتورة (items) بغض النظر عن فئتها.
  /// يُفضّل استخدام هذا بدل الحقول الرقمية القديمة لأنه يعكس أي تعديل يدوي.
  double get itemsTotal => items.fold<double>(0, (sum, it) => sum + it.amount);

  double get grandTotal => items.isNotEmpty
      ? itemsTotal
      : (portFeesTotal + customsFeesTotal + storageFeesTotal + permitFeesTotal + agencyFee + transportFee + miscFee);

  double get netPayable => grandTotal - advancePayment;

  /// يعيد حساب حقول إجمالي كل فئة (portFeesTotal...الخ) من قائمة البنود الحالية،
  /// حتى تبقى متوافقة مع أي كود قديم يعرضها مباشرة (مثل شاشة الأرشيف القديمة).
  void recomputeCategoryTotals() {
    double sumFor(String cat) =>
        items.where((i) => i.category == cat).fold<double>(0, (s, i) => s + i.amount);
    portFeesTotal = sumFor(ItemCategory.ports);
    customsFeesTotal = sumFor(ItemCategory.customs);
    storageFeesTotal = sumFor(ItemCategory.storage);
    permitFeesTotal = sumFor(ItemCategory.permit);
    agencyFee = sumFor(ItemCategory.fee);
    transportFee = sumFor(ItemCategory.transport);
    miscFee = sumFor(ItemCategory.misc) +
        items.where((i) => i.category == ItemCategory.other).fold<double>(0, (s, i) => s + i.amount);
  }

  /// الصافي المطلوب سداده بعد خصم كل الدفعات المسجلة (بالإضافة إلى دفعة المقدم القديمة إن وُجدت).
  double netPayableAfterPayments(double paymentsSum) => netPayable - paymentsSum;

  Map<String, dynamic> toMap() => {
    'id': id,
    'billOfLadingId': billOfLadingId,
    'clientId': clientId,
    'clientName': clientName,
    'declarationNo': declarationNo,
    'billOfLading': billOfLading,
    'vesselName': vesselName,
    'containerCount': containerCount,
    'date': date,
    'docTypes': docTypes.join(','),
    'portFeesTotal': portFeesTotal,
    'customsFeesTotal': customsFeesTotal,
    'storageFeesTotal': storageFeesTotal,
    'permitFeesTotal': permitFeesTotal,
    'agencyFee': agencyFee,
    'transportFee': transportFee,
    'miscFee': miscFee,
    'advancePayment': advancePayment,
  };

  factory ClearanceInvoice.fromMap(Map<String, dynamic> map) => ClearanceInvoice(
    id: map['id'],
    billOfLadingId: map['billOfLadingId'] ?? '',
    clientId: map['clientId'] ?? '',
    clientName: map['clientName'] ?? '',
    declarationNo: map['declarationNo'] ?? '',
    billOfLading: map['billOfLading'] ?? '',
    vesselName: map['vesselName'] ?? '',
    containerCount: (map['containerCount'] as num?)?.toInt() ?? 0,
    date: map['date'] ?? '',
    docTypes: ((map['docTypes'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList(),
    items: const [],
    portFeesTotal: (map['portFeesTotal'] as num?)?.toDouble() ?? 0,
    customsFeesTotal: (map['customsFeesTotal'] as num?)?.toDouble() ?? 0,
    storageFeesTotal: (map['storageFeesTotal'] as num?)?.toDouble() ?? 0,
    permitFeesTotal: (map['permitFeesTotal'] as num?)?.toDouble() ?? 0,
    agencyFee: (map['agencyFee'] as num?)?.toDouble() ?? 0,
    transportFee: (map['transportFee'] as num?)?.toDouble() ?? 0,
    miscFee: (map['miscFee'] as num?)?.toDouble() ?? 0,
    advancePayment: (map['advancePayment'] as num?)?.toDouble() ?? 0,
  );
}
