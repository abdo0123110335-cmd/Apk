import 'dart:io';

class OCRResult {
  final String clientName;
  final String declarationNo;
  final String vesselName;
  final String billNo;
  final double totalAmount;
  final double vat;
  final Map<String, double> items;

  OCRResult({
    required this.clientName,
    required this.declarationNo,
    required this.vesselName,
    required this.billNo,
    required this.totalAmount,
    required this.vat,
    required this.items,
  });
}

class OCRService {
  // المحاكي الذكي لقراءة فواتير الموانئ وإشعار الجمارك (أسيكودا)
  Future<OCRResult> processDocument(File imageFile, String docType) async {
    await Future.delayed(const Duration(seconds: 2)); // محاكاة المعالجة

    if (docType == 'ports') {
      return OCRResult(
        clientName: 'ELSHEIKH MUKHTAR ELS',
        declarationNo: '8330',
        vesselName: 'KOTA NILAM',
        billNo: '10126056795',
        totalAmount: 6306800.94,
        vat: 914734.54,
        items: {
          'HANDLING FULL CONTAINER': 711001.80,
          'SHIFTING FULL': 711001.80,
          'PORT DUES FOR CONTAINERS': 3792009.60,
          'PORRT DEUES S O C CONT': 79000.20,
          'Extraction Bill': 21944.50,
          'VAT': 914734.54,
        },
      );
    } else {
      // أسيكودا الجمارك
      return OCRResult(
        clientName: 'MASHARIQ DEVELOPMENT CO.LTD',
        declarationNo: 'A 4628',
        vesselName: 'KOTA NILAM',
        billNo: 'H 4634',
        totalAmount: 9014.00,
        vat: 0.0,
        items: {
          'Computer Service': 2500.00,
          'Business Stamp': 5000.00,
          'Stamp Tax': 1500.00,
          'Police Stamp': 14.00,
        },
      );
    }
  }
}
