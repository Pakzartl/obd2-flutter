import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BleTaskHandler());
}

class BleTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
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
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
      ),
    );
  }

  Future<void> start() async {
    init();
    await FlutterForegroundTask.requestNotificationPermission();
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: 'ADV350 Logger Active',
      notificationText: 'Recording telemetry...',
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
