import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/client.dart';
import '../models/bill_of_lading.dart';
import '../models/shipment_document.dart';
import '../models/clearance_invoice.dart';
import '../models/payment.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('elsheikh_customs.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        taxNumber TEXT,
        address TEXT,
        advanceBalance REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE bill_of_ladings (
        id TEXT PRIMARY KEY,
        billNumber TEXT NOT NULL,
        clientId TEXT,
        clientName TEXT,
        vesselName TEXT,
        containerCount INTEGER,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE shipment_documents (
        id TEXT PRIMARY KEY,
        billOfLadingId TEXT NOT NULL,
        docType TEXT,
        imagePath TEXT,
        amount REAL,
        description TEXT,
        date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id TEXT PRIMARY KEY,
        billOfLadingId TEXT,
        clientId TEXT,
        clientName TEXT,
        declarationNo TEXT,
        billOfLading TEXT,
        vesselName TEXT,
        containerCount INTEGER,
        date TEXT,
        docTypes TEXT,
        portFeesTotal REAL,
        customsFeesTotal REAL,
        storageFeesTotal REAL,
        permitFeesTotal REAL,
        agencyFee REAL,
        transportFee REAL,
        miscFee REAL,
        advancePayment REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id TEXT PRIMARY KEY,
        invoiceId TEXT NOT NULL,
        description TEXT,
        amount REAL,
        category TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        billOfLadingId TEXT NOT NULL,
        clientId TEXT,
        amount REAL,
        note TEXT,
        date TEXT
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bill_of_ladings (
          id TEXT PRIMARY KEY,
          billNumber TEXT NOT NULL,
          clientId TEXT,
          clientName TEXT,
          vesselName TEXT,
          containerCount INTEGER,
          date TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS shipment_documents (
          id TEXT PRIMARY KEY,
          billOfLadingId TEXT NOT NULL,
          docType TEXT,
          imagePath TEXT,
          amount REAL,
          description TEXT,
          date TEXT
        )
      ''');

      // الجدول القديم كان بدون هذه الأعمدة - نضيفها بأمان لعدم فقدان بيانات موجودة
      final existing = await db.rawQuery("PRAGMA table_info(invoices)");
      final existingCols = existing.map((e) => e['name'] as String).toSet();
      final newCols = <String, String>{
        'billOfLadingId': 'TEXT',
        'containerCount': 'INTEGER',
        'docTypes': 'TEXT',
        'storageFeesTotal': 'REAL',
        'permitFeesTotal': 'REAL',
      };
      for (final entry in newCols.entries) {
        if (!existingCols.contains(entry.key)) {
          await db.execute('ALTER TABLE invoices ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoice_items (
          id TEXT PRIMARY KEY,
          invoiceId TEXT NOT NULL,
          description TEXT,
          amount REAL,
          category TEXT
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payments (
          id TEXT PRIMARY KEY,
          billOfLadingId TEXT NOT NULL,
          clientId TEXT,
          amount REAL,
          note TEXT,
          date TEXT
        )
      ''');
    }
  }

  // ---------------- Clients ----------------

  Future<int> insertClient(Client client) async {
    final db = await instance.database;
    return await db.insert('clients', client.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Client>> getClients() async {
    final db = await instance.database;
    final result = await db.query('clients', orderBy: 'name ASC');
    return result.map((json) => Client.fromMap(json)).toList();
  }

  Future<int> updateClient(Client client) async {
    final db = await instance.database;
    return await db.update('clients', client.toMap(), where: 'id = ?', whereArgs: [client.id]);
  }

  Future<int> deleteClient(String id) async {
    final db = await instance.database;
    return await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  Future<Client?> getClientById(String id) async {
    final db = await instance.database;
    final result = await db.query('clients', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Client.fromMap(result.first);
  }

  /// يبحث عن عميل بنفس الاسم (غير حساس لحالة الأحرف/المسافات) وإن لم يجده
  /// يُنشئ عميلاً جديداً تلقائياً بهذا الاسم. هكذا يبقى كل مستند مرتبطاً بعميل
  /// حقيقي له ملف واحد ثابت، بدل معرّفات مؤقتة غير مرتبطة بدليل العملاء.
  Future<Client> findOrCreateClientByName(String name) async {
    final cleaned = name.trim();
    final clients = await getClients();
    for (final c in clients) {
      if (c.name.trim().toLowerCase() == cleaned.toLowerCase()) return c;
    }
    final newClient = Client(
      id: const Uuid().v4(),
      name: cleaned,
      phone: '',
      taxNumber: '',
      address: '',
      advanceBalance: 0.0,
    );
    await insertClient(newClient);
    return newClient;
  }

  // ---------------- Bill of Lading ----------------

  Future<int> insertBillOfLading(BillOfLading bol) async {
    final db = await instance.database;
    return await db.insert('bill_of_ladings', bol.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// يبحث عن بوليصة بنفس الرقم لنفس العميل (بحث غير حساس لحالة الأحرف والمسافات)
  /// حتى تُربط كل المستندات الخاصة بنفس الشحنة مع بعضها بدل تكرارها.
  Future<BillOfLading?> findBillOfLading(String billNumber, String clientId) async {
    final db = await instance.database;
    final cleaned = billNumber.trim().toLowerCase();
    if (cleaned.isEmpty) return null;
    final result = await db.query('bill_of_ladings', where: 'clientId = ?', whereArgs: [clientId]);
    for (final row in result) {
      final existingNumber = (row['billNumber'] as String? ?? '').trim().toLowerCase();
      if (existingNumber == cleaned) {
        return BillOfLading.fromMap(row);
      }
    }
    return null;
  }

  Future<List<BillOfLading>> getBillOfLadings() async {
    final db = await instance.database;
    final result = await db.query('bill_of_ladings', orderBy: 'date DESC');
    return result.map((json) => BillOfLading.fromMap(json)).toList();
  }

  Future<List<BillOfLading>> getBillOfLadingsForClient(String clientId) async {
    final db = await instance.database;
    final result = await db.query(
      'bill_of_ladings',
      where: 'clientId = ?',
      whereArgs: [clientId],
      orderBy: 'date DESC',
    );
    return result.map((json) => BillOfLading.fromMap(json)).toList();
  }

  Future<BillOfLading?> getBillOfLadingById(String id) async {
    final db = await instance.database;
    final result = await db.query('bill_of_ladings', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return BillOfLading.fromMap(result.first);
  }

  // ---------------- Shipment Documents ----------------

  Future<int> insertShipmentDocument(ShipmentDocument doc) async {
    final db = await instance.database;
    return await db.insert('shipment_documents', doc.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ShipmentDocument>> getDocumentsForBillOfLading(String billOfLadingId) async {
    final db = await instance.database;
    final result = await db.query(
      'shipment_documents',
      where: 'billOfLadingId = ?',
      whereArgs: [billOfLadingId],
      orderBy: 'date ASC',
    );
    return result.map((json) => ShipmentDocument.fromMap(json)).toList();
  }

  // ---------------- Invoices + line items ----------------

  /// يحفظ الفاتورة مع كل بنودها (اسم البند + مبلغه) دفعة واحدة.
  /// يستبدل أي بنود سابقة لنفس الفاتورة (مفيد عند إعادة الحفظ/التعديل).
  Future<void> saveInvoiceWithItems(ClearanceInvoice invoice) async {
    final db = await instance.database;
    await db.insert('invoices', invoice.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('invoice_items', where: 'invoiceId = ?', whereArgs: [invoice.id]);
    for (final item in invoice.items) {
      await db.insert('invoice_items', {
        'id': const Uuid().v4(),
        'invoiceId': invoice.id,
        ...item.toMap(),
      });
    }
  }

  Future<int> insertInvoice(ClearanceInvoice invoice) async {
    final db = await instance.database;
    return await db.insert('invoices', invoice.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<InvoiceItem>> getItemsForInvoice(String invoiceId) async {
    final db = await instance.database;
    final result = await db.query('invoice_items', where: 'invoiceId = ?', whereArgs: [invoiceId]);
    return result.map((json) => InvoiceItem.fromMap(json)).toList();
  }

  Future<List<ClearanceInvoice>> getInvoices() async {
    final db = await instance.database;
    final result = await db.query('invoices', orderBy: 'date DESC');
    final invoices = result.map((json) => ClearanceInvoice.fromMap(json)).toList();
    for (final inv in invoices) {
      inv.items = await getItemsForInvoice(inv.id);
    }
    return invoices;
  }

  Future<List<ClearanceInvoice>> getInvoicesForBillOfLading(String billOfLadingId) async {
    final db = await instance.database;
    final result = await db.query(
      'invoices',
      where: 'billOfLadingId = ?',
      whereArgs: [billOfLadingId],
      orderBy: 'date ASC',
    );
    final invoices = result.map((json) => ClearanceInvoice.fromMap(json)).toList();
    for (final inv in invoices) {
      inv.items = await getItemsForInvoice(inv.id);
    }
    return invoices;
  }

  /// يُعيد الفاتورة الواحدة الموحّدة الخاصة بهذه البوليصة (فاتورة واحدة فقط
  /// لكل بوليصة تجمع كل الرسوم: موانئ + جمارك + أرضيات + إذن + أتعاب...الخ).
  /// إن وُجدت فواتير قديمة متعددة لنفس البوليصة (من نسخة سابقة من التطبيق)
  /// يتم دمج كل بنودها في فاتورة واحدة تلقائياً وحذف البقية، حتى لا تتكرر البيانات.
  /// إن لم توجد أي فاتورة بعد، تُنشأ فاتورة فارغة جديدة وتُعاد.
  Future<ClearanceInvoice> getOrCreateInvoiceForBillOfLading(
    String billOfLadingId, {
    required String clientId,
    required String clientName,
    required String billOfLading,
    String vesselName = '',
    int containerCount = 0,
    String declarationNo = '',
  }) async {
    final existingList = await getInvoicesForBillOfLading(billOfLadingId);
    final now = DateFormat('yyyy/MM/dd').format(DateTime.now());

    if (existingList.isEmpty) {
      final invoice = ClearanceInvoice(
        id: const Uuid().v4(),
        billOfLadingId: billOfLadingId,
        clientId: clientId,
        clientName: clientName,
        declarationNo: declarationNo,
        billOfLading: billOfLading,
        vesselName: vesselName,
        containerCount: containerCount,
        date: now,
        docTypes: const [],
        items: [],
      );
      await saveInvoiceWithItems(invoice);
      return invoice;
    }

    if (existingList.length == 1) {
      return existingList.first;
    }

    // دمج عدة فواتير قديمة لنفس البوليصة في فاتورة واحدة
    final primary = existingList.first;
    final allItems = <InvoiceItem>[...primary.items];
    double advance = primary.advancePayment;
    for (final extra in existingList.skip(1)) {
      allItems.addAll(extra.items);
      advance += extra.advancePayment;
      await deleteInvoice(extra.id);
    }
    primary.items = allItems;
    primary.advancePayment = advance;
    primary.recomputeCategoryTotals();
    await saveInvoiceWithItems(primary);
    return primary;
  }

  Future<void> deleteInvoice(String invoiceId) async {
    final db = await instance.database;
    await db.delete('invoice_items', where: 'invoiceId = ?', whereArgs: [invoiceId]);
    await db.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
  }

  /// يضيف بنداً جديداً (أو أكثر) إلى فاتورة موجودة، يعيد حساب إجماليات الفئات،
  /// ويحفظ الفاتورة. هذا هو الأسلوب المستخدم عند إضافة مستند ممسوح ضوئياً جديد
  /// أو عند إضافة أتعاب/رسوم يدوياً من داخل شاشة الفاتورة.
  Future<ClearanceInvoice> addItemsToInvoice(ClearanceInvoice invoice, List<InvoiceItem> newItems) async {
    invoice.items = [...invoice.items, ...newItems];
    for (final it in newItems) {
      if (!invoice.docTypes.contains(it.category)) {
        invoice.docTypes = [...invoice.docTypes, it.category];
      }
    }
    invoice.recomputeCategoryTotals();
    await saveInvoiceWithItems(invoice);
    return invoice;
  }

  // ---------------- Payments ----------------

  Future<int> insertPayment(Payment payment) async {
    final db = await instance.database;
    return await db.insert('payments', payment.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Payment>> getPaymentsForBillOfLading(String billOfLadingId) async {
    final db = await instance.database;
    final result = await db.query(
      'payments',
      where: 'billOfLadingId = ?',
      whereArgs: [billOfLadingId],
      orderBy: 'date ASC',
    );
    return result.map((json) => Payment.fromMap(json)).toList();
  }

  Future<double> getTotalPaymentsForBillOfLading(String billOfLadingId) async {
    final payments = await getPaymentsForBillOfLading(billOfLadingId);
    return payments.fold<double>(0, (sum, p) => sum + p.amount);
  }

  Future<int> deletePayment(String id) async {
    final db = await instance.database;
    return await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }
}
