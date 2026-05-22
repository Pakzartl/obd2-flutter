import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/ble_service.dart';
import 'ota_screen.dart';

class SystemScreen extends StatefulWidget {
  final BleService bleService;
  const SystemScreen({super.key, required this.bleService});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  static const _apiBase = 'https://adv350.pakzartl.xyz';
  String _appVersion = '...';
  String? _fwVersion;
  List<_ReleaseEntry> _appReleases = [];
  List<_ReleaseEntry> _fwReleases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;
    _fwVersion = await widget.bleService.readFirmwareVersion();

    try {
      final appRes = await http.get(Uri.parse('$_apiBase/api/firmware/latest?component=flutter-app'));
      final fwRes = await http.get(Uri.parse('$_apiBase/api/firmware/latest?component=firmware-s3'));

      if (appRes.statusCode == 200) {
        final d = jsonDecode(appRes.body);
        _appReleases = [_ReleaseEntry(d['version'], d['changelog'] ?? '', d['download_url'] ?? '')];
      }
      if (fwRes.statusCode == 200) {
        final d = jsonDecode(fwRes.body);
        _fwReleases = [_ReleaseEntry(d['version'], d['changelog'] ?? '', d['download_url'] ?? '')];
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  bool _isNewer(String remote, String current) {
    final r = remote.split('-').first.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final c = current.split('-').first.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (rv > cv) return true;
      if (rv < cv) return false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System'), backgroundColor: Colors.grey[900]),
      backgroundColor: Colors.grey[900],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _versionCard(
                  'App Version',
                  _appVersion,
                  _appReleases.isNotEmpty ? _appReleases.first.version : null,
                  _appReleases,
                  Icons.phone_android,
                  Colors.teal,
                  onUpdate: _appReleases.isNotEmpty &&
                          _isNewer(_appReleases.first.version, _appVersion)
                      ? () => _updateApp(_appReleases.first)
                      : null,
                ),
                const SizedBox(height: 12),
                _versionCard(
                  'Firmware (S3)',
                  _fwVersion ?? 'unknown',
                  _fwReleases.isNotEmpty ? _fwReleases.first.version : null,
                  _fwReleases,
                  Icons.developer_board,
                  Colors.orange,
                  onUpdate: _fwReleases.isNotEmpty &&
                          _fwVersion != null &&
                          _isNewer(_fwReleases.first.version, _fwVersion!)
                      ? () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => OtaScreen(bleService: widget.bleService)))
                      : null,
                ),
                const SizedBox(height: 24),
                Text('Release Notes',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_appReleases.isNotEmpty)
                  _releaseNote('App', _appReleases.first, Colors.teal),
                if (_fwReleases.isNotEmpty)
                  _releaseNote('Firmware', _fwReleases.first, Colors.orange),
              ],
            ),
    );
  }

  Widget _versionCard(String label, String current, String? latest,
      List<_ReleaseEntry> releases, IconData icon, Color color,
      {VoidCallback? onUpdate}) {
    final hasUpdate = latest != null && _isNewer(latest, current);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasUpdate ? color.withValues(alpha: 0.5) : Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const Spacer(),
            if (hasUpdate)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('UPDATE', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text('v$current', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            if (latest != null) ...[
              const SizedBox(width: 12),
              Text('→ v$latest',
                  style: TextStyle(
                      color: hasUpdate ? color : Colors.grey[600],
                      fontSize: 14, fontFamily: 'monospace')),
            ],
          ]),
          if (_appUpdating && label.contains('App')) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _appUpdateProgress, color: color),
            const SizedBox(height: 4),
            Text('${(_appUpdateProgress * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ] else if (onUpdate != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onUpdate,
                icon: const Icon(Icons.system_update, size: 16),
                label: const Text('Install Update'),
                style: FilledButton.styleFrom(backgroundColor: color),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _releaseNote(String component, _ReleaseEntry release, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
              child: Text(component, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text('v${release.version}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12, fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 8),
          Text(release.changelog.isEmpty ? 'No changelog' : release.changelog,
              style: TextStyle(color: Colors.grey[300], fontSize: 13)),
        ],
      ),
    );
  }

  bool _appUpdating = false;
  double _appUpdateProgress = 0;

  Future<void> _updateApp(_ReleaseEntry release) async {
    if (_appUpdating || release.downloadUrl.isEmpty) return;
    setState(() { _appUpdating = true; _appUpdateProgress = 0; });

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/app_update_${release.version}.apk';
      final file = File(savePath);

      if (!await file.exists()) {
        final cacheFiles = dir.listSync().where(
            (f) => f.path.contains('app_update_') && f.path.endsWith('.apk'));
        for (final f in cacheFiles) {
          try { await f.delete(); } catch (_) {}
        }

        final request = http.Request('GET', Uri.parse(release.downloadUrl));
        final response = await http.Client().send(request);
        final total = response.contentLength ?? 0;
        int received = 0;

        final sink = file.openWrite();
        await response.stream.map((chunk) {
          received += chunk.length;
          if (total > 0 && mounted) {
            setState(() => _appUpdateProgress = received / total);
          }
          return chunk;
        }).pipe(sink);
        await sink.close();
      }

      await OpenFile.open(savePath, type: 'application/vnd.android.package-archive');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _appUpdating = false);
    }
  }
}

class _ReleaseEntry {
  final String version;
  final String changelog;
  final String downloadUrl;
  _ReleaseEntry(this.version, this.changelog, this.downloadUrl);
}
