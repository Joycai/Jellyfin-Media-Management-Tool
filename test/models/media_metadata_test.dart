import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/models/media_metadata.dart';

void main() {
  test('metadata with any writable field is not empty', () {
    final metadata = MediaMetadata()
      ..set(
        MetadataField.fanart,
        'https://example.invalid/backdrop.jpg',
        FieldOrigin.recipe,
      );

    expect(metadata.isEmpty, isFalse);
  });

  test('malformed actor values are coerced without throwing', () {
    final metadata = MediaMetadata()
      ..set(MetadataField.actors, [
        {'name': 42, 'role': 7, 'thumb': true},
        {'name': ''},
      ], FieldOrigin.recipe);

    expect(metadata.actors, hasLength(1));
    expect(metadata.actors.single.name, '42');
    expect(metadata.actors.single.role, '7');
    expect(metadata.actors.single.thumbUrl, 'true');
  });
}
