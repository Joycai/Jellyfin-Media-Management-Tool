import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/api_log.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('api_log_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ApiLog log() =>
      ApiLog(directory: dir, clock: () => DateTime(2026, 9, 19, 14, 2, 11))
        ..enabled = true;

  Future<List<Map<String, dynamic>>> read(ApiLog log) async {
    await log.flush();
    final file = log.currentFile!;
    return [
      for (final line in await file.readAsLines())
        jsonDecode(line) as Map<String, dynamic>,
    ];
  }

  test('writes one numbered line per request to a file per day', () async {
    final apiLog = log();
    for (var i = 0; i < 3; i++) {
      apiLog.record(
        protocol: 'chat',
        model: 'm',
        url: Uri.parse('http://localhost:1234/v1/chat/completions'),
        request: {'n': i},
        status: 200,
      );
    }

    final entries = await read(apiLog);
    expect(apiLog.currentFile!.path, endsWith('api-2026-09-19.jsonl'));
    expect(entries.map((e) => e['seq']), [1, 2, 3]);
    expect(entries.map((e) => (e['request'] as Map)['n']), [0, 1, 2]);
  });

  test('nothing is written while disabled', () async {
    final apiLog = log()..enabled = false;
    apiLog.record(
      protocol: 'chat',
      model: 'm',
      url: Uri.parse('http://x/'),
      request: const {},
    );
    await apiLog.flush();
    expect(await apiLog.currentFile!.exists(), isFalse);
  });

  test('never writes a credential from the URL', () async {
    final apiLog = log();
    apiLog.record(
      protocol: 'gemini',
      model: 'm',
      url: Uri.parse('https://user:pw@host:8443/v1beta/models/m?key=secret'),
      request: const {},
    );
    final entry = (await read(apiLog)).single;
    expect(entry['url'], 'https://host:8443/v1beta/models/m');

    apiLog.record(
      protocol: 'chat',
      model: 'm',
      url: Uri.parse('http://[::1]:1234/v1/chat/completions'),
      request: const {},
    );
    expect(
      (await read(apiLog)).last['url'],
      'http://[::1]:1234/v1/chat/completions',
    );
  });

  test('long strings and inline images become notes of their size', () {
    final long = 'x' * (ApiLog.maxString + 1);
    final redacted =
        ApiLog.redact({
              'messages': [
                {'content': long},
                {
                  'image_url': {'url': 'data:image/jpeg;base64,${'A' * 10}'},
                },
                {
                  'inlineData': {'mimeType': 'image/png', 'data': 'B' * 300},
                },
              ],
              'short': 'kept',
            })
            as Map;
    final messages = redacted['messages'] as List;
    expect((messages[0] as Map)['content'], contains('chars omitted'));
    expect(
      ((messages[1] as Map)['image_url'] as Map)['url'],
      startsWith('<inline data'),
    );
    expect(
      ((messages[2] as Map)['inlineData'] as Map)['data'],
      startsWith('<inline data'),
    );
    expect(redacted['short'], 'kept');
  });

  test('clear removes every log file', () async {
    final apiLog = log();
    apiLog.record(
      protocol: 'chat',
      model: 'm',
      url: Uri.parse('http://x/'),
      request: const {},
    );
    await apiLog.clear();
    expect(await dir.exists(), isFalse);
  });
}
