import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/rename_service.dart';

/// rename_service.dart had no test at all, and CLAUDE.md singles out one of
/// its rules as worth preserving: baseNameForTarget has to walk *past* the
/// Season NN / Specials container folders up to the series folder, or a TV
/// rename produces `Season 01.S01E01.mkv`. That rule is asserted here so it
/// cannot be lost quietly.
///
/// Paths use forward separators on purpose: the service resolves through the
/// ambient `path` context, and `/` is understood on every platform while `\\`
/// is not understood on POSIX CI.
void main() {
  group('buildName', () {
    test('matchFolder is the base name plus the extension', () {
      expect(
        RenameService.buildName('Dune', '.mkv', RenameRule.matchFolder),
        'Dune.mkv',
      );
    });

    test('featurette and interview suffix with a dash', () {
      expect(
        RenameService.buildName('Dune', '.mkv', RenameRule.featurette),
        'Dune-featurette.mkv',
      );
      expect(
        RenameService.buildName('Dune', '.mkv', RenameRule.interview),
        'Dune-interview.mkv',
      );
    });

    test('part takes the extra, and defaults to 1', () {
      expect(
        RenameService.buildName('Dune', '.mkv', RenameRule.part, extra: '2'),
        'Dune-part2.mkv',
      );
      expect(
        RenameService.buildName('Dune', '.mkv', RenameRule.part),
        'Dune-part1.mkv',
      );
    });

    test('tvShow joins the code with a dot, and defaults to S01E01', () {
      expect(
        RenameService.buildName(
          'The Expanse',
          '.mkv',
          RenameRule.tvShow,
          extra: 'S02E05',
        ),
        'The Expanse.S02E05.mkv',
      );
      expect(
        RenameService.buildName('The Expanse', '.mkv', RenameRule.tvShow),
        'The Expanse.S01E01.mkv',
      );
    });

    test('subtitle is the extra verbatim: the video name is already in it', () {
      expect(
        RenameService.buildName(
          'ignored',
          '.srt',
          RenameRule.subtitle,
          extra: 'Dune.2021.chi',
        ),
        'Dune.2021.chi.srt',
      );
    });
  });

  group('baseNameForTarget', () {
    test('walks past a Season folder up to the series folder', () {
      expect(
        RenameService.baseNameForTarget(
          'Shows/The Expanse (2015)/Season 02/homevideo.mkv',
        ),
        'The Expanse (2015)',
      );
    });

    test('walks past Specials the same way', () {
      expect(
        RenameService.baseNameForTarget(
          'Shows/The Expanse/Specials/oneoff.mkv',
        ),
        'The Expanse',
      );
    });

    test('the container match ignores case and padding', () {
      expect(
        RenameService.baseNameForTarget('Shows/Some Show/SEASON  03/e.mkv'),
        'Some Show',
      );
      expect(
        RenameService.baseNameForTarget('Shows/Some Show/ SPECIALS /e.mkv'),
        'Some Show',
      );
    });

    test('a movie folder is not a container, so it is the base name', () {
      expect(
        RenameService.baseNameForTarget('Movies/Dune (2021)/Dune (2021).mkv'),
        'Dune (2021)',
      );
    });

    test('a flat target falls back to the file name', () {
      expect(RenameService.baseNameForTarget('Dune.mkv'), 'Dune');
    });

    test('a Season folder with no series above it falls back too', () {
      // Without the fallback this would return null-ish nonsense; the file's
      // own name is the only sane base left.
      expect(RenameService.baseNameForTarget('Season 01/ep.mkv'), 'ep');
    });

    test('the library root is not mistaken for the media name', () {
      expect(
        RenameService.baseNameForTarget('Shows/Some Show/ep.mkv'),
        'Some Show',
      );
    });
  });
}
