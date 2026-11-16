import 'dart:convert';
import 'dart:io' show Platform;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/presence_event.dart';

/// Local SQLite log of every presence event, persisted on-device so the
/// Events and Analytics screens have history across app restarts.
class EventStore {
  static final EventStore instance = EventStore._();
  EventStore._();

  // sqflite has no Linux desktop support, so the Linux build keeps the
  // event log as JSON in shared_preferences (newest 5000 events).
  static final bool _useJson = Platform.isLinux;
  static const _jsonKey = 'events_json';
  static const _jsonCap = 5000;
  List<PresenceEvent>? _jsonCache;

  Future<List<PresenceEvent>> _jsonAll() async {
    if (_jsonCache != null) return _jsonCache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_jsonKey);
      final list = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
      _jsonCache = list.map((e) => PresenceEvent.fromMap(Map<String, Object?>.from(e as Map))).toList();
    } catch (_) {
      _jsonCache = <PresenceEvent>[];
    }
    return _jsonCache!;
  }

  Future<void> _jsonSave() async {
    final all = _jsonCache ?? <PresenceEvent>[];
    if (all.length > _jsonCap) all.removeRange(0, all.length - _jsonCap);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jsonKey, jsonEncode(all.map((e) => e.toMap()).toList()));
  }

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
    if (_useJson) {
      final all = await _jsonAll();
      final id = DateTime.now().microsecondsSinceEpoch;
      all.add(PresenceEvent(
        id: id,
        type: event.type,
        timestamp: event.timestamp,
        distanceCm: event.distanceCm,
        angle: event.angle,
      ));
      await _jsonSave();
      return id;
    }
    final database = await db;
    return database.insert('events', event.toMap()..remove('id'));
  }

  Future<List<PresenceEvent>> recent({int limit = 200}) async {
    if (_useJson) {
      final all = List<PresenceEvent>.of(await _jsonAll())
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return all.take(limit).toList();
    }
    final database = await db;
    final rows = await database.query(
      'events',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(PresenceEvent.fromMap).toList();
  }

  Future<List<PresenceEvent>> since(DateTime from) async {
    if (_useJson) {
      final all = (await _jsonAll()).where((e) => !e.timestamp.isBefore(from)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return all;
    }
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
    if (_useJson) {
      _jsonCache = <PresenceEvent>[];
      await _jsonSave();
      return;
    }
    final database = await db;
    await database.delete('events');
  }
}
