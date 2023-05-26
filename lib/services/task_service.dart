import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:locus/api/nostr-events.dart';
import 'package:locus/constants/app.dart';
import 'package:locus/models/log.dart';
import 'package:locus/services/log_service.dart';
import 'package:locus/utils/cryptography.dart';
import 'package:nostr/nostr.dart';
import 'package:uuid/uuid.dart';

import '../api/get-locations.dart' as getLocationsAPI;
import 'location_point_service.dart';
import 'timers_service.dart';

const storage = FlutterSecureStorage();
const KEY = "tasks_settings";
const SAME_TIME_THRESHOLD = Duration(minutes: 15);

enum TaskLinkPublishProgress {
  startsSoon,
  encrypting,
  publishing,
  creatingURI,
  done,
}

const uuid = Uuid();

class Task extends ChangeNotifier {
  final String id;
  final DateTime createdAt;

  // Password for symmetric encryption of the locations
  final SecretKey _encryptionPassword;

  final String nostrPrivateKey;
  final List<String> relays;
  final List<TaskRuntimeTimer> timers;
  String name;
  bool deleteAfterRun;

  Task({
    required this.id,
    required this.name,
    required this.createdAt,
    required SecretKey encryptionPassword,
    required this.nostrPrivateKey,
    required this.relays,
    required this.timers,
    this.deleteAfterRun = false,
  }) : _encryptionPassword = encryptionPassword;

  factory Task.fromJSON(Map<String, dynamic> json) {
    return Task(
      id: json["id"],
      name: json["name"],
      encryptionPassword: SecretKey(List<int>.from(json["encryptionPassword"])),
      nostrPrivateKey: json["nostrPrivateKey"],
      createdAt: DateTime.parse(json["createdAt"]),
      relays: List<String>.from(json["relays"]),
      deleteAfterRun: json["deleteAfterRun"] == "true",
      timers: List<TaskRuntimeTimer>.from(json["timers"].map((timer) {
        switch (timer["_IDENTIFIER"]) {
          case WeekdayTimer.IDENTIFIER:
            return WeekdayTimer.fromJSON(timer);
          case DurationTimer.IDENTIFIER:
            return DurationTimer.fromJSON(timer);
          default:
            throw Exception("Unknown timer type");
        }
      })),
    );
  }

  String get taskKey => "Task:$id";

  String get scheduleKey => "Task:$id:Schedule";

  String get nostrPublicKey => Keychain(nostrPrivateKey).public;

  Future<Map<String, dynamic>> toJSON() async {
    return {
      "id": id,
      "name": name,
      "encryptionPassword": await _encryptionPassword.extractBytes(),
      "nostrPrivateKey": nostrPrivateKey,
      "createdAt": createdAt.toIso8601String(),
      "relays": relays,
      "timers": timers.map((timer) => timer.toJSON()).toList(),
      "deleteAfterRun": deleteAfterRun.toString(),
    };
  }

  static Future<Task> create(
    final String name,
    final List<String> relays, {
    List<TaskRuntimeTimer> timers = const [],
    bool deleteAfterRun = false,
  }) async {
    final secretKey = await generateSecretKey();

    return Task(
      id: uuid.v4(),
      name: name,
      encryptionPassword: secretKey,
      nostrPrivateKey: Keychain.generate().private,
      relays: relays,
      createdAt: DateTime.now(),
      timers: timers,
      deleteAfterRun: deleteAfterRun,
    );
  }

  Future<bool> isRunning() async {
    final status = await getExecutionStatus();

    return status != null;
  }

  Future<Map<String, dynamic>?> getExecutionStatus() async {
    final rawData = await storage.read(key: taskKey);

    if (rawData == null || rawData == "") {
      return null;
    }

    final data = jsonDecode(rawData);

    return {
      ...data,
      "startedAt": DateTime.parse(data["startedAt"]),
    };
  }

  Future<Map<String, dynamic>?> getScheduleStatus() async {
    final rawData = await storage.read(key: scheduleKey);

    if (rawData == null || rawData == "") {
      return null;
    }

    final data = jsonDecode(rawData);

    return {
      ...data,
      "startedAt": DateTime.parse(data["startedAt"]),
      "startsAt": DateTime.parse(data["startsAt"]),
    };
  }

  DateTime? nextStartDate({final DateTime? date}) => findNextStartDate(timers, startDate: date);

  DateTime? nextEndDate() => findNextEndDate(timers);

  bool isInfinite() => timers.any((timer) => timer.isInfinite());

  Future<bool> shouldRunNow() async {
    final executionStatus = await getExecutionStatus();
    final shouldRunNowBasedOnTimers = timers.any((timer) => timer.shouldRun(DateTime.now()));

    if (shouldRunNowBasedOnTimers) {
      return true;
    }

    if (executionStatus != null) {
      final earliestNextRun = nextStartDate(date: executionStatus["startedAt"]);

      if (earliestNextRun == null) {
        return false;
      }

      return (executionStatus["startedAt"] as DateTime).isBefore(earliestNextRun);
    }

    return false;
  }

