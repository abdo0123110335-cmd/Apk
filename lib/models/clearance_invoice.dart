class InvoiceItem {
  String description;
  double amount;
  String category; // 'port', 'customs', 'agency', 'transport', 'misc'

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
  String clientId;
  String clientName;
  String declarationNo;
  String billOfLading;
  String vesselName;
  String date;
  List<InvoiceItem> items;
  double portFeesTotal;
  double customsFeesTotal;
  double agencyFee;
  double transportFee;
  double miscFee;
  double advancePayment;

  ClearanceInvoice({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.declarationNo,
    required this.billOfLading,
    required this.vesselName,
    required this.date,
    required this.items,
    required this.portFeesTotal,
    required this.customsFeesTotal,
    required this.agencyFee,
    required this.transportFee,
    required this.miscFee,
    required this.advancePayment,
  });

  double get grandTotal => portFeesTotal + customsFeesTotal + agencyFee + transportFee + miscFee;
  double get netPayable => grandTotal - advancePayment;

  Map<String, dynamic> toMap() => {
    'id': id,
    'clientId': clientId,
    'clientName': clientName,
    'declarationNo': declarationNo,
    'billOfLading': billOfLading,
    'vesselName': vesselName,
    'date': date,
    'portFeesTotal': portFeesTotal,
    'customsFeesTotal': customsFeesTotal,
    'agencyFee': agencyFee,
    'transportFee': transportFee,
    'miscFee': miscFee,
    'advancePayment': advancePayment,
  };
}
