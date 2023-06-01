import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:locus/services/location_point_service.dart';
import 'package:nostr/nostr.dart';

Future<WebSocket> openSocket({
  required final String url,
  required final Request request,
  required final SecretKey encryptionPassword,
  required void Function(LocationPointService) onLocationFetched,
  required void Function() onEnd,
}) async {
  final List<Future<LocationPointService>> decryptionProcesses = [];

  bool hasReceivedEvent = false;
  bool hasReceivedEndOfStream = false;

  final socket = await WebSocket.connect(url);

  socket.add(request.serialize());

  socket.listen((rawEvent) {
    final event = Message.deserialize(rawEvent);

    switch (event.type) {
      case "EVENT":
        hasReceivedEvent = true;

        final locationProcess = LocationPointService.fromEncrypted(
          event.message.content,
          encryptionPassword,
        );

        decryptionProcesses.add(locationProcess);

        locationProcess.then((location) {
          onLocationFetched(location);
          decryptionProcesses.remove(locationProcess);

          if (decryptionProcesses.isEmpty && hasReceivedEndOfStream) {
            onEnd();
          }
        });

        break;
      case "EOSE":
        socket.close();

        hasReceivedEndOfStream = true;

        if ((decryptionProcesses.isEmpty && hasReceivedEvent) ||
            !hasReceivedEvent) {
          onEnd();
        }
        break;
    }
  });

  return socket;
}

Future<void Function()> getLocations({
  required final String nostrPublicKey,
  required final SecretKey encryptionPassword,
  required final List<String> relays,
  required void Function(LocationPointService) onLocationFetched,
  required void Function() onEnd,
  bool onlyLatestPosition = false,
  DateTime? from,
}) async {
  final request = Request(generate64RandomHexChars(), [
    Filter(
      kinds: [1000],
      authors: [nostrPublicKey],
      limit: onlyLatestPosition ? 1 : null,
      since: from == null ? null : (from.millisecondsSinceEpoch / 1000).floor(),
    ),
  ]);

  final List<String> existingIDs = [];

  final List<WebSocket> socketProcesses = [];

  for (final relay in relays) {
    final socketProcess = openSocket(
      url: relay,
      request: request,
      encryptionPassword: encryptionPassword,
      onLocationFetched: (final LocationPointService location) {
        if (existingIDs.contains(location.id)) {
          return;
        }

        existingIDs.add(location.id);

        onLocationFetched(location);
      },
      onEnd: () {},
    )..then(socketProcesses.add);
  }

  return () async {
    for (final socketProcess in socketProcesses) {
      final socket = await socketProcess;

      socket.close();
    }
  };
}
