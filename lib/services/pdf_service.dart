import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/clearance_invoice.dart';

class PDFService {
  static Future<Uint8List> generateInvoicePDF(ClearanceInvoice invoice) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoBold();
    final fontRegular = await PdfGoogleFonts.cairoRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            cross: pw.CrossAxisAlignment.start,
            children: [
              // الهيدر الرسمي لشركة الشيخ مختار
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#003366'),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  main: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      cross: pw.CrossAxisAlignment.start,
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
                      cross: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('فاتورة مطالبة تخليص', style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.amber)),
                        pw.Text('التاريخ: ${invoice.date}', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.white)),
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
                child: pw.Row(
                  main: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('اسم العميل: ${invoice.clientName}', style: pw.TextStyle(font: font, fontSize: 11)),
                    pw.Text('اسم الباخرة: ${invoice.vesselName}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                    pw.Text('البوليسة: ${invoice.billOfLading}', style: pw.TextStyle(font: fontRegular, fontSize: 11)),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),

              // جدول المصاريف التفصيلي
              pw.TableHelper.fromTextArray(
                headers: ['البيان / نوع الخدمة', 'المبلغ (جنيه سوداني)'],
                data: [
                  ['إجمالي رسوم هيئة الموانئ البحرية', '${invoice.portFeesTotal.toStringAsFixed(2)} SDG'],
                  ['إجمالي الرسوم الجمركية (أسيكودا)', '${invoice.customsFeesTotal.toStringAsFixed(2)} SDG'],
                  ['أجور التخليص والخدمات', '${invoice.agencyFee.toStringAsFixed(2)} SDG'],
                  ['رسوم النقل / النولون', '${invoice.transportFee.toStringAsFixed(2)} SDG'],
                  ['نثريات وتدميغات ومصروفات نقدية', '${invoice.miscFee.toStringAsFixed(2)} SDG'],
                ],
                headerStyle: pw.TextStyle(font: font, color: PdfColors.white, fontSize: 11),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#0099CC')),
                cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
                cellAlignment: pw.Alignment.centerRight,
              ),
              pw.SizedBox(height: 15),

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
                      main: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('إجمالي تكلفة المانفيستو والمصاريف:', style: pw.TextStyle(font: font, fontSize: 11)),
                        pw.Text('${invoice.grandTotal.toStringAsFixed(2)} SDG', style: pw.TextStyle(font: font, fontSize: 11)),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      main: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('خصم المقاديم / المدفوع مقدماً:', style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.red700)),
                        pw.Text('- ${invoice.advancePayment.toStringAsFixed(2)} SDG', style: pw.TextStyle(font: fontRegular, fontSize: 11, color: PdfColors.red700)),
                      ],
                    ),
                    pw.Divider(),
                    pw.Row(
                      main: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('الصافي المطلوب سداده:', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromHex('#003366'))),
                        pw.Text('${invoice.netPayable.toStringAsFixed(2)} SDG', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromHex('#003366'))),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // التذييل وبور سودان
              pw.Row(
                main: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    cross: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('توقيع المخلص / المحاسب', style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.SizedBox(height: 20),
                      pw.Text('................................', style: pw.TextStyle(font: fontRegular)),
                    ],
                  ),
                  pw.Column(
                    cross: pw.CrossAxisAlignment.end,
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
