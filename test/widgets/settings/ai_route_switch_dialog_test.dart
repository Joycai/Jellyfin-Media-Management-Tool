import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/ai_channel.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_profiles_service.dart';
import 'package:jellyfin_media_management_tool/services/ai/ai_provider.dart';
import 'package:jellyfin_media_management_tool/services/ai/platform_profiles.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/ai_route_switch_dialog.dart';

import '../../helpers/settings.dart';

void main() {
  testWidgets('values the new route had before come back', (tester) async {
    useTempSupportDir();
    final model =
        AiModelEntry.create(
              upstream: 'gemini-2.5-pro',
              route: AiProviderType.googleGenAi,
            )
            .withCurrentParams(const RouteParams(maxOutputTokens: 4096))
            .switchedTo(AiProviderType.openAi)
            .withCurrentParams(const RouteParams(maxOutputTokens: 1234))
            .switchedTo(AiProviderType.googleGenAi);
    final channel =
        AiChannel.create(
          platform: PlatformProfiles.google,
          name: 'g',
          apiKey: 'k',
        ).copyWith(
          routes: const [
            AiRoute(protocol: AiProviderType.googleGenAi),
            AiRoute(protocol: AiProviderType.openAi),
          ],
          models: [model],
        );

    await pumpAiPage(
      tester,
      RouteSwitchDialog(
        channel: channel,
        model: model,
        to: AiProviderType.openAi,
      ),
      profiles: AiProfilesService(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('4096'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    // The target route was configured, so nothing reads as unset.
    expect(find.text('not set · not sent'), findsNothing);
  });
}
