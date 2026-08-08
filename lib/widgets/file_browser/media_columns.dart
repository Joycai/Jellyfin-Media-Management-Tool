/// The file table's columns, and the arithmetic behind dragging their edges.
///
/// Widths are stored as **weights**, not pixels. The table lives in the middle
/// of a three-pane layout whose width the window decides, so pixel widths would
/// either leave a gap on the right or need a horizontal scrollbar that has
/// nowhere to go. Weights re-resolve to whatever space there is, and dragging a
/// divider moves weight from one column to its neighbour — which is what a
/// table that must fill its viewport can honestly offer.
///
/// Kept pure and free of widgets so the resize arithmetic, which is the part
/// that is easy to get subtly wrong, can be tested directly.
library;

enum MediaColumn { name, type, size, suggestion, confidence }

class MediaColumnLayout {
  /// No column may be dragged narrower than this. Below it a header label is
  /// unreadable and the column stops being a column.
  static const minWidth = 56.0;

  /// Space before the first column, matching the row's checkbox gutter.
  static const gutter = 30.0;

  /// Grab area either side of a divider. Wider than the 1px line it draws,
  /// because a one-pixel drag target is a test of aim, not a control.
  static const dividerHitWidth = 10.0;

  static const defaults = <MediaColumn, double>{
    MediaColumn.name: 32,
    MediaColumn.type: 10,
    MediaColumn.size: 10,
    MediaColumn.suggestion: 26,
    MediaColumn.confidence: 16,
  };

  /// Weights as they should be used: the stored map, with anything missing or
  /// nonsensical falling back to the default for that column.
  ///
  /// Tolerant because these come from `config.json`, which a user may have
  /// hand-edited and an older build may have written without some column.
  static Map<MediaColumn, double> sanitize(Map<MediaColumn, double>? stored) {
    final out = <MediaColumn, double>{};
    for (final column in MediaColumn.values) {
      final value = stored?[column];
      out[column] = (value == null || !value.isFinite || value <= 0)
          ? defaults[column]!
          : value;
    }
    return out;
  }

  /// Pixel width per column for a table [available] pixels wide.
  ///
  /// Honours [minWidth] by taking the shortfall from whatever columns still
  /// have room to give. When there is not even enough space for every column
  /// to hit its minimum, the space is split evenly — a cramped table beats a
  /// RenderFlex overflow.
  static Map<MediaColumn, double> resolve(
    double available,
    Map<MediaColumn, double> weights,
  ) {
    final columns = MediaColumn.values;
    if (available <= columns.length * minWidth) {
      final each = available <= 0 ? 0.0 : available / columns.length;
      return {for (final c in columns) c: each};
    }

    final safe = sanitize(weights);
    final total = safe.values.fold(0.0, (a, b) => a + b);
    final out = {for (final c in columns) c: available * safe[c]! / total};

    // Pull every column up to the minimum, then take the difference back from
    // those above it, in proportion to how much they have to spare.
    final owed = <MediaColumn, double>{};
    var deficit = 0.0;
    for (final c in columns) {
      if (out[c]! < minWidth) {
        deficit += minWidth - out[c]!;
        owed[c] = minWidth;
      }
    }
    if (deficit == 0) return out;

    final donors = columns.where((c) => !owed.containsKey(c));
    final spare = donors.fold(0.0, (a, c) => a + out[c]! - minWidth);
    for (final c in donors) {
      final share = spare <= 0 ? 0.0 : (out[c]! - minWidth) / spare;
      out[c] = out[c]! - deficit * share;
    }
    out.addAll(owed);
    return out;
  }

  /// New weights after dragging the divider on the right of [column] by [dx]
  /// pixels, within a table [available] pixels wide.
  ///
  /// The drag is a transfer, not a resize: the column grows by exactly what its
  /// neighbour gives up, so the table still fills its width and no other column
  /// twitches. A drag that would push either side below [minWidth] is clamped
  /// to the point where it would.
  static Map<MediaColumn, double> resize({
    required Map<MediaColumn, double> weights,
    required MediaColumn column,
    required double dx,
    required double available,
  }) {
    final columns = MediaColumn.values;
    final index = columns.indexOf(column);
    if (index < 0 || index >= columns.length - 1) return sanitize(weights);

    final next = columns[index + 1];
    final safe = sanitize(weights);
    final total = safe.values.fold(0.0, (a, b) => a + b);
    if (available <= 0 || total <= 0) return safe;

    // Work in pixels, where the minimum is expressed, then convert back.
    final perPixel = total / available;
    final current = available * safe[column]! / total;
    final neighbour = available * safe[next]! / total;

    final delta = dx.clamp(minWidth - current, neighbour - minWidth);
    return {
      ...safe,
      column: safe[column]! + delta * perPixel,
      next: safe[next]! - delta * perPixel,
    };
  }
}
