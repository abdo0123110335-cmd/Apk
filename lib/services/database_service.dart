import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/client.dart';

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
      version: 1,
      onCreate: _createDB,
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
      CREATE TABLE invoices (
        id TEXT PRIMARY KEY,
        clientId TEXT,
        clientName TEXT,
        declarationNo TEXT,
        billOfLading TEXT,
        vesselName TEXT,
        date TEXT,
        portFeesTotal REAL,
        customsFeesTotal REAL,
        agencyFee REAL,
        transportFee REAL,
        miscFee REAL,
        advancePayment REAL
      )
    ''');
  }

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
}
