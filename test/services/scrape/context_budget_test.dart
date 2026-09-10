import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/token_budget.dart';
import 'package:jellyfin_media_management_tool/services/scrape/direct_extractor.dart';
import 'package:jellyfin_media_management_tool/services/scrape/recipe_learner.dart';

import '../../helpers/ai.dart';

const _window = 4096;

const _small = AiConfig(
  provider: AiProviderType.openAi,
  endpoint: 'http://localhost:1234',
  apiKey: '',
  model: 'small-local-model',
  contextWindow: _window,
);

final _url = Uri.parse('https://example.com/product/1');

/// A product page many times larger than a 4K window: a long table of markup
/// and a long Japanese synopsis.
final _page =
    '''
<html><body>
<h1 class="title">作品タイトル</h1>
${'<div class="row"><span class="label">出演</span><span class="value">名前</span></div>\n' * 2000}
<p class="plot">${'あらすじの本文。' * 4000}</p>
</body></html>''';

int _sent(ScriptedProvider provider, int call) =>
    TokenBudget.estimate(provider.systemPrompts[call]) +
    TokenBudget.estimate(provider.userPrompts[call]);

void main() {
  test('direct extraction trims the page to the window', () async {
    final provider = ScriptedProvider(['{"title": "作品タイトル"}'], config: _small);

    await DirectExtractor(
      provider,
    ).extract(document: html_parser.parse(_page), pageUrl: _url);

    expect(_sent(provider, 0), lessThan(_window));
  });

  test('without a window the page goes at its natural size', () async {
    final provider = ScriptedProvider(['{"title": "作品タイトル"}']);

    await DirectExtractor(
      provider,
    ).extract(document: html_parser.parse(_page), pageUrl: _url);

    expect(_sent(provider, 0), greaterThan(_window));
  });

  test('recipe learning trims the skeleton on every attempt', () async {
    final provider = ScriptedProvider(['not a recipe'], config: _small);

    await RecipeLearner(
      provider,
    ).learn(html: _page, document: html_parser.parse(_page), pageUrl: _url);

    expect(provider.calls, RecipeLearner.maxAttempts);
    for (var call = 0; call < provider.calls; call++) {
      expect(_sent(provider, call), lessThan(_window));
    }
  });
}
