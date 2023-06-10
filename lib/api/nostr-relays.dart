import 'dart:convert';

import "package:http/http.dart" as http;
import 'package:locus/constants/apis.dart';
import 'package:locus/constants/values.dart';

Future<Map<String, dynamic>> getNostrRelays() async {
  final response = await http.get(Uri.parse(NOSTR_LIST_URI)).timeout(HTTP_TIMEOUT);

  return {
    "relays": List<String>.from(jsonDecode(response.body)),
  };
}
