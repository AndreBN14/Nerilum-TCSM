import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:synchronized/synchronized.dart';

import '../../domain/models/pending_analysis.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/repositories/pending_analysis_repository.dart';

/// Los metadatos están en SQLCipher y los bytes en archivos AES-GCM privados.
class EncryptedPendingAnalysisRepository implements PendingAnalysisRepository {
  EncryptedPendingAnalysisRepository({
    FlutterSecureStorage? keyStorage,
    this._rootOverride,
    this._testDatabaseOpener,
    this._testKey,
  }) : _keyStorage = keyStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _keyStorage;
  final Directory? _rootOverride;
  final Future<Database> Function(
    String,
    String,
    Future<void> Function(Database, int),
  )?
  _testDatabaseOpener;
  final List<int>? _testKey;
  final _cipher = AesGcm.with256bits();
  final _lock = Lock();
  Database? _db;
  Future<Database>? _opening;
  Directory? _folder;
  SecretKey? _key;

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null && db.isOpen) await db.close();
  }

  Future<Database> _open() =>
      _opening ??= _initialize().catchError((Object error) {
        _opening = null;
        throw error;
      });

  Future<Database> _initialize() async {
    if (_db != null) return _db!;
    final root = _rootOverride ?? await getApplicationSupportDirectory();
    final folder = Directory(p.join(root.path, 'nerilum_pending'));
    final dbPath = p.join(folder.path, 'pending.db');
    final stored = _testKey == null
        ? await _keyStorage.read(key: 'nerilum_pending_key_v1')
        : null;
    if (_testKey == null && stored == null && await File(dbPath).exists()) {
      throw StateError(
        'La clave local ya no está disponible; no se abrirá una base existente.',
      );
    }
    final random = Random.secure();
    final keyBytes =
        _testKey ??
        (stored == null
            ? List<int>.generate(32, (_) => random.nextInt(256))
            : base64Decode(stored));
    if (keyBytes.length != 32) throw StateError('Clave local inválida');
    if (stored == null && _testKey == null) {
      await _keyStorage.write(
        key: 'nerilum_pending_key_v1',
        value: base64Encode(keyBytes),
      );
    }
    await folder.create(recursive: true);
    Future<void> create(Database database, int version) async {
      await database.execute('''
          CREATE TABLE pending_analyses (
            id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, filename TEXT NOT NULL,
            extension TEXT NOT NULL, image_sha256 TEXT NOT NULL,
            image_size INTEGER NOT NULL, created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending', preview_id TEXT,
            save_proof TEXT, proof_expires_at TEXT, display_name TEXT
          )
        ''');
      await database.execute(
        'CREATE INDEX pending_owner ON pending_analyses(owner_id, status, created_at)',
      );
    }

    final db = _testDatabaseOpener == null
        ? await openDatabase(
            dbPath,
            password: base64Encode(keyBytes),
            version: 1,
            onCreate: create,
          )
        : await _testDatabaseOpener(dbPath, base64Encode(keyBytes), create);
    final version = _testDatabaseOpener == null
        ? await db.rawQuery('PRAGMA cipher_version')
        : [
            <String, Object?>{'test': 'ffi'},
          ];
    if (version.isEmpty) {
      await db.close();
      throw StateError('La base de pendientes no tiene SQLCipher disponible.');
    }
    _folder = folder;
    _key = SecretKey(keyBytes);
    _db = db;
    await _reconcile(db);
    return db;
  }

  Future<void> _reconcile(Database db) async {
    final rows = await db.query('pending_analyses', columns: ['id', 'status']);
    final ids = rows.map((row) => row['id'] as String).toSet();
    await for (final entry in _folder!.list()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (name.endsWith('.tmp') ||
          (name.endsWith('.enc') &&
              !ids.contains(name.substring(0, name.length - 4)))) {
        await entry.delete();
      }
    }
    for (final row in rows) {
      final id = row['id'] as String;
      if (row['status'] != 'saving' && !await _imageFile(id).exists()) {
        await db.update(
          'pending_analyses',
          {'status': 'failed'},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  String _hex(List<int> data) =>
      data.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  File _imageFile(String id) => File(p.join(_folder!.path, '$id.enc'));

  PendingAnalysis _parse(Map<String, Object?> row) => PendingAnalysis(
    id: row['id']! as String,
    ownerId: row['owner_id']! as String,
    filename: row['filename']! as String,
    extension: row['extension']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    status: row['status']! as String,
    previewId: row['preview_id'] as String?,
    saveProof: row['save_proof'] as String?,
    proofExpiresAt: row['proof_expires_at'] == null
        ? null
        : DateTime.parse(row['proof_expires_at']! as String),
    displayName: row['display_name'] as String?,
  );

  @override
  Future<PendingAnalysis> enqueue(String ownerId, SelectedImage image) async {
    if (ownerId.isEmpty ||
        image.bytes.isEmpty ||
        image.bytes.length > 10 * 1024 * 1024 ||
        !['jpg', 'jpeg', 'png'].contains(image.extension.toLowerCase())) {
      throw ArgumentError('Imagen o propietario inválido');
    }
    return _lock.synchronized(() async {
      final db = await _open();
      final count = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM pending_analyses WHERE owner_id = ?',
          [ownerId],
        ),
      )!;
      if (count >= 10) {
        throw StateError('Máximo de diez pendientes por cuenta.');
      }
      final id = const Uuid().v4();
      final date = DateTime.now().toUtc();
      final hash = _hex((await Sha256().hash(image.bytes)).bytes);
      final box = await _cipher.encrypt(image.bytes, secretKey: _key!);
      final temporary = File(p.join(_folder!.path, '$id.tmp'));
      try {
        await temporary.writeAsBytes(box.concatenation(), flush: true);
        await temporary.rename(_imageFile(id).path);
        await db.insert('pending_analyses', {
          'id': id,
          'owner_id': ownerId,
          'filename': image.name,
          'extension': image.extension,
          'image_sha256': hash,
          'image_size': image.bytes.length,
          'created_at': date.toIso8601String(),
          'status': 'pending',
        });
        return PendingAnalysis(
          id: id,
          ownerId: ownerId,
          filename: image.name,
          extension: image.extension,
          createdAt: date,
          status: 'pending',
        );
      } catch (_) {
        if (await temporary.exists()) await temporary.delete();
        final file = _imageFile(id);
        if (await file.exists()) await file.delete();
        rethrow;
      }
    });
  }

  @override
  Future<List<PendingAnalysis>> list(String ownerId) async {
    final db = await _open();
    final expired = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final old = await db.query(
      'pending_analyses',
      columns: ['id'],
      where: "owner_id = ? AND status = 'pending' AND created_at < ?",
      whereArgs: [ownerId, expired.toIso8601String()],
    );
    for (final row in old) {
      await discard(ownerId, row['id']! as String);
    }
    final rows = await db.query(
      'pending_analyses',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_parse).toList(growable: false);
  }

  @override
  Future<PendingAnalysis?> find(String ownerId, String id) async {
    final db = await _open();
    final rows = await db.query(
      'pending_analyses',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : _parse(rows.single);
  }

  @override
  Future<SelectedImage> image(String ownerId, String id) async {
    final db = await _open();
    final rows = await db.query(
      'pending_analyses',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Pendiente no encontrado');
    final data = await _imageFile(id).readAsBytes();
    late final List<int> clear;
    try {
      final box = SecretBox.fromConcatenation(
        data,
        nonceLength: 12,
        macLength: 16,
      );
      clear = await _cipher.decrypt(box, secretKey: _key!);
    } catch (_) {
      throw StateError('Imagen cifrada alterada');
    }
    if (_hex((await Sha256().hash(clear)).bytes) !=
            rows.single['image_sha256'] ||
        clear.length != rows.single['image_size']) {
      throw StateError('Imagen cifrada alterada');
    }
    return SelectedImage(
      name: rows.single['filename']! as String,
      extension: rows.single['extension']! as String,
      bytes: Uint8List.fromList(clear),
    );
  }

  @override
  Future<void> discard(String ownerId, String id) async {
    final db = await _open();
    final deleted = await db.delete(
      'pending_analyses',
      where: "owner_id = ? AND id = ? AND status != 'saving'",
      whereArgs: [ownerId, id],
    );
    if (deleted == 0) throw StateError('No se puede descartar este pendiente.');
    final file = _imageFile(id);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> resetPreview(String ownerId, String id) async {
    final db = await _open();
    await db.update(
      'pending_analyses',
      {
        'status': 'pending',
        'preview_id': null,
        'save_proof': null,
        'proof_expires_at': null,
        'display_name': null,
      },
      where: "owner_id = ? AND id = ? AND status != 'saving'",
      whereArgs: [ownerId, id],
    );
  }

  @override
  Future<void> releaseExpiredSave(String ownerId, String id) async {
    final db = await _open();
    await db.update(
      'pending_analyses',
      {
        'status': 'pending',
        'preview_id': null,
        'save_proof': null,
        'proof_expires_at': null,
        'display_name': null,
      },
      where: "owner_id = ? AND id = ? AND status = 'saving'",
      whereArgs: [ownerId, id],
    );
  }

  @override
  Future<void> beginSave(
    String ownerId,
    String id, {
    required String previewId,
    required String proof,
    required DateTime expiresAt,
    required String name,
  }) async {
    final db = await _open();
    final updated = await db.update(
      'pending_analyses',
      {
        'status': 'saving',
        'preview_id': previewId,
        'save_proof': proof,
        'proof_expires_at': expiresAt.toUtc().toIso8601String(),
        'display_name': name,
      },
      where: "owner_id = ? AND id = ? AND status = 'pending'",
      whereArgs: [ownerId, id],
    );
    if (updated != 1) throw StateError('El pendiente cambió de estado.');
  }

  @override
  Future<void> complete(String ownerId, String id) async {
    final db = await _open();
    final rows = await db.query(
      'pending_analyses',
      columns: ['id'],
      where: "owner_id = ? AND id = ? AND status = 'saving'",
      whereArgs: [ownerId, id],
    );
    if (rows.isEmpty) return;
    final file = _imageFile(id);
    if (await file.exists()) await file.delete();
    await db.delete(
      'pending_analyses',
      where: 'owner_id = ? AND id = ?',
      whereArgs: [ownerId, id],
    );
  }
}
