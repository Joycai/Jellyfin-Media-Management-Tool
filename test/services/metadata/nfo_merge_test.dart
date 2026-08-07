import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/metadata/nfo_merge.dart';

MediaMetadata _existing() => MediaMetadata(
  title: 'Hand-written Title',
  plot: 'A plot someone corrected by hand.',
  genres: ['Action'],
  studio: 'GIGA',
  origins: {
    MetadataField.title: FieldOrigin.existingNfo,
    MetadataField.plot: FieldOrigin.existingNfo,
  },
);

MediaMetadata _scraped({FieldOrigin origin = FieldOrigin.recipe}) {
  final m = MediaMetadata();
  m.set(MetadataField.title, 'Scraped Title', origin);
  m.set(MetadataField.plot, 'A scraped plot.', origin);
  m.set(MetadataField.code, 'SPSF-43', origin);
  m.set(MetadataField.genres, ['Action', 'Drama'], origin);
  m.set(MetadataField.studio, 'GIGA', origin);
  m.sourceUrl = 'https://example.invalid/p/1';
  return m;
}

void main() {
  group('suggest', () {
    test('fills a blank field automatically', () {
      // Adding information is safe, so a field the NFO does not have is taken
      // without asking.
      final plan = NfoMerge.suggest(_existing(), _scraped());
      expect(plan.decisionFor(MetadataField.code), MergeDecision.replace);
      expect(plan.newFields, contains(MetadataField.code));
    });

    test('keeps a conflicting scalar field', () {
      // Replacing information is a judgement call, so it defaults to no.
      final plan = NfoMerge.suggest(_existing(), _scraped());
      expect(plan.decisionFor(MetadataField.title), MergeDecision.keep);
      expect(plan.decisionFor(MetadataField.plot), MergeDecision.keep);
      expect(plan.conflictFields, contains(MetadataField.title));
    });

    test('merges list fields by default', () {
      final plan = NfoMerge.suggest(_existing(), _scraped());
      expect(plan.decisionFor(MetadataField.genres), MergeDecision.merge);
    });

    test('never lets an LLM guess overwrite an existing value', () {
      final plan = NfoMerge.suggest(
        _existing(),
        _scraped(origin: FieldOrigin.llm),
      );
      expect(plan.decisionFor(MetadataField.title), MergeDecision.keep);
      // Even for list fields, where the default would otherwise be merge.
      expect(plan.decisionFor(MetadataField.genres), MergeDecision.keep);
    });

    test('identical values produce no decision at all', () {
      // <studio> is the same on both sides; showing it as a conflict would be
      // noise in the preview.
      final plan = NfoMerge.suggest(_existing(), _scraped());
      expect(plan.decisions.containsKey(MetadataField.studio), isFalse);
      expect(plan.conflictFields, isNot(contains(MetadataField.studio)));
    });

    test('with no existing NFO everything is a new field', () {
      final plan = NfoMerge.suggest(null, _scraped());
      expect(plan.conflictFields, isEmpty);
      for (final decision in plan.decisions.values) {
        expect(decision, MergeDecision.replace);
      }
    });
  });

  group('presets', () {
    test('fillEmptyOnly takes new fields and leaves conflicts alone', () {
      final plan = NfoMerge.suggest(
        _existing(),
        _scraped(),
      ).withPreset(MergePreset.fillEmptyOnly);
      expect(plan.decisionFor(MetadataField.code), MergeDecision.replace);
      expect(plan.decisionFor(MetadataField.title), MergeDecision.keep);
      expect(plan.decisionFor(MetadataField.genres), MergeDecision.keep);
    });

    test('replaceAll and keepAll are absolute', () {
      final base = NfoMerge.suggest(_existing(), _scraped());
      for (final d
          in base.withPreset(MergePreset.replaceAll).decisions.values) {
        expect(d, MergeDecision.replace);
      }
      for (final d in base.withPreset(MergePreset.keepAll).decisions.values) {
        expect(d, MergeDecision.keep);
      }
    });
  });

  group('resolve', () {
    test('applies the default plan', () {
      final existing = _existing();
      final scraped = _scraped();
      final out = NfoMerge.resolve(
        existing,
        scraped,
        NfoMerge.suggest(existing, scraped),
      );

      expect(out.title, 'Hand-written Title'); // conflict -> kept
      expect(out.plot, 'A plot someone corrected by hand.');
      expect(out.code, 'SPSF-43'); // was blank -> filled
      expect(out.genres, ['Action', 'Drama']); // merged, existing first
    });

    test('honours a per-field override', () {
      final existing = _existing();
      final scraped = _scraped();
      final plan = NfoMerge.suggest(
        existing,
        scraped,
      ).withDecision(MetadataField.title, MergeDecision.replace);

      expect(NfoMerge.resolve(existing, scraped, plan).title, 'Scraped Title');
    });

    test('merging a list de-duplicates and preserves order', () {
      final existing = MediaMetadata(genres: ['B', 'A']);
      final scraped = MediaMetadata()
        ..set(MetadataField.genres, ['A', 'C'], FieldOrigin.recipe);
      final out = NfoMerge.resolve(
        existing,
        scraped,
        NfoMerge.suggest(existing, scraped),
      );
      expect(out.genres, ['B', 'A', 'C']);
    });

    test('does not mutate the inputs', () {
      final existing = _existing();
      final scraped = _scraped();
      NfoMerge.resolve(
        existing,
        scraped,
        NfoMerge.suggest(existing, scraped).withPreset(MergePreset.replaceAll),
      );
      expect(existing.title, 'Hand-written Title');
      expect(existing.genres, ['Action']);
    });

    test('provenance always follows the newest scrape', () {
      final existing = _existing();
      final scraped = _scraped();
      final out = NfoMerge.resolve(
        existing,
        scraped,
        NfoMerge.suggest(existing, scraped).withPreset(MergePreset.keepAll),
      );
      expect(out.sourceUrl, 'https://example.invalid/p/1');
    });
  });
}
