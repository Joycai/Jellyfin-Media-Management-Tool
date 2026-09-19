import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/model_parameter_cards.dart';

import '../../helpers/settings.dart';

void main() {
  testWidgets('the model parameter cards lay out', (tester) async {
    final maxOutput = TextEditingController();
    addTearDown(maxOutput.dispose);
    await pumpAiPage(
      tester,
      Column(
        children: [
          ContextWindowCard(
            value: 131072,
            onChanged: (_) {},
            detectedCeiling: null,
          ),
          MaxOutputCard(
            controller: maxOutput,
            onChanged: () {},
            contextWindow: 131072,
          ),
        ],
      ),
      profiles: AiProfilesService(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('131,072'), findsOneWidget);
    // The tick labels read in k/M, while the field keeps raw tokens.
    expect(find.text('128k'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
  });

  testWidgets('max output is clamped when the field is left', (tester) async {
    final maxOutput = TextEditingController();
    addTearDown(maxOutput.dispose);
    var changes = 0;
    await pumpAiPage(
      tester,
      MaxOutputCard(
        controller: maxOutput,
        onChanged: () => changes++,
        contextWindow: 8192,
      ),
      profiles: AiProfilesService(),
    );

    await tester.enterText(find.byType(TextField), '999999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Half the context window at most.
    expect(int.parse(maxOutput.text), lessThanOrEqualTo(4096));
    expect(changes, greaterThan(0));
  });
}