  Future<void> stopSchedule() async {
    await storage.delete(key: scheduleKey);
  }

  // Starts the task. This will schedule the task to run at the next expected time.
  // You can find out when the task will run by calling `nextStartDate`.
  // Returns the next start date of the task OR `null` if the task is not scheduled to run.
  Future<DateTime?> startSchedule({
    final bool startNowIfNextRunIsUnknown = false,
    final DateTime? startDate,
  }) async {
    final now = startDate ?? DateTime.now();
    DateTime? nextStartDate = this.nextStartDate(date: now);

    if (nextStartDate == null) {
      if (startNowIfNextRunIsUnknown) {
        nextStartDate = now;
      } else {
        return null;
      }
    }

    final isNow = nextStartDate.subtract(SAME_TIME_THRESHOLD).isBefore(now);

    if (isNow) {
      await startExecutionImmediately();
    } else {
      await stopSchedule();

      await storage.write(
        key: scheduleKey,
        value: jsonEncode({
          "startedAt": DateTime.now().toIso8601String(),
          "startsAt": nextStartDate.toIso8601String(),
        }),
      );
    }

    return nextStartDate;
  }

  // Starts the schedule tomorrow morning. This should be used when the user manually stops the execution of the task, but
  // still wants the task to run at the next expected time. If `startSchedule` is used, the schedule might start,
  // immediately, which is not what the user wants.
  // Returns the next date the task will run OR `null` if the task is not scheduled to run.
  Future<DateTime?> startScheduleTomorrow() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final nextDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6, 0, 0);

    return startSchedule(startDate: nextDate);
  }

  // Starts the actual execution of the task. You should only call this if either the user wants to manually start the
  // task or if the task is scheduled to run.
  Future<void> startExecutionImmediately() async {
    await storage.write(
      key: taskKey,
      value: jsonEncode({
        "startedAt": DateTime.now().toIso8601String(),
      }),
    );

    await stopSchedule();

    for (final timer in timers) {
      timer.executionStarted();
    }

    notifyListeners();
  }

  // Stops the actual execution of the task. You should only call this if either the user wants to manually stop the
  // task or if the task is scheduled to stop.
  Future<void> stopExecutionImmediately() async {
    await storage.delete(key: taskKey);

    for (final timer in timers) {
      timer.executionStopped();
    }

    notifyListeners();
  }

  Future<void> update({
    String? name,
    List<String>? relays,
    List<TaskRuntimeTimer>? timers,
    bool? deleteAfterRun,
  }) async {
    if (name != null) {
      this.name = name;
    }

    if (relays != null) {
      this.relays.clear();
      this.relays.addAll(relays);
    }

    if (timers != null) {
      this.timers.clear();
      this.timers.addAll(timers);
    }

    if (deleteAfterRun != null) {
      this.deleteAfterRun = deleteAfterRun;
    }

    notifyListeners();
  }

  Future<String> generateViewKeyContent() async {
    return jsonEncode({
      "encryptionPassword": await _encryptionPassword.extractBytes(),
      "nostrPublicKey": nostrPublicKey,
      "relays": relays,
    });
  }

  // Generates a link that can be used to retrieve the task
  // This link is primarily used for sharing the task to the web app
  // Here's the process:
  // 1. Generate a random password
  // 2. Encrypt the task with the password
  // 3. Publish the encrypted task to a random Nostr relay
  // 4. Generate a link that contains the password and the Nostr relay ID
  Future<String> generateLink({
    final void Function(TaskLinkPublishProgress progress)? onProgress,
  }) async {
    onProgress?.call(TaskLinkPublishProgress.startsSoon);

    final message = await generateViewKeyContent();

    onProgress?.call(TaskLinkPublishProgress.encrypting);

    final passwordSecretKey = await generateSecretKey();
    final password = await passwordSecretKey.extractBytes();
    final cipherText = await encryptUsingAES(message, passwordSecretKey);

    onProgress?.call(TaskLinkPublishProgress.publishing);

    final relay = relays[Random().nextInt(relays.length)];
    final manager = NostrEventsManager(
      relays: [relay],
      privateKey: nostrPrivateKey,
    );
    final publishedEvent = await manager.publishMessage(cipherText, kind: 1001);

    onProgress?.call(TaskLinkPublishProgress.creatingURI);

    final parameters = {
      // Password
      "p": password,
      // Key
      "k": nostrPublicKey,
      // ID
      "i": publishedEvent.id,
      // Relay
      "r": relay,
    };

    final fragment = base64Url.encode(jsonEncode(parameters).codeUnits);
    final uri = Uri(
      scheme: "https",
      host: APP_URL_DOMAIN,
      path: "/",
      fragment: fragment,
    );

    onProgress?.call(TaskLinkPublishProgress.done);
    passwordSecretKey.destroy();

    return uri.toString();
  }

  Future<void> publishCurrentLocationNow([
    final LocationPointService? location,
  ]) async {
    final eventManager = NostrEventsManager.fromTask(this);
    final locationPoint = location ?? await LocationPointService.createUsingCurrentLocation();

    final rawMessage = jsonEncode(locationPoint.toJSON());
    final message = await encryptUsingAES(rawMessage, _encryptionPassword);

    await eventManager.publishMessage(message);
  }

  Future<void Function()> getLocations({
    required void Function(LocationPointService) onLocationFetched,
    required void Function() onEnd,
    bool onlyLatestPosition = false,
    DateTime? from,
  }) =>
      getLocationsAPI.getLocations(
        encryptionPassword: _encryptionPassword,
        nostrPublicKey: nostrPublicKey,
        relays: relays,
        onLocationFetched: onLocationFetched,
        onEnd: onEnd,
        from: from,
        onlyLatestPosition: onlyLatestPosition,
      );

  @override
  void dispose() {
    _encryptionPassword.destroy();

    super.dispose();
  }
}

