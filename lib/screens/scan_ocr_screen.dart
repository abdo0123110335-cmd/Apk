import 'dart:io';
import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import 'review_invoice_screen.dart';

class ScanOCRScreen extends StatefulWidget {
  final String docType;
  const ScanOCRScreen({super.key, required this.docType});

  @override
  State<ScanOCRScreen> createState() => _ScanOCRScreenState();
}

class _ScanOCRScreenState extends State<ScanOCRScreen> {
  bool isScanning = false;

  void _startProcess() async {
    setState(() => isScanning = true);
    final ocr = OCRService();
    final result = await ocr.processDocument(File('dummy'), widget.docType);

    setState(() => isScanning = false);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewInvoiceScreen(ocrResult: result, docType: widget.docType),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.docType == 'ports' ? 'مسح فاتورة الموانئ' : 'مسح إشعار أسيكودا'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.docType == 'ports' ? Icons.anchor : Icons.assignment,
                size: 90,
                color: const Color(0xFF003366),
              ),
              const SizedBox(height: 20),
              Text(
                widget.docType == 'ports'
                    ? 'التقط صورة لشهادة/فاتورة هيئة الموانئ البحرية'
                    : 'التقط صورة لإشعار تقييم الجمارك (أسيكودا)',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              if (isScanning) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 15),
                const Text('جاري تحليل النصوص والمبالغ بالذكاء الاصطناعي...'),
              ] else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0099CC),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text('بدء التصوير والمسح الآلي', style: TextStyle(color: Colors.white, fontSize: 16)),
                  onPressed: _startProcess,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
