import 'dart:io';
import 'package:path_provider/path_provider.dart';

class RawBackupService {
  IOSink? _sink;
  String? _currentPath;
  int _count = 0;

  String? get currentPath => _currentPath;
  int get count => _count;

  Future<void> startSession() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/raw_backup');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    await _migrateOldFiles(backupDir);
    final now = DateTime.now();
    final filename = '${now.year}-${_p(now.month)}-${_p(now.day)}.jsonl';
    _currentPath = '${backupDir.path}/$filename';
    _sink = File(_currentPath!).openWrite(mode: FileMode.append);
    _count = 0;
  }

  Future<void> _migrateOldFiles(Directory backupDir) async {
    final files = await backupDir.list().toList();
    final oldFiles = files
        .whereType<File>()
        .where((f) => RegExp(r'\d{8}_\d{6}\.jsonl$').hasMatch(f.path))
        .toList();
    if (oldFiles.isEmpty) return;

    final grouped = <String, List<File>>{};
    for (final f in oldFiles) {
      final name = f.path.split('/').last;
      final date = '${name.substring(0, 4)}-${name.substring(4, 6)}-${name.substring(6, 8)}';
      (grouped[date] ??= []).add(f);
    }

    for (final entry in grouped.entries) {
      final dailyPath = '${backupDir.path}/${entry.key}.jsonl';
      final dailySink = File(dailyPath).openWrite(mode: FileMode.append);
      for (final old in entry.value) {
        final content = await old.readAsString();
        if (content.isNotEmpty) dailySink.write(content);
        await old.delete();
      }
      await dailySink.flush();
      await dailySink.close();
    }
  }

  void writeRaw(List<int> bleBytes) {
    if (_sink == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final hex = bleBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    _sink!.writeln('{"ts":$ts,"hex":"$hex","len":${bleBytes.length}}');
    _count++;
    // Flush every 50 packets — survive app crash/kill
    if (_count % 50 == 0) {
      _sink!.flush();
    }
  }

  Future<void> endSession() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  Future<List<FileSystemEntity>> listBackups() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/raw_backup');
    if (!await backupDir.exists()) return [];
    final files = await backupDir.list().toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}
