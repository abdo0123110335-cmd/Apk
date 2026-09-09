import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// نتيجة قراءة المستند: كل الحقول تُستخرج مباشرة من النص المقروء بالصورة
/// (قراءة نصوص حقيقية على الجهاز عبر Google ML Kit - بدون أي محرك ذكاء اصطناعي
/// وبدون إرسال الصورة لأي خادم خارجي). النتائج مقترحات قابلة للمراجعة والتعديل
/// دائماً قبل الحفظ، لأن استخراج الحقول يعتمد على قواعد تحليل نصية وليس فهماً ذكياً.
class OCRResult {
  final String billNo; // رقم البوليصة إن وُجد
  final String vesselName;
  final String declarationNo;
  final double totalAmount; // آخر سطر يحتوي على كلمة TOTAL مع مبلغ
  final Map<String, double> items; // بنود مقترحة: الوصف -> المبلغ
  final String rawText; // النص الكامل المقروء (للمراجعة اليدوية عند الحاجة)

  OCRResult({
    required this.billNo,
    required this.vesselName,
    required this.declarationNo,
    required this.totalAmount,
    required this.items,
    required this.rawText,
  });

  factory OCRResult.empty() => OCRResult(
    billNo: '',
    vesselName: '',
    declarationNo: '',
    totalAmount: 0,
    items: const {},
    rawText: '',
  );
}

class OCRService {
  // يدعم Google ML Kit الأحرف اللاتينية (English/Numbers) بشكل افتراضي - وهو ما
  // تُطبع به غالبية فواتير هيئة الموانئ وإشعارات أسيكودا فعلياً (أسماء الخدمات
  // والأرقام والمبالغ بالإنجليزية). النصوص العربية الخالصة لا يقرأها هذا المحرك.
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static final RegExp _amountRe = RegExp(r'([0-9][0-9,]*\.[0-9]{2})');
  static final RegExp _blKeywordRe = RegExp(r'B\s*/?\s*L\b|BILL\s*OF\s*LADING', caseSensitive: false);
  static final RegExp _vesselKeywordRe = RegExp(r'VESSEL', caseSensitive: false);
  static final RegExp _declKeywordRe = RegExp(r'DECLAR|REG(?:ISTRATION)?\s*(?:NO|#)', caseSensitive: false);
  static final RegExp _totalKeywordRe = RegExp(r'\bTOTAL\b', caseSensitive: false);
  static final RegExp _codeRe = RegExp(r'[A-Z0-9][A-Z0-9\-\/]{5,}');
  static final RegExp _shortCodeRe = RegExp(r'[A-Z0-9][A-Z0-9\-\/]{3,}');
  static final RegExp _digitsOnlyRe = RegExp(r'^[\d\s\-\/.,]+$');

  Future<OCRResult> processDocument(List<File> imageFiles, String docType) async {
    if (imageFiles.isEmpty) return OCRResult.empty();

    final buffer = StringBuffer();
    for (final file in imageFiles) {
      try {
        final inputImage = InputImage.fromFilePath(file.path);
        final recognized = await _recognizer.processImage(inputImage);
        buffer.writeln(recognized.text);
      } catch (_) {
        // نتجاهل صورة تعذّرت قراءتها ونكمل الباقي بدل إيقاف كل العملية
      }
    }

    return _parse(buffer.toString());
  }

  OCRResult _parse(String fullText) {
    final lines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String billNo = '';
    String vesselName = '';
    String declarationNo = '';
    double totalAmount = 0;
    final items = <String, double>{};

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      if (billNo.isEmpty && _blKeywordRe.hasMatch(upper)) {
        final afterKeyword = upper.replaceFirst(_blKeywordRe, ' ');
        final match = _codeRe.firstMatch(afterKeyword);
        if (match != null) {
          billNo = match.group(0)!;
        } else if (i + 1 < lines.length) {
          final next = _codeRe.firstMatch(lines[i + 1].toUpperCase());
          if (next != null) billNo = next.group(0)!;
        }
      }

      if (vesselName.isEmpty && _vesselKeywordRe.hasMatch(upper)) {
        var rest = line.replaceAll(_vesselKeywordRe, '').trim();
        rest = rest.replaceFirst(RegExp(r'^[:\-\s]+'), '').trim();
        if (rest.isEmpty && i + 1 < lines.length) rest = lines[i + 1].trim();
        if (rest.isNotEmpty) vesselName = rest;
      }

      if (declarationNo.isEmpty && _declKeywordRe.hasMatch(upper)) {
        final afterKeyword = upper.replaceFirst(_declKeywordRe, ' ');
        final match = _shortCodeRe.firstMatch(afterKeyword);
        if (match != null) declarationNo = match.group(0)!;
      }

      final amountMatch = _amountRe.firstMatch(line);
      if (amountMatch != null) {
        final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0;
        if (amount <= 0) continue;

        if (_totalKeywordRe.hasMatch(upper)) {
          totalAmount = amount;
          continue;
        }

        final desc = line.substring(0, amountMatch.start).trim();
        if (desc.length > 2 && !_digitsOnlyRe.hasMatch(desc)) {
          items[desc] = amount;
        }
      }
    }

    return OCRResult(
      billNo: billNo,
      vesselName: vesselName,
      declarationNo: declarationNo,
      totalAmount: totalAmount,
      items: items,
      rawText: fullText,
    );
  }

  void dispose() {
    _recognizer.close();
  }
}
