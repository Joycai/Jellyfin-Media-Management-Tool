import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/widgets/file_browser/media_columns.dart';

double _sum(Map<MediaColumn, double> m) => m.values.fold(0.0, (a, b) => a + b);

void main() {
  group('resolve', () {
    test('splits the width in proportion to the weights', () {
      final widths = MediaColumnLayout.resolve(940, MediaColumnLayout.defaults);

      // Defaults total 94, so a 940px table gives 10px per unit.
      expect(widths[MediaColumn.name], closeTo(320, 0.01));
      expect(widths[MediaColumn.type], closeTo(100, 0.01));
      expect(widths[MediaColumn.confidence], closeTo(160, 0.01));
      expect(_sum(widths), closeTo(940, 0.01));
    });

    test('always fills exactly the width it was given', () {
      // The table has no horizontal scroll, so any shortfall is a visible gap
      // and any excess is an overflow stripe.
      for (final available in [420.0, 700.0, 1600.0]) {
        expect(
          _sum(
            MediaColumnLayout.resolve(available, MediaColumnLayout.defaults),
          ),
          closeTo(available, 0.01),
          reason: 'at $available px',
        );
      }
    });

    test('a starved column is pulled up to the minimum', () {
      final widths = MediaColumnLayout.resolve(900, {
        MediaColumn.name: 200,
        MediaColumn.type: 1,
        MediaColumn.size: 1,
        MediaColumn.suggestion: 1,
        MediaColumn.confidence: 1,
      });

      for (final column in MediaColumn.values) {
        expect(
          widths[column],
          greaterThanOrEqualTo(MediaColumnLayout.minWidth - 0.01),
          reason: '$column',
        );
      }
      expect(_sum(widths), closeTo(900, 0.01));
    });

    test('a table too narrow for the minimums shares out what there is', () {
      // Better a cramped table than a RenderFlex overflow.
      final widths = MediaColumnLayout.resolve(100, MediaColumnLayout.defaults);
      expect(_sum(widths), closeTo(100, 0.01));
      expect(widths.values, everyElement(closeTo(20, 0.01)));
    });

    test('zero width does not divide by anything', () {
      expect(
        MediaColumnLayout.resolve(0, MediaColumnLayout.defaults).values,
        everyElement(0.0),
      );
    });
  });

  group('sanitize', () {
    test('fills in a column an older build never wrote', () {
      final weights = MediaColumnLayout.sanitize({MediaColumn.name: 40});
      expect(weights[MediaColumn.name], 40);
      expect(
        weights[MediaColumn.size],
        MediaColumnLayout.defaults[MediaColumn.size],
      );
    });

    test('rejects values a hand-edited config could contain', () {
      final weights = MediaColumnLayout.sanitize({
        MediaColumn.name: 0,
        MediaColumn.type: -5,
        MediaColumn.size: double.nan,
        MediaColumn.suggestion: double.infinity,
      });

      for (final column in MediaColumn.values) {
        expect(weights[column], MediaColumnLayout.defaults[column]);
      }
    });

    test('null is simply the defaults', () {
      expect(MediaColumnLayout.sanitize(null), MediaColumnLayout.defaults);
    });
  });

  group('resize', () {
    Map<MediaColumn, double> drag(double dx, {double available = 940}) =>
        MediaColumnLayout.resize(
          weights: MediaColumnLayout.defaults,
          column: MediaColumn.name,
          dx: dx,
          available: available,
        );

    test('a drag moves width from one column to its neighbour', () {
      // 30px, comfortably inside what Type can spare — the clamp is the next
      // test's job.
      final after = MediaColumnLayout.resolve(940, drag(30));

      expect(after[MediaColumn.name], closeTo(320 + 30, 0.01));
      expect(after[MediaColumn.type], closeTo(100 - 30, 0.01));
      // Nothing else moves, and the table still fills its width.
      expect(after[MediaColumn.suggestion], closeTo(260, 0.01));
      expect(_sum(after), closeTo(940, 0.01));
    });

    test('dragging left gives width back', () {
      final after = MediaColumnLayout.resolve(940, drag(-40));
      expect(after[MediaColumn.name], closeTo(280, 0.01));
      expect(after[MediaColumn.type], closeTo(140, 0.01));
    });

    test('the neighbour cannot be pushed below the minimum', () {
      // Type starts at 100px, so it can give up at most 100 - 56 = 44.
      final after = MediaColumnLayout.resolve(940, drag(500));

      expect(
        after[MediaColumn.type],
        closeTo(MediaColumnLayout.minWidth, 0.01),
      );
      expect(after[MediaColumn.name], closeTo(320 + 44, 0.01));
      expect(_sum(after), closeTo(940, 0.01));
    });

    test('the dragged column cannot be pushed below the minimum either', () {
      final after = MediaColumnLayout.resolve(940, drag(-500));
      expect(
        after[MediaColumn.name],
        closeTo(MediaColumnLayout.minWidth, 0.01),
      );
      expect(_sum(after), closeTo(940, 0.01));
    });

    test('the last column has no divider to drag', () {
      // There is nothing to its right to trade with, so a stray drag is a
      // no-op rather than a silent redistribution.
      expect(
        MediaColumnLayout.resize(
          weights: MediaColumnLayout.defaults,
          column: MediaColumn.confidence,
          dx: 40,
          available: 940,
        ),
        MediaColumnLayout.defaults,
      );
    });

    test('many small drags land where one big drag would', () {
      // A drag arrives as a stream of deltas, so the increments have to sum
      // cleanly or the column would drift away from the cursor.
      var weights = MediaColumnLayout.defaults;
      for (var i = 0; i < 20; i++) {
        weights = MediaColumnLayout.resize(
          weights: weights,
          column: MediaColumn.name,
          dx: 2,
          available: 940,
        );
      }

      expect(
        MediaColumnLayout.resolve(940, weights)[MediaColumn.name],
        closeTo(360, 0.01),
      );
    });

    test('a zero-width table does not produce NaN', () {
      final after = MediaColumnLayout.resize(
        weights: MediaColumnLayout.defaults,
        column: MediaColumn.name,
        dx: 10,
        available: 0,
      );
      expect(after.values, everyElement(isNot(isNaN)));
    });
  });
}
