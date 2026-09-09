import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/clearance_invoice.dart';
import '../models/shipment_document.dart';
import '../models/payment.dart';

class PDFService {
  static String _invoiceTitle(ClearanceInvoice invoice) {
    if (invoice.docTypes.length == 1) {
      switch (invoice.docTypes.first) {
        case 'ports':
          return 'فاتورة مطالبة - رسوم الموانئ';
        case 'customs':
          return 'فاتورة مطالبة - إشعار الجمارك';
        case 'storage':
          return 'فاتورة مطالبة - أرضيات الشركة';
        case 'permit':
          return 'فاتورة مطالبة - إذن الشركة';
      }
    }
    return 'فاتورة مطالبة تخليص';
  }

  static double _paymentsSum(List<Payment> payments) =>
      payments.fold<double>(0, (sum, p) => sum + p.amount);

  static Future<Uint8List> generateInvoicePDF(
    ClearanceInvoice invoice, {
    List<Payment> payments = const [],
    bool isFinal = false,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoBold();
    final fontRegular = await PdfGoogleFonts.cairoRegular();

    // نطبع بنود الفاتورة التفصيلية (اسم البند + مبلغه) كما أُدخلت أو استُخرجت من
    // الصورة، بدل رقم إجمالي واحد فقط. هذا يحافظ أيضاً على عدم خلط رسوم الموانئ
    // مع الجمارك أو الأرضيات أو الإذن في نفس الفاتورة، لأن كل فاتورة نوع واحد فقط.
    final rows = <List<String>>[];
    if (invoice.items.isNotEmpty) {
      for (final item in invoice.items) {
        rows.add([item.description, '${item.amount.toStringAsFixed(2)} SDG']);
      }
    } else {
      // توافق مع فواتير قديمة محفوظة قبل إضافة نظام البنود التفصيلية
      if (invoice.portFeesTotal > 0) {
        rows.add([DocType.label(DocType.ports), '${invoice.portFeesTotal.toStringAsFixed(2)} SDG']);
      }
      if (invoice.customsFeesTotal > 0) {
        rows.add([DocType.label(DocType.customs), '${invoice.customsFeesTotal.toStringAsFixed(2)} SDG']);
      }
      if (invoice.storageFeesTotal > 0) {
        rows.add([DocType.label(DocType.storage), '${invoice.storageFeesTotal.toStringAsFixed(2)} SDG']);
      }
      if (invoice.permitFeesTotal > 0) {
        rows.add([DocType.label(DocType.permit), '${invoice.permitFeesTotal.toStringAsFixed(2)} SDG']);
      }
    }
    if (invoice.agencyFee > 0) {
      rows.add(['أجور التخليص والخدمات', '${invoice.agencyFee.toStringAsFixed(2)} SDG']);
    }
    if (invoice.transportFee > 0) {
      rows.add(['رسوم النقل / النولون', '${invoice.transportFee.toStringAsFixed(2)} SDG']);
    }
    if (invoice.miscFee > 0) {
      rows.add(['نثريات وتدميغات ومصروفات نقدية', '${invoice.miscFee.toStringAsFixed(2)} SDG']);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // الهيدر الرسمي لشركة الشيخ مختار
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#003366'),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'أعمال الشيخ مختار الشيخ',
                          style: pw.TextStyle(font: font, fontSize: 18, color: PdfColors.white),
                        ),
                        pw.Text(
                          'Elsheikh M.E Clearing & Enterprise',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.lightBlue100),
                        ),
                        pw.Text(
                          'تخليص - ترحيل - تجارة عمومية',
                          style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.white),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          isFinal ? 'فاتورة نهائية' : _invoiceTitle(invoice),
                          style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.amber),
                        ),
                        pw.Text('التاريخ: ${invoice.date}', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.white)),
                        if (invoice.declarationNo.isNotEmpty)
                          pw.Text('رقم الإقرار: ${invoice.declarationNo}', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.white)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),

              // بيانات العميل والشحنة
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('اسم العميل: ${invoice.clientName}', style: pw.TextStyle(font: font, fontSize: 11)),
                        pw.Text('اسم الباخرة: ${invoice.vesselName}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('رقم البوليصة: ${invoice.billOfLading}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                        pw.Text('عدد الحاويات: ${invoice.containerCount}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),

              // جدول المصاريف التفصيلي - فقط البنود التي لها قيمة في هذه الفاتورة
              pw.TableHelper.fromTextArray(
                headers: ['البيان / نوع الخدمة', 'المبلغ (جنيه سوداني)'],
                data: rows,
                headerStyle: pw.TextStyle(font: font, color: PdfColors.white, fontSize: 11),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#0099CC')),
                cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
                cellAlignment: pw.Alignment.centerRight,
              ),
              pw.SizedBox(height: 15),

              // جدول الدفعات المسددة إن وُجدت
              if (payments.isNotEmpty) ...[
                pw.Text('الدفعات المسددة:', style: pw.TextStyle(font: font, fontSize: 11, color: PdfColor.fromHex('#003366'))),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  headers: ['التاريخ', 'ملاحظة', 'المبلغ (جنيه سوداني)'],
                  data: payments
                      .map((p) => [p.date, p.note.isEmpty ? '-' : p.note, '${p.amount.toStringAsFixed(2)} SDG'])
                      .toList(),
                  headerStyle: pw.TextStyle(font: font, color: PdfColors.white, fontSize: 10),
                  headerDecoration: pw.BoxDecoration(color: PdfColors.teal600),
                  cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
                  cellAlignment: pw.Alignment.centerRight,
                ),
                pw.SizedBox(height: 12),
              ],

              // الإجماليات والتصفية الحسابية
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('إجمالي المصاريف:', style: pw.TextStyle(font: font, fontSize: 11)),
                        pw.Text('${invoice.grandTotal.toStringAsFixed(2)} SDG', style: pw.TextStyle(font: font, fontSize: 11)),
                      ],
                    ),
                    pw.Divider(),
                    if (invoice.advancePayment > 0) ...[
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('خصم المقاديم / المدفوع مقدماً:', style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.red700)),
                          pw.Text('- ${invoice.advancePayment.toStringAsFixed(2)} SDG', style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.red700)),
                        ],
                      ),
                      pw.Divider(),
                    ],
                    if (payments.isNotEmpty) ...[
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('إجمالي الدفعات المسددة:', style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.red700)),
                          pw.Text('- ${_paymentsSum(payments).toStringAsFixed(2)} SDG', style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.red700)),
                        ],
                      ),
                      pw.Divider(),
                    ],
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('الصافي المطلوب سداده:', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromHex('#003366'))),
                        pw.Text(
                          '${invoice.netPayableAfterPayments(_paymentsSum(payments)).toStringAsFixed(2)} SDG',
                          style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromHex('#003366')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // التذييل وبور سودان
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('توقيع المخلص / المحاسب', style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.SizedBox(height: 20),
                      pw.Text('................................', style: pw.TextStyle(font: fontRegular)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Port Sudan - Sudan | بورتسودان', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                      pw.Text('الهاتف: +249912310347 | +249912287622', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                      pw.Text('البريد: mukhtarelshiekh@gmail.com', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
