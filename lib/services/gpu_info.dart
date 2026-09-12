import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The graphics adapter this process is rendering on.
///
/// Windows only. Flutter's Impeller backend goes through ANGLE, which creates
/// its D3D11 device on the *default* DXGI adapter for the process — and that
/// default is exactly what the per-app GPU preference in Settings → System →
/// Display → Graphics reorders. So DXGI's first hardware adapter is the card
/// the app actually runs on, not merely the one the machine happens to have.
/// It is inferred rather than read back from the live GL context, which no
/// Dart API exposes; the two only disagree if something overrides ANGLE's
/// adapter choice out of band.
///
/// Everything here is best-effort: every failure path yields null and the
/// About page simply drops the row. A diagnostic must never be able to take
/// down the screen that displays it.
class GpuInfo {
  /// Adapter description as reported by the driver, e.g.
  /// `NVIDIA GeForce RTX 4090`.
  final String name;

  /// PCI vendor id — 0x10DE NVIDIA, 0x1002 AMD, 0x8086 Intel.
  final int vendorId;

  /// Dedicated video memory in bytes. 0 on an integrated or software adapter,
  /// which have no VRAM of their own.
  final int dedicatedMemoryBytes;

  /// True for a software rasterizer (Microsoft Basic Render Driver / WARP),
  /// which is what a machine with no usable display driver falls back to.
  final bool isSoftware;

  const GpuInfo({
    required this.name,
    required this.vendorId,
    required this.dedicatedMemoryBytes,
    required this.isSoftware,
  });

  static List<GpuInfo>? _cached;

  /// Every adapter DXGI reports, in its own order, probed once per session.
  /// Empty when the platform isn't Windows or the query failed.
  ///
  /// The order is the answer to "which one is this app on": the first entry is
  /// the process's default adapter. A software rasterizer only appears when it
  /// is the only thing there is.
  static List<GpuInfo> all() => _cached ??= _detect();

  /// The adapter this process renders on. Null when nothing could be read.
  static GpuInfo? current() {
    final adapters = all();
    return adapters.isEmpty ? null : adapters.first;
  }

  /// `NVIDIA GeForce RTX 4090 · 24.0 GB`, or just the name when the adapter
  /// reports no dedicated memory.
  String get summary => dedicatedMemoryBytes > 0
      ? '$name · ${formatBytes(dedicatedMemoryBytes)}'
      : name;

  /// GB with one decimal, MB below a gigabyte. Video memory is always a round
  /// power-of-two figure, so no more precision than that is meaningful.
  static String formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / (1024 * 1024)).round()} MB';
  }

  static List<GpuInfo> _detect() {
    if (!Platform.isWindows) return const [];
    try {
      return _enumerateDxgi();
    } catch (_) {
      return const [];
    }
  }

  // ── DXGI, via raw COM vtable calls ────────────────────────────────────────
  //
  // package:win32 is in the lock file transitively but doesn't surface these
  // interfaces, and three vtable slots don't justify a direct dependency on it.

  /// IID_IDXGIFactory1 `{770aae78-f26f-4dba-a829-253c83d1b387}`, laid out the
  /// way a GUID sits in memory: the first three fields little-endian, the
  /// trailing eight bytes in order.
  static const List<int> _iidFactory1 = [
    0x78, 0xae, 0x0a, 0x77, //
    0x6f, 0xf2, //
    0xba, 0x4d, //
    0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87,
  ];

  // DXGI_ADAPTER_DESC1 field offsets (x64). Description is WCHAR[128]; the
  // SIZE_T members that follow the four UINTs are 8-aligned, hence 272.
  static const int _descSize = 320;
  static const int _offVendorId = 256;
  static const int _offDedicatedVideoMemory = 272;
  static const int _offFlags = 304;
  static const int _flagSoftware = 2;

  static List<GpuInfo> _enumerateDxgi() {
    final dxgi = DynamicLibrary.open('dxgi.dll');
    final createFactory = dxgi
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>),
          int Function(Pointer<Uint8>, Pointer<Pointer<Void>>)
        >('CreateDXGIFactory1');

    final iid = calloc<Uint8>(16);
    final out = calloc<Pointer<Void>>();
    final desc = calloc<Uint8>(_descSize);
    try {
      for (var i = 0; i < _iidFactory1.length; i++) {
        iid[i] = _iidFactory1[i];
      }
      if (createFactory(iid, out) != 0) return const [];
      final factory = out.value;
      try {
        final cards = <GpuInfo>[];
        GpuInfo? fallback;
        for (var index = 0; index < 16; index++) {
          out.value = nullptr;
          // A non-zero HRESULT is DXGI_ERROR_NOT_FOUND once the index runs
          // past the last adapter.
          if (_enumAdapters1(factory, index, out) != 0) break;
          final adapter = out.value;
          try {
            if (_getDesc1(adapter, desc) != 0) continue;
            final info = _readDesc(desc);
            // Real cards in DXGI order. A software adapter is still worth
            // reporting if it's all there is — that *is* the answer — so it is
            // kept as a fallback rather than dropped, but it never joins a
            // list of real ones: "2 GPUs detected" must not mean "one card and
            // the fallback Windows would use if it died".
            if (info.isSoftware) {
              fallback ??= info;
            } else {
              cards.add(info);
            }
          } finally {
            _release(adapter);
          }
        }
        if (cards.isNotEmpty) return cards;
        return fallback == null ? const [] : [fallback];
      } finally {
        _release(factory);
      }
    } finally {
      calloc.free(iid);
      calloc.free(out);
      calloc.free(desc);
    }
  }

  static GpuInfo _readDesc(Pointer<Uint8> desc) {
    final chars = desc.cast<Uint16>();
    final name = StringBuffer();
    for (var i = 0; i < 128; i++) {
      final c = chars[i];
      if (c == 0) break;
      name.writeCharCode(c);
    }
    final flags = (desc + _offFlags).cast<Uint32>().value;
    return GpuInfo(
      name: name.toString().trim(),
      vendorId: (desc + _offVendorId).cast<Uint32>().value,
      dedicatedMemoryBytes: (desc + _offDedicatedVideoMemory)
          .cast<Uint64>()
          .value,
      isSoftware: flags & _flagSoftware != 0,
    );
  }

  /// A COM object is a pointer to a struct whose first member is its vtable,
  /// so each interface method is one indexed function pointer away. `dart:ffi`
  /// needs `asFunction`'s types known at compile time, which is why every slot
  /// gets its own wrapper rather than one generic helper.
  static Pointer<Pointer<Void>> _vtable(Pointer<Void> obj) =>
      obj.cast<Pointer<Pointer<Void>>>().value;

  /// IDXGIFactory1::EnumAdapters1 — slot 12.
  static int _enumAdapters1(
    Pointer<Void> factory,
    int index,
    Pointer<Pointer<Void>> out,
  ) => _vtable(factory)[12]
      .cast<
        NativeFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>)
        >
      >()
      .asFunction<
        int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
      >()(factory, index, out);

  /// IDXGIAdapter1::GetDesc1 — slot 10.
  static int _getDesc1(Pointer<Void> adapter, Pointer<Uint8> desc) =>
      _vtable(adapter)[10]
          .cast<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Uint8>)>>()
          .asFunction<int Function(Pointer<Void>, Pointer<Uint8>)>()(
        adapter,
        desc,
      );

  /// IUnknown::Release — slot 2.
  static void _release(Pointer<Void> obj) {
    _vtable(obj)[2]
        .cast<NativeFunction<Uint32 Function(Pointer<Void>)>>()
        .asFunction<int Function(Pointer<Void>)>()(obj);
  }
}
