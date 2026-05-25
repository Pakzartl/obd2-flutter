import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BleTaskHandler());
}

class BleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      final devices = FlutterBluePlus.connectedDevices;
      final hasAdv350 = devices.any((d) => d.platformName.startsWith('ADV350'));
      
      final text = hasAdv350
          ? 'Connected — recording telemetry...'
          : 'Disconnected — attempting reconnect...';

      await FlutterForegroundTask.updateService(
        notificationTitle: 'ADV350 Logger Active',
        notificationText: text,
      );

      FlutterForegroundTask.sendDataToMain(hasAdv350);
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class ForegroundService {
  ForegroundService._();
  static final instance = ForegroundService._();

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ble_logger',
        channelName: 'ADV350 BLE Logger',
        channelDescription: 'Keeps BLE connection alive for telemetry recording',
        onlyAlertOnce: true,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
      ),
    );
  }

  Future<void> start({bool connected = true}) async {
    init();
    await FlutterForegroundTask.requestNotificationPermission();

    final text = connected
        ? 'Connected — recording telemetry...'
        : 'Disconnected — attempting reconnect...';

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'ADV350 Logger Active',
        notificationText: text,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'ADV350 Logger Active',
      notificationText: text,
      callback: startCallback,
    );
  }

  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  bool get isRunning => FlutterForegroundTask.isRunningService is Future
      ? false
      : false;
}
