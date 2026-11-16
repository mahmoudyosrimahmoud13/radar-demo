import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/presence_event.dart';

/// Local SQLite log of every presence event, persisted on-device so the
/// Events and Analytics screens have history across app restarts.
class EventStore {
  static final EventStore instance = EventStore._();
  EventStore._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'radar_events.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            distanceCm INTEGER NOT NULL,
            angle INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<int> insert(PresenceEvent event) async {
    final database = await db;
    return database.insert('events', event.toMap()..remove('id'));
  }

  Future<List<PresenceEvent>> recent({int limit = 200}) async {
    final database = await db;
    final rows = await database.query(
      'events',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(PresenceEvent.fromMap).toList();
  }

  Future<List<PresenceEvent>> since(DateTime from) async {
    final database = await db;
    final rows = await database.query(
      'events',
      where: 'timestamp >= ?',
      whereArgs: [from.millisecondsSinceEpoch],
      orderBy: 'timestamp ASC',
    );
    return rows.map(PresenceEvent.fromMap).toList();
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('events');
  }
}
