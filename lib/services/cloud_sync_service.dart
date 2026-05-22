import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/telemetry.dart';
import 'database_service.dart';

class CloudSyncService {
  static const String _apiBase = 'https://adv350.pakzartl.xyz';
  static const int _batchSize = 100;
  static const Duration _interval = Duration(seconds: 30);

  final DatabaseService _db;
  String _apiKey = '';
  Timer? _timer;
  bool _syncing = false;
  int _lastSyncedCount = 0;
  String? _lastError;

  CloudSyncService(this._db);

  int get lastSyncedCount => _lastSyncedCount;
  String? get lastError => _lastError;
  bool get isRunning => _timer != null;

  void configure({required String apiKey}) {
    _apiKey = apiKey;
  }

  void startPeriodic() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => syncOnce());
    syncOnce();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<int> syncOnce() async {
    if (_syncing || _apiKey.isEmpty) return 0;
    _syncing = true;
    _lastError = null;
    int totalSynced = 0;

    try {
      while (true) {
        final rows = await _db.getUnsynced(limit: _batchSize);
        if (rows.isEmpty) break;

        final payload = {
          'device_id': 'adv350-01',
          'rows': rows.map((t) => {
            'rpm': t.rpm,
            'speed': t.speed,
            'throttle': t.throttle,
            'coolant_temp': t.coolantTemp,
            'map_kpa': t.mapKpa,
            'iat': t.iat,
            'engine_load': t.engineLoad,
            'ignition_timing': t.ignitionTiming,
            'raw_ble_hex': t.rawBleHex,
            'fuel_rate_lph': t.fuelRateLph,
            'cvt_ratio': t.cvtRatio,
            'riding_score': t.ridingScore,
            'board_temp': t.boardTemp,
            'distance_m': t.distanceM,
            'recorded_at': t.timestamp.toUtc().toIso8601String(),
          }).toList(),
        };

        final res = await http.post(
          Uri.parse('$_apiBase/api/telemetry'),
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': _apiKey,
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final ids = rows.where((t) => t.id != null).map((t) => t.id!).toList();
          await _db.markSynced(ids);
          totalSynced += ids.length;
        } else {
          _lastError = 'HTTP ${res.statusCode}: ${res.body}';
          break;
        }
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _syncing = false;
      _lastSyncedCount += totalSynced;
    }
    return totalSynced;
  }

  Future<int> restoreFromCloud({
    void Function(int fetched, int inserted)? onProgress,
  }) async {
    if (_apiKey.isEmpty) throw Exception('API key not set');
    _lastError = null;
    int totalInserted = 0;
    int totalFetched = 0;
    String? cursor;

    await _db.deleteSyncedRows();

    try {
      while (true) {
        var url = '$_apiBase/api/telemetry?device_id=adv350-01&limit=1000';
        if (cursor != null) url += '&until=$cursor';

        final res = await http.get(
          Uri.parse(url),
          headers: {'X-API-Key': _apiKey},
        ).timeout(const Duration(seconds: 30));

        if (res.statusCode != 200) {
          _lastError = 'HTTP ${res.statusCode}';
          break;
        }

        final data = jsonDecode(res.body);
        final rows = data['rows'] as List;
        if (rows.isEmpty) break;

        totalFetched += rows.length;
        int batchInserted = 0;

        for (final row in rows) {
          final recordedAt = row['recorded_at'] as String?;
          if (recordedAt == null) continue;
          final ts = DateTime.parse(recordedAt);
          final exists = await _db.existsAtTimestamp(ts);
          if (exists) continue;

          final t = _cloudRowToTelemetry(row, ts);
          await _db.insertTelemetry(t);
          batchInserted++;
        }

        totalInserted += batchInserted;
        onProgress?.call(totalFetched, totalInserted);

        final lastRecordedAt = rows.last['recorded_at'] as String?;
        if (lastRecordedAt == null || rows.length < 1000) break;
        cursor = lastRecordedAt;
      }
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }
    return totalInserted;
  }

  Telemetry _cloudRowToTelemetry(Map<String, dynamic> row, DateTime ts) {
    return Telemetry(
      rpm: (row['rpm'] as num?)?.toInt() ?? 0,
      speed: (row['speed'] as num?)?.toInt() ?? 0,
      throttle: (row['throttle'] as num?)?.toInt() ?? 0,
      coolantTemp: (row['coolant_temp'] as num?)?.toInt() ?? 0,
      mapKpa: (row['map_kpa'] as num?)?.toInt() ?? 0,
      iat: (row['iat'] as num?)?.toInt() ?? 0,
      engineLoad: (row['engine_load'] as num?)?.toInt() ?? 0,
      ignitionTiming: (row['ignition_timing'] as num?)?.toInt() ?? 0,
      rawBleHex: (row['raw_ble_hex'] as String?) ?? '',
      fuelRateLph: (row['fuel_rate_lph'] as num?)?.toDouble() ?? 0,
      cvtRatio: (row['cvt_ratio'] as num?)?.toDouble() ?? 0,
      ridingScore: (row['riding_score'] as num?)?.toInt() ?? 0,
      boardTemp: (row['board_temp'] as num?)?.toInt() ?? 0,
      distanceM: (row['distance_m'] as num?)?.toDouble() ?? 0,
      timestamp: ts,
      synced: true,
    );
  }

  void dispose() {
    stop();
  }
}
