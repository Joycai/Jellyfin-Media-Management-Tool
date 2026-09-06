import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_media_management_tool/services/gpu_info.dart';

void main() {
  group('GpuInfo.formatBytes', () {
    test('reports gigabytes with one decimal', () {
      expect(GpuInfo.formatBytes(8 * 1024 * 1024 * 1024), '8.0 GB');
      expect(GpuInfo.formatBytes(24 * 1024 * 1024 * 1024), '24.0 GB');
    });

    test('falls back to whole megabytes below a gigabyte', () {
      expect(GpuInfo.formatBytes(512 * 1024 * 1024), '512 MB');
      expect(GpuInfo.formatBytes(0), '0 MB');
    });
  });

  group('GpuInfo.summary', () {
    test('appends the memory only when the adapter reports some', () {
      const discrete = GpuInfo(
        name: 'NVIDIA GeForce RTX 4090',
        vendorId: 0x10DE,
        dedicatedMemoryBytes: 24 * 1024 * 1024 * 1024,
        isSoftware: false,
      );
      expect(discrete.summary, 'NVIDIA GeForce RTX 4090 · 24.0 GB');

      // Integrated adapters have no VRAM of their own; a trailing "· 0 MB"
      // would read as a fault rather than as the absence of a number.
      const integrated = GpuInfo(
        name: 'AMD Radeon(TM) Graphics',
        vendorId: 0x1002,
        dedicatedMemoryBytes: 0,
        isSoftware: false,
      );
      expect(integrated.summary, 'AMD Radeon(TM) Graphics');
    });
  });

  group('GpuInfo.current', () {
    test('is probed once and cached', () {
      expect(identical(GpuInfo.current(), GpuInfo.current()), isTrue);
    });

    test('is null off Windows', () {
      if (Platform.isWindows) return;
      expect(GpuInfo.current(), isNull);
    });

    test('names a real adapter on Windows', () {
      if (!Platform.isWindows) return;
      final gpu = GpuInfo.current();
      // Every Windows install enumerates at least the Basic Render Driver, so
      // a null here means the DXGI call itself broke rather than that the
      // machine has no GPU.
      expect(gpu, isNotNull);
      expect(gpu!.name, isNotEmpty);
      expect(gpu.vendorId, isNot(0));
      expect(gpu.summary, contains(gpu.name));
      // ignore: avoid_print
      print(
        'detected adapter: ${gpu.summary} (vendor 0x'
        '${gpu.vendorId.toRadixString(16)}, software=${gpu.isSoftware})',
      );
    });
  });
}
