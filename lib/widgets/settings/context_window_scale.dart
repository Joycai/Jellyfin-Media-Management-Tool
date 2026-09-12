import 'dart:math' as math;

/// 6.1 / 03c · 上下文窗口滑块的刻度换算。
///
/// 纯函数，独立成库是为了能直接测：滑块的手感全在这几行里，而「拖到 128k 附近
/// 会不会正好停在 128k」这种问题用手拖是验不完的。
///
/// **刻度等距分段，段内线性。** 8k–1M 差 128 倍，线性铺开的话 8k 到 32k 挤在
/// 轨道最左边 2% 里 —— 而那正是本地模型最常落的区间。八段等宽让每一段都有同样
/// 的拖动余量；段内仍按 1k 连续，所以把手可以停在任意 1k 位置，不是只能落在刻度上。
abstract final class ContextWindowScale {
  /// 九个刻度 = 八段。数值就是服务端配置里会看到的那些。
  static const List<int> ticks = [
    8192, // 8k
    16384, // 16k
    32768, // 32k
    65536, // 64k
    98304, // 96k
    131072, // 128k
    262144, // 256k
    524288, // 512k
    1048576, // 1M
  ];

  /// 步进 1k。
  static const int step = 1024;

  /// 距刻度 ≤ 2k 时吸附过去。
  static const int snapWithin = 2048;

  /// Shift + 方向键的步长。
  static const int coarseStep = 16 * step;

  static int get min => ticks.first;
  static int get max => ticks.last;

  /// 0 – 1 的轨道位置。区间外的值夹到端点 —— 服务端报了个 2M，把手停在最右端
  /// 比跑出轨道外要诚实。
  static double positionOf(int tokens) {
    final v = tokens.clamp(min, max);
    for (var i = 0; i < ticks.length - 1; i++) {
      if (v <= ticks[i + 1]) {
        final span = ticks[i + 1] - ticks[i];
        return (i + (v - ticks[i]) / span) / (ticks.length - 1);
      }
    }
    return 1;
  }

  /// 轨道位置 → tokens，已对齐到 1k 并做过吸附。
  static int tokensAt(double position) {
    final scaled = position.clamp(0.0, 1.0) * (ticks.length - 1);
    var i = scaled.floor();
    if (i > ticks.length - 2) i = ticks.length - 2;
    final f = scaled - i;
    final raw = ticks[i] + (ticks[i + 1] - ticks[i]) * f;
    return snap(align(raw.round()));
  }

  /// 向下对齐到 1k，并夹进区间（03c）。
  ///
  /// 向下而不是就近：这个数要和服务端那边加载模型时填的上下文对得上，而估高了
  /// 会让提示越过窗口被服务端从头截掉 —— 截掉的正是系统提示。宁可少一点。
  static int align(int tokens) {
    final aligned = (tokens / step).floor() * step;
    return aligned.clamp(min, max);
  }

  /// 靠得够近就吸到刻度上。128k 和 130k 在滑轨上差不到两个像素，而只有前者是
  /// 用户真正想填的那个数。
  static int snap(int tokens) {
    for (final tick in ticks) {
      if ((tokens - tick).abs() <= snapWithin) return tick;
    }
    return tokens.clamp(min, max);
  }

  /// PgUp / PgDn：跳到相邻刻度，也就是一整段。
  static int nextTick(int tokens, {required bool up}) {
    if (up) {
      for (final tick in ticks) {
        if (tick > tokens) return tick;
      }
      return max;
    }
    for (final tick in ticks.reversed) {
      if (tick < tokens) return tick;
    }
    return min;
  }

  /// 展示用：≥ 1024k 记作 `1M`，其余记作 `128k`。输入框里始终是原始 tokens 数，
  /// 方便和服务端配置逐字对照。
  static String format(int tokens) {
    if (tokens >= 1024 * 1024) {
      final m = tokens / (1024 * 1024);
      return m == m.roundToDouble()
          ? '${m.round()}M'
          : '${m.toStringAsFixed(1)}M';
    }
    final k = tokens / 1024;
    return k == k.roundToDouble()
        ? '${k.round()}k'
        : '${k.toStringAsFixed(1)}k';
  }

  /// 千位分隔，给卡头那个当前值用。
  static String grouped(int tokens) {
    final digits = tokens.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// 最大输出 tokens：256 – 上下文 ÷ 2，步进 256（03c）。
abstract final class MaxOutputScale {
  static const int step = 256;
  static const int min = step;

  /// 上下文没填时没有上限可算 —— 那时不夹紧，让服务端自己说了算。
  static int? ceilingFor(int? contextWindow) =>
      contextWindow == null ? null : math.max(min, contextWindow ~/ 2);

  /// 对齐到 256 并夹进 `[256, 上下文 ÷ 2]`。
  static int clamp(int tokens, {int? contextWindow}) {
    final aligned = math.max(min, (tokens / step).round() * step);
    final ceiling = ceilingFor(contextWindow);
    return ceiling == null ? aligned : math.min(aligned, ceiling);
  }
}