class TaskService extends ChangeNotifier {
  final List<Task> _tasks;

  TaskService({
    required List<Task> tasks,
  }) : _tasks = tasks;

  UnmodifiableListView<Task> get tasks => UnmodifiableListView(_tasks);

  static Future<TaskService> restore() async {
    final rawTasks = await storage.read(key: KEY);

    if (rawTasks == null) {
      return TaskService(
        tasks: [],
      );
    }

    return TaskService(
      tasks: List<Task>.from(
        List<Map<String, dynamic>>.from(
          jsonDecode(rawTasks),
        ).map(
          Task.fromJSON,
        ),
      ).toList(),
    );
  }

  Future<void> save() async {
    // await all `toJson` functions
    final data = await Future.wait<Map<String, dynamic>>(
      _tasks.map(
        (task) => task.toJSON(),
      ),
    );

    await storage.write(key: KEY, value: jsonEncode(data));
  }

  Task getByID(final String id) {
    return _tasks.firstWhere((task) => task.id == id);
  }

  void add(Task task) {
    _tasks.add(task);

    notifyListeners();
  }

  void remove(final Task task) {
    task.stopExecutionImmediately();
    _tasks.remove(task);

    notifyListeners();
  }

  void update(final Task task) {
    final index = _tasks.indexWhere((element) => element.id == task.id);

    _tasks[index] = task;

    notifyListeners();
    save();
  }

  // Does a general check up state of the task.
  // Checks if the task should be running / should be deleted etc.
  Future<void> checkup(final LogService logService) async {
    for (final task in tasks) {
      if (!task.isInfinite() && task.nextEndDate() == null) {
        // Delete task
        remove(task);
        await save();

        await logService.addLog(
          Log.deleteTask(
            initiator: LogInitiator.system,
            taskName: task.name,
          ),
        );
      } else if (!(await task.shouldRunNow()) && (await task.isRunning())) {
        await task.stopExecutionImmediately();

        await logService.addLog(
          Log.taskStatusChanged(
            initiator: LogInitiator.system,
            taskId: task.id,
            taskName: task.name,
            active: false,
          ),
        );
      }
    }
  }

  Stream<Task> getRunningTasks() async* {
    for (final task in tasks) {
      if (await task.isRunning()) {
        yield task;
      }
    }
  }
}

class TaskExample {
  final String name;
  final List<TaskRuntimeTimer> timers;
  final bool realtime;

  const TaskExample({
    required this.name,
    required this.timers,
    this.realtime = false,
  });
}

DateTime? findNextStartDate(final List<TaskRuntimeTimer> timers,
    {final DateTime? startDate, final bool onlyFuture = true}) {
  final now = startDate ?? DateTime.now();

  final nextDates = timers
      .map((timer) => timer.nextStartDate(now))
      .where((date) => date != null && (date.isAfter(now) || date == now))
      .toList(growable: false);

  if (nextDates.isEmpty) {
    return null;
  }

  // Find earliest date
  nextDates.sort();
  return nextDates.first;
}

DateTime? findNextEndDate(final List<TaskRuntimeTimer> timers, {final DateTime? startDate}) {
  final now = startDate ?? DateTime.now();
  final nextDates = List<DateTime>.from(
    timers.map((timer) => timer.nextEndDate(now)).where((date) => date != null),
  )..sort();

  DateTime endDate = nextDates.first;

  for (final date in nextDates.sublist(1)) {
    final nextStartDate = findNextStartDate(timers, startDate: date);
    if (nextStartDate == null || nextStartDate.difference(date).inMinutes.abs() > 15) {
      // No next start date found or the difference is more than 15 minutes, so this is the last date
      break;
    }
    endDate = date;
  }

  return endDate;
}
