import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';
import 'package:jellyfin_media_management_tool/services/scrape/image_role.dart';

Map<String, String> _plan({
  required List<String> order,
  Set<String>? selected,
  Map<String, ImageRole> roles = const {},
  String extension = 'jpg',
}) => ImageNaming.plan(
  order: order,
  selected: selected ?? order.toSet(),
  roles: roles,
  extensionOf: (_) => extension,
);

void main() {
  group('naming', () {
    test('an unmarked image keeps the name the server used', () {
      // The point of the default. A picture the user just wants to keep should
      // not be forced into a Jellyfin slot it does not fill.
      expect(_plan(order: ['https://e.test/db/spsf43_01.jpg']), {
        'https://e.test/db/spsf43_01.jpg': 'spsf43_01.jpg',
      });
    });

    test('a marked image takes the name Jellyfin looks for', () {
      // The names verified against a live server: `folder` for the primary
      // image, `backdrop` for the background, `landscape` for the thumb and
      // `menu` for the menu art. Jellyfin also reads `poster`/`fanart`/`thumb`,
      // but one type gets one name here.
      expect(
        _plan(
          order: [
            'https://e.test/pac_s.jpg',
            'https://e.test/bg.jpg',
            'https://e.test/wide.jpg',
            'https://e.test/menu.jpg',
          ],
          roles: {
            'https://e.test/pac_s.jpg': ImageRole.poster,
            'https://e.test/bg.jpg': ImageRole.fanart,
            'https://e.test/wide.jpg': ImageRole.thumb,
            'https://e.test/menu.jpg': ImageRole.menu,
          },
        ),
        {
          'https://e.test/pac_s.jpg': 'folder.jpg',
          'https://e.test/bg.jpg': 'backdrop.jpg',
          'https://e.test/wide.jpg': 'landscape.jpg',
          'https://e.test/menu.jpg': 'menu.jpg',
        },
      );
    });

    test('no two roles write the same Jellyfin slot', () {
      // `thumb.jpg` beside `landscape.jpg` is two files for one image type,
      // and Jellyfin silently picks one — so each type has exactly one stem.
      final stems = [
        for (final role in ImageRole.values)
          if (role.stem != null) role.stem!,
      ];
      expect(stems.toSet().length, stems.length);
    });

    test('extra backdrops are numbered in their own folder', () {
      expect(
        _plan(
          order: ['https://e.test/1.jpg', 'https://e.test/2.jpg'],
          roles: {
            'https://e.test/1.jpg': ImageRole.extraFanart,
            'https://e.test/2.jpg': ImageRole.extraFanart,
          },
        ).values,
        ['extrafanart/backdrop-1.jpg', 'extrafanart/backdrop-2.jpg'],
      );
    });

    test('the extension comes from the bytes, not the URL', () {
      // A CDN serving a PNG from a .jpg path would otherwise produce
      // poster.jpg full of PNG data — and Jellyfin matches on name.
      expect(
        _plan(
          order: ['https://e.test/pac_s.jpg'],
          roles: {'https://e.test/pac_s.jpg': ImageRole.poster},
          extension: 'png',
        ).values.single,
        'folder.png',
      );
    });

    test('unselected images are not named at all', () {
      expect(
        _plan(
          order: ['https://e.test/a.jpg', 'https://e.test/b.jpg'],
          selected: {'https://e.test/b.jpg'},
        ).keys,
        ['https://e.test/b.jpg'],
      );
    });

    test('two images with the same server name do not collide', () {
      // Different folders on the site, same basename. Without this the second
      // would silently overwrite the first.
      expect(
        _plan(
          order: ['https://e.test/a/cover.jpg', 'https://e.test/b/cover.jpg'],
        ).values,
        ['cover.jpg', 'cover (2).jpg'],
      );
    });

    test('a hostile server name cannot climb out of the folder', () {
      // MetadataWriter would refuse the write anyway, but a refused write is a
      // lost image; producing a usable name is better than relying on the
      // backstop.
      final name = _plan(
        order: ['https://e.test/%2e%2e%2f%2e%2e%2fevil.jpg'],
      ).values.single;

      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, isNot(startsWith('.')));
    });

    test('a URL with no usable file name still gets one', () {
      expect(_plan(order: ['https://e.test/']).values.single, 'image.jpg');
    });
  });

  group('roles', () {
    test('every role but original and extra fanart is single-slot', () {
      // Two files both called poster.jpg means one overwriting the other, so
      // the UI has to take the role away from whoever held it.
      expect(ImageRole.poster.isSingleSlot, isTrue);
      expect(ImageRole.disc.isSingleSlot, isTrue);
      expect(ImageRole.original.isSingleSlot, isFalse);
      expect(ImageRole.extraFanart.isSingleSlot, isFalse);
    });

    test('the scrape seeds the roles it already worked out', () {
      final roles = ImageNaming.defaultsFor(
        MediaMetadata(
          posterUrl: 'https://e.test/p.jpg',
          fanartUrl: 'https://e.test/f.jpg',
          extraFanartUrls: ['https://e.test/1.jpg'],
        ),
      );

      expect(roles['https://e.test/p.jpg'], ImageRole.poster);
      expect(roles['https://e.test/f.jpg'], ImageRole.fanart);
      // A still is just a picture until the user says otherwise.
      expect(roles['https://e.test/1.jpg'], isNull);
    });

    test('one URL serving as both poster and backdrop is only the poster', () {
      final roles = ImageNaming.defaultsFor(
        MediaMetadata(
          posterUrl: 'https://e.test/only.jpg',
          fanartUrl: 'https://e.test/only.jpg',
        ),
      );

      expect(roles, {'https://e.test/only.jpg': ImageRole.poster});
    });
  });
}
