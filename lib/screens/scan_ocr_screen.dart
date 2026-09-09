import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/shipment_document.dart';
import '../services/ocr_service.dart';
import 'review_invoice_screen.dart';

class ScanOCRScreen extends StatefulWidget {
  final String docType;
  const ScanOCRScreen({super.key, required this.docType});

  @override
  State<ScanOCRScreen> createState() => _ScanOCRScreenState();
}

class _ScanOCRScreenState extends State<ScanOCRScreen> {
  final ImagePicker _picker = ImagePicker();
  final OCRService _ocr = OCRService();
  final List<File> _images = [];
  bool isScanning = false;

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (shot != null) {
        setState(() => _images.add(File(shot.path)));
      }
    } catch (e) {
      _showError('تعذر فتح الكاميرا. تأكد من منح التطبيق صلاحية الكاميرا من إعدادات الجهاز.');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final shots = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 2000);
      if (shots.isNotEmpty) {
        setState(() => _images.addAll(shots.map((x) => File(x.path))));
      }
    } catch (e) {
      _showError('تعذر فتح معرض الصور. تأكد من منح التطبيق صلاحية الوصول للصور.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _startProcess() async {
    if (_images.isEmpty) {
      _showError('الرجاء التقاط صورة واحدة على الأقل أو اختيارها من المعرض قبل المتابعة.');
      return;
    }

    setState(() => isScanning = true);
    final result = await _ocr.processDocument(_images, widget.docType);

    if (!mounted) return;
    setState(() => isScanning = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewInvoiceScreen(
          ocrResult: result,
          docType: widget.docType,
          imageFiles: List<File>.from(_images),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = DocType.shortTitle(widget.docType);
    final instruction = _instructionFor(widget.docType);
    final icon = _iconFor(widget.docType);

    return Scaffold(
      appBar: AppBar(title: Text('مسح: $title')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(icon, size: 64, color: const Color(0xFF003366)),
            const SizedBox(height: 12),
            Text(
              instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (_images.isNotEmpty)
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_images[index], fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Text(
                    'لا توجد صور بعد.\nاستخدم الكاميرا أو المعرض لإضافة صور المستند (يمكن إضافة أكثر من صورة لنفس المستند).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            if (isScanning) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text('جاري تحليل النصوص والمبالغ...'),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('التقاط بالكاميرا'),
                      onPressed: _takePhoto,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('إضافة من المعرض'),
                      onPressed: _pickFromGallery,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0099CC),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.document_scanner, color: Colors.white),
                label: Text(
                  'متابعة (${_images.length} ${_images.length == 1 ? 'صورة' : 'صور'})',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                onPressed: _images.isEmpty ? null : _startProcess,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _instructionFor(String docType) {
    switch (docType) {
      case 'ports':
        return 'التقط صورة (أو أكثر) لفاتورة هيئة الموانئ البحرية';
      case 'customs':
        return 'التقط صورة (أو أكثر) لإشعار تقييم الجمارك (أسيكودا)';
      case 'storage':
        return 'التقط صورة (أو أكثر) لفاتورة أرضيات الشركة';
      case 'permit':
        return 'التقط صورة (أو أكثر) لفاتورة/إيصال إذن الشركة (إذن التسليم)';
      default:
        return 'التقط صورة المستند';
    }
  }

  IconData _iconFor(String docType) {
    switch (docType) {
      case 'ports':
        return Icons.anchor;
      case 'customs':
        return Icons.assignment;
      case 'storage':
        return Icons.warehouse;
      case 'permit':
        return Icons.fact_check;
      default:
        return Icons.description;
    }
  }
}
