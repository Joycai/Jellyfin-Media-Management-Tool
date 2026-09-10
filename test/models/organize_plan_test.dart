import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/organize_plan.dart';

OrganizeAction _action(double confidence, {ActionStatus? status}) =>
    OrganizeAction(
      source: 'e1.mkv',
      target: 'Shows/S/e1.mkv',
      kind: 'video',
      confidence: confidence,
      note: '',
      status: status,
    );

void main() {
  test('an action below 0.6 confidence starts out needing review', () {
    // ApplyController skips these, so a doubtful move never runs unseen.
    expect(_action(0.59).status, ActionStatus.needsReview);
    expect(_action(0.6).status, ActionStatus.pending);
  });

  test('an explicit status wins over the confidence rule', () {
    expect(
      _action(0.1, status: ActionStatus.pending).status,
      ActionStatus.pending,
    );
  });

  test('totalTokens adds both halves', () {
    final plan = OrganizePlan(
      mediaType: 'series',
      targetRoot: 'Shows',
      reasoning: const [],
      actions: const [],
      promptTokens: 120,
      completionTokens: 30,
    );
    expect(plan.totalTokens, 150);
  });
}
