import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/learned_behaviour.dart';

void main() {
  test('the route key never holds the API key', () {
    final key = LearnedStore.routeKey(
      protocol: 'openai',
      base: 'https://api.example.com/v1',
      model: 'm',
      apiKey: 'sk-very-secret',
    );
    expect(key, isNot(contains('sk-very-secret')));
    expect(
      key,
      LearnedStore.routeKey(
        protocol: 'openai',
        base: 'https://api.example.com/v1',
        model: 'm',
        apiKey: ' sk-very-secret ',
      ),
    );
    expect(
      key,
      isNot(
        LearnedStore.routeKey(
          protocol: 'openai',
          base: 'https://api.example.com/v1',
          model: 'm',
          apiKey: 'sk-other',
        ),
      ),
    );
  });

  test('what was learned survives a reload', () async {
    final dir = await Directory.systemTemp.createTemp('learned_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ai_learned.json');

    final store = LearnedStore();
    await store.load(file);
    store.update(
      'r',
      (b) => b.copyWith(
        jsonMode: 'schema',
        rejectedFields: {'top_k'},
        thinkingOffTried: {'templateKwargs'},
        maxCompletionTokens: true,
      ),
    );
    await store.save();

    final reloaded = LearnedStore();
    await reloaded.load(file);
    final learned = reloaded.of('r');
    expect(learned.jsonMode, 'schema');
    expect(learned.rejectedFields, {'top_k'});
    expect(learned.thinkingOffTried, {'templateKwargs'});
    expect(learned.maxCompletionTokens, isTrue);
  });

  test('an entry older than the maximum age is forgotten', () async {
    var now = DateTime(2026, 9, 1);
    final store = LearnedStore(clock: () => now);
    store.update('r', (b) => b.copyWith(jsonMode: 'none'));
    expect(store.of('r').jsonMode, 'none');

    now = now.add(LearnedStore.maxAge + const Duration(days: 1));
    expect(store.of('r').isEmpty, isTrue);
  });

  test('an unchanged memory keeps its date, so it still expires', () {
    var now = DateTime(2026, 9, 1);
    final store = LearnedStore(clock: () => now)
      ..update('r', (b) => b.copyWith(jsonMode: 'object'));
    now = now.add(const Duration(days: 20));
    // Re-learning the same thing on every request must not keep it alive.
    store.update('r', (b) => b.copyWith(jsonMode: 'object'));
    expect(store.of('r').updated, DateTime(2026, 9, 1));
    now = now.add(const Duration(days: 11));
    expect(store.of('r').isEmpty, isTrue);
  });

  test('user info in an endpoint never reaches the key', () {
    final key = LearnedStore.routeKey(
      protocol: 'openai',
      base: 'https://alice:hunter2@relay.example.com/v1',
      model: 'm',
      apiKey: '',
    );
    expect(key, isNot(contains('hunter2')));
    expect(key, contains('https://relay.example.com/v1'));
  });

  test('forget drops a route', () {
    final store = LearnedStore()
      ..update('r', (b) => b.copyWith(rejectedFields: {'min_p'}));
    store.forget('r');
    expect(store.of('r').isEmpty, isTrue);
  });

  test('an unreadable file is an empty store', () async {
    final dir = await Directory.systemTemp.createTemp('learned_bad');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ai_learned.json')
      ..writeAsStringSync('{not json');
    final store = LearnedStore();
    await store.load(file);
    expect(store.entries, isEmpty);
  });
}
