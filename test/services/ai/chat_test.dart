import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/ai/chat.dart';

void main() {
  group('arguments written back to back', () {
    test('merge left to right', () {
      expect(ToolCall.mergeConcatenated('{}{"id":1}'), {'id': 1});
      expect(ToolCall.mergeConcatenated('{"a":1} \n {"a":2,"b":3}'), {
        'a': 2,
        'b': 3,
      });
    });

    test('braces and quotes inside strings are text', () {
      expect(ToolCall.mergeConcatenated(r'{"a":"}{\""}{"b":2}'), {
        'a': '}{"',
        'b': 2,
      });
      // An escaped backslash does not escape the quote after it.
      expect(ToolCall.mergeConcatenated(r'{"a":"x\\"}{"b":"\u007d{"}'), {
        'a': r'x\',
        'b': '}{',
      });
    });

    test('anything between the objects, or one object alone, is not this', () {
      expect(ToolCall.mergeConcatenated('{"a":1} x {"b":2}'), isNull);
      expect(ToolCall.mergeConcatenated('{"a":1},{"b":2}'), isNull);
      expect(ToolCall.mergeConcatenated('{"a":1}[1]'), isNull);
      expect(ToolCall.mergeConcatenated('{"a":1} "x" {"b":2}'), isNull);
      expect(ToolCall.mergeConcatenated('{"a":1}}{{"b":2}'), isNull);
      // A cut-off last object is not dropped to run the ones before it.
      expect(ToolCall.mergeConcatenated('{"a":1}{"b":2}{"c":'), isNull);
      expect(ToolCall.mergeConcatenated('{"a":1}{"b":'), isNull);
      expect(ToolCall.mergeConcatenated('{"a":1}'), isNull);
      expect(ToolCall.mergeConcatenated(''), isNull);
    });

    test('are read as the object they merge into', () {
      const call = ToolCall(id: 'c', name: 'f', arguments: '{}{"id":1}');
      expect(call.decodedArguments, {'id': 1});
      const single = ToolCall(id: 'c', name: 'f', arguments: '{"a":1}');
      expect(single.decodedArguments, {'a': 1});
      const broken = ToolCall(id: 'c', name: 'f', arguments: '{"a":');
      expect(broken.decodedArguments, isNull);
    });

    test('are sent back as one object; anything else as it was', () {
      expect(ToolCall.normalizeArguments('{}{"id":1}'), '{"id":1}');
      expect(ToolCall.normalizeArguments('{"a": 1}'), '{"a": 1}');
      expect(ToolCall.normalizeArguments('{"a":'), '{"a":');
    });
  });
}
