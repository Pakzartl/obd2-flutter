# ADV350 OBD Flutter App

> **Flutter app** for Honda ADV350 OBD-II data logger
> **BLE** connection to ESP32-S3 relay board
> **SQLite** local storage + **Cloudflare D1** cloud sync

---

## Quick Start

```bash
flutter pub get
flutter run              # Debug build
flutter build apk --release
```

## Architecture

```
ESP32-S3 (BLE relay) ←BLE GATT→ Flutter App → SQLite → Cloudflare D1
```

**4-tab layout**: Ride (live gauges) | Trip (sparkline charts) | Vehicle (all sensors) | Dev (debug, OTA, cloud sync)

## Key Files

```
lib/
├── main.dart                    # Auto-connect, startup screen
├── models/
│   └── telemetry.dart           # Vehicle data decoder, raw_ble_hex
├── screens/
│   ├── scan_screen.dart         # BLE device scan
│   ├── dashboard_screen.dart    # 4-tab layout, telemetry stream
│   ├── tabs/
│   │   ├── ride_tab.dart        # Live speed, RPM, fuel hint
│   │   ├── trip_tab.dart        # Sparkline graphs, drag-to-zoom
│   │   ├── vehicle_tab.dart     # All sensor tiles
│   │   └── dev_tab.dart         # BLE mgmt, cloud sync, OTA
│   ├── ota_screen.dart          # Firmware update UI
│   ├── raw_log_screen.dart
│   └── history_screen.dart
└── services/
    ├── ble_service.dart         # GATT connect, notify, reconnect, OTA
    ├── database_service.dart    # SQLite CRUD (v8: timestamp index)
    ├── cloud_sync_service.dart  # D1 batch sync + auto-delete
    ├── ota_service.dart         # Firmware check + BLE OTA
    └── raw_backup_service.dart  # Daily JSONL raw data backup
```

## BLE Protocol

- **Service UUID**: `12345678-1234-5678-1234-56789abcdef0`
- **Vehicle data** (def3): 23 bytes — rpm, speed, coolant, throttle, MAP, IAT, fuel, CVT, score, board temp, engine load, STFT, lambda, braking
- **OTA** (def8): begin/data/end/abort
- **Mgmt** (def9): board info, clear logs, restart
- **FW version** (def7): version string

## Cloud API

```
Base: https://adv350.pakzartl.xyz

GET  /api/firmware/latest?component=firmware-s3   # Check firmware update
POST /api/telemetry                                # Batch upload (X-API-Key)
GET  /api/telemetry?since=&until=&limit=           # Query data
```

## Database

SQLite v8 — `telemetry` table with 18 columns + timestamp index.
After cloud sync, synced rows are auto-deleted from local.

## Performance Notes

- UI updates throttled to 4Hz (not every BLE packet)
- Trip tab: incremental query (only new rows), shouldRepaint with generation counter
- Trip tab only refreshes when active (isActive guard)
- Save interval: 0.5s (2Hz)
- Raw backup: daily file grouping

## BLE Reconnect

- Scan throttle: 6s min gap (Android rate-limit)
- Re-entry guard: _isReconnecting prevents nested loops
- systemDevices check: reuse OS connection on app restart
- Post-delay check in _tryReconnect prevents race condition

## Coding Conventions

- Dart/Flutter standard
- Debug builds until told otherwise
- Always store raw_ble_hex alongside decoded data
- Distance calculated from actual timestamp deltas between samples
