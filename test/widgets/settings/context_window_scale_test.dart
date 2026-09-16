import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/widgets/settings/context_window_scale.dart';

/// The feel of the context slider lives entirely in this arithmetic, and
/// "does it stop exactly on 128k?" is not a question you can settle by
/// dragging.
void main() {
  group('ContextWindowScale', () {
    test('the eight segments are evenly spaced, not linear in tokens', () {
      // 8k–1M is a 128x range. Linear would squash 8k–32k, where local models
      // actually sit, into the leftmost 2% of the track.
      expect(ContextWindowScale.positionOf(8192), 0);
      expect(ContextWindowScale.positionOf(1048576), 1);
      expect(ContextWindowScale.positionOf(65536), closeTo(3 / 8, 1e-9));
      expect(ContextWindowScale.positionOf(131072), closeTo(5 / 8, 1e-9));

      // Half of the 8k–16k segment is 12k — a linear scale would put 12k at
      // 0.4% of the track instead of 6.25%.
      expect(ContextWindowScale.positionOf(12288), closeTo(0.5 / 8, 1e-9));
    });

    test('a position round-trips back to its tick', () {
      for (final tick in ContextWindowScale.ticks) {
        expect(
          ContextWindowScale.tokensAt(ContextWindowScale.positionOf(tick)),
          tick,
        );
      }
    });

    test('values within 2k of a tick snap to it', () {
      expect(ContextWindowScale.snap(130048), 131072); // 128k − 1k
      expect(ContextWindowScale.snap(133120), 131072); // 128k + 2k
      // 3k away is a deliberate value, not a near miss.
      expect(ContextWindowScale.snap(134144), 134144);
    });

    test('typed values align down to 1k and clamp to the ends', () {
      expect(ContextWindowScale.align(100000), 99328); // floor, not nearest
      expect(ContextWindowScale.align(10), ContextWindowScale.min);
      expect(ContextWindowScale.align(9999999), ContextWindowScale.max);
    });

    test('page up and down move one whole segment', () {
      expect(ContextWindowScale.nextTick(65536, up: true), 98304);
      expect(ContextWindowScale.nextTick(70000, up: false), 65536);
      // At the ends there is nowhere further to go.
      expect(ContextWindowScale.nextTick(1048576, up: true), 1048576);
      expect(ContextWindowScale.nextTick(8192, up: false), 8192);
    });

    test('display rounds to k, and 1024k reads as 1M', () {
      expect(ContextWindowScale.format(8192), '8k');
      expect(ContextWindowScale.format(131072), '128k');
      expect(ContextWindowScale.format(1048576), '1M');
      // The field itself always shows raw tokens, for comparing against a
      // server config line by line.
      expect(ContextWindowScale.grouped(131072), '131,072');
    });
  });

  group('MaxOutputScale', () {
    test('caps at half the context window and steps by 256', () {
      expect(MaxOutputScale.clamp(3000, contextWindow: 131072), 3072);
      expect(MaxOutputScale.clamp(100000, contextWindow: 131072), 65536);
      expect(MaxOutputScale.clamp(1, contextWindow: 131072), 256);
    });

    test('with no context window there is nothing to cap against', () {
      // Blank context means "send everything" — the server decides, so the
      // app must not invent a ceiling of its own.
      expect(MaxOutputScale.ceilingFor(null), isNull);
      expect(MaxOutputScale.clamp(100000, contextWindow: null), 100096);
    });
  });
}
