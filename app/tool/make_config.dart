// Builds a config from a saved subscription body, for checking servers on the computer:
// dart run tool/make_config.dart <subscription file> <out.json> [port]
import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/subscription/links.dart';

void main(List<String> args) {
  final servers = Links.parseSubscription(File(args[0]).readAsStringSync());
  final config = ConfigBuilder.build(servers: servers, systemProxy: true, controlSecret: 'local', logLevel: 'info');
  // a plain local proxy here: the computer's own settings are not touched
  ((config['inbounds']! as List).single as Map)
    ..remove('set_system_proxy')
    ..['listen_port'] = int.parse(args.length > 2 ? args[2] : '2080');
  (config['dns']! as Map)['servers'] = [
    {'type': 'https', 'tag': 'remote', 'server': '1.1.1.1', 'detour': 'select'},
    {'type': 'local', 'tag': 'local'},
  ];
  File(args[1]).writeAsStringSync(jsonEncode(config));
  stdout.writeln('servers: ${servers.length}');
}
