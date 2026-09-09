/// أنواع المستندات المدعومة في التطبيق.
/// كل نوع مربوط بفئة رسوم مستقلة داخل الفاتورة.
class DocType {
  static const ports = 'ports'; // فاتورة رسوم هيئة الموانئ
  static const customs = 'customs'; // إشعار تقييم الجمارك (أسيكودا)
  static const storage = 'storage'; // فاتورة أرضيات الشركة
  static const permit = 'permit'; // رسوم إذن الشركة (إذن التسليم)

  static const all = [ports, customs, storage, permit];

  static String label(String type) {
    switch (type) {
      case ports:
        return 'رسوم هيئة الموانئ البحرية';
      case customs:
        return 'إشعار تقييم الجمارك (أسيكودا)';
      case storage:
        return 'أرضيات الشركة';
      case permit:
        return 'إذن الشركة (إذن التسليم)';
      default:
        return type;
    }
  }

  static String shortTitle(String type) {
    switch (type) {
      case ports:
        return 'فاتورة موانئ';
      case customs:
        return 'فاتورة جمارك';
      case storage:
        return 'فاتورة أرضيات';
      case permit:
        return 'فاتورة إذن';
      default:
        return type;
    }
  }
}

class ShipmentDocument {
  String id;
  String billOfLadingId;
  String docType;
  String imagePath;
  double amount;
  String description;
  String date;

  ShipmentDocument({
    required this.id,
    required this.billOfLadingId,
    required this.docType,
    required this.imagePath,
    required this.amount,
    this.description = '',
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'billOfLadingId': billOfLadingId,
    'docType': docType,
    'imagePath': imagePath,
    'amount': amount,
    'description': description,
    'date': date,
  };

  factory ShipmentDocument.fromMap(Map<String, dynamic> map) => ShipmentDocument(
    id: map['id'],
    billOfLadingId: map['billOfLadingId'] ?? '',
    docType: map['docType'] ?? '',
    imagePath: map['imagePath'] ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    description: map['description'] ?? '',
    date: map['date'] ?? '',
  );
}
