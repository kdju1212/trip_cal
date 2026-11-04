import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'domain.dart';

class Storage {
  Storage(this.db);
  final Database db;
  static Future<Storage> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(path ?? join(await f.getDatabasesPath(), 'trip_cal.db'),
      options: OpenDatabaseOptions(version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE trips (id INTEGER PRIMARY KEY, name TEXT NOT NULL, country TEXT NOT NULL, departure TEXT, budget TEXT NOT NULL)');
          await db.execute('CREATE TABLE expenses (id INTEGER PRIMARY KEY, trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE, name TEXT NOT NULL, category TEXT NOT NULL, amount TEXT NOT NULL, currency TEXT NOT NULL, rate TEXT NOT NULL, won TEXT NOT NULL, rate_date TEXT, rate_source TEXT)');
          await db.execute('CREATE TABLE checklist (id INTEGER PRIMARY KEY, trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE, name TEXT NOT NULL, checked INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT "직접 추가")');
          await _createV2(db);
        },
        onUpgrade: (db, old, version) async {
          if (old < 2) {
            await db.execute('ALTER TABLE checklist ADD COLUMN category TEXT NOT NULL DEFAULT "직접 추가"');
            await _createV2(db);
          }
        }));
    return Storage(db);
  }
  static Future<void> _createV2(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE rates (currency TEXT PRIMARY KEY, rate TEXT NOT NULL, date TEXT NOT NULL, source TEXT NOT NULL)');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute('CREATE TABLE purchases (trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE, item TEXT NOT NULL, needed INTEGER NOT NULL, PRIMARY KEY (trip_id,item))');
    await db.execute('CREATE INDEX expenses_trip ON expenses(trip_id)');
    await db.execute('CREATE INDEX checklist_trip ON checklist(trip_id)');
  }
  Future<List<DbRow>> trips() => db.query('trips', orderBy: 'id DESC');
  Future<List<DbRow>> expenses(int id) => db.query('expenses', where: 'trip_id = ?', whereArgs: [id], orderBy: 'id DESC');
  Future<List<DbRow>> checklist(int id) => db.query('checklist', where: 'trip_id = ?', whereArgs: [id], orderBy: 'id');
  void _validateTrip(DbRow trip) {
    if (trip.containsKey('name') && (trip['name'] as String).trim().isEmpty) throw const FormatException('여행 이름을 입력해 주세요.');
    if (trip.containsKey('country')) countryByCode(trip['country']! as String);
    if (trip.containsKey('budget') && !RegExp(r'^\d+$').hasMatch(trip['budget']! as String)) throw const FormatException('예산은 0 이상이어야 합니다.');
  }
  Future<int> createTrip(DbRow trip) => db.transaction((txn) async {
    _validateTrip(trip);
    final id = await txn.insert('trips', trip);
    final groups = {...defaultItems};
    if (trip['country'] != 'KR') {
      for (final e in overseasItems.entries) {
        groups[e.key] = [...?groups[e.key], ...e.value];
      }
    }
    for (final group in groups.entries) {
      for (final name in group.value) {
        await txn.insert('checklist', {'trip_id': id, 'name': name, 'category': group.key});
      }
    }
    return id;
  });
  Future<void> updateTrip(int id, DbRow trip) async {
    _validateTrip(trip);
    await db.update('trips', trip, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> deleteTrip(int id) async {
    await db.transaction((txn) async {
      await txn.delete('trips', where: 'id = ?', whereArgs: [id]);
      // Manual selection must not silently point to a different trip.
      final s = await txn.query('settings', where: 'key = ?', whereArgs: ['notificationTrip']);
      if (s.isNotEmpty && s.first['value'] == jsonEncode(id)) {
        await txn.insert('settings', {'key': 'notificationEnabled', 'value': 'false'}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
  Future<int> duplicateTrip(int id) => db.transaction((txn) async {
    final original = (await txn.query('trips', where: 'id = ?', whereArgs: [id])).single;
    final copy = Map<String, Object?>.from(original)..remove('id');
    copy['name'] = '${copy['name']} (복사)';
    final newId = await txn.insert('trips', copy);
    for (final table in ['expenses', 'checklist', 'purchases']) {
      final rows = await txn.query(table, where: 'trip_id = ?', whereArgs: [id]);
      for (final row in rows) {
        final data = Map<String, Object?>.from(row)..remove('id');
        data['trip_id'] = newId;
        await txn.insert(table, data);
      }
    }
    return newId;
  });
  Future<void> saveExpense(int tripId, DbRow row, {int? id}) async {
    // Validate again at the persistence boundary; ignore caller-provided won.
    if ((row['name']! as String).trim().isEmpty || (row['category']! as String).trim().isEmpty) throw const FormatException('경비 이름과 카테고리를 입력해 주세요.');
    final currency = row['currency']! as String;
    final rate = currency == 'KRW' ? '1' : row['rate']! as String;
    final won = convertToWon(row['amount']! as String, rate, fractionDigits: currencyInfo(currency).fractionDigits);
    final data = {...row, 'trip_id': tripId, 'rate': rate, 'won': won.toString()};
    if (id == null) { await db.insert('expenses', data); }
    else { await db.update('expenses', data, where: 'id = ? AND trip_id = ?', whereArgs: [id, tripId]); }
  }
  Future<void> recalculate(int tripId, List<DbRow> preview) => db.transaction((txn) async {
    for (final row in preview) {
      final current = await txn.query('expenses', where: 'id = ? AND trip_id = ?', whereArgs: [row['id'], tripId]);
      if (current.isEmpty || current.single['amount'] != row['amount'] || current.single['currency'] != row['currency']) {
        throw const FormatException('경비가 변경되었습니다. 환율 재계산을 다시 실행해 주세요.');
      }
      final currency = row['currency']! as String;
      final won = convertToWon(row['amount']! as String, row['rate']! as String, fractionDigits: currencyInfo(currency).fractionDigits);
      await txn.update('expenses', {'rate': row['rate'], 'won': won.toString(), 'rate_date': row['rate_date'], 'rate_source': row['rate_source']}, where: 'id = ? AND trip_id = ?', whereArgs: [row['id'], tripId]);
    }
  });
  Future<T> setting<T>(String key, T fallback) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return fallback;
    return jsonDecode(rows.single['value']! as String) as T;
  }
  Future<void> setSetting(String key, Object value) async {
    await db.insert('settings', {'key': key, 'value': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
