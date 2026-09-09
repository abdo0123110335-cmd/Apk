class Payment {
  String id;
  String billOfLadingId;
  String clientId;
  double amount;
  String note;
  String date;

  Payment({
    required this.id,
    required this.billOfLadingId,
    this.clientId = '',
    required this.amount,
    this.note = '',
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'billOfLadingId': billOfLadingId,
    'clientId': clientId,
    'amount': amount,
    'note': note,
    'date': date,
  };

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
    id: map['id'],
    billOfLadingId: map['billOfLadingId'] ?? '',
    clientId: map['clientId'] ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    note: map['note'] ?? '',
    date: map['date'] ?? '',
  );
}
