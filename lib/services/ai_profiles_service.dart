import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/ai_service_profile.dart';
import '../utils/ids.dart';
import 'ai/ai_provider.dart';

/// Owns the user-configured AI service profiles and the currently active
/// selection. Persists to its own `ai_profiles.json` so editing a profile
/// doesn't trigger a rewrite of the theme/locale/glass config — and a slider
/// drag never thrashes the AI keys file.
///
/// Reads the legacy `config.json` on first launch if its own file doesn't
/// exist, copying over `ai_services` / `active_ai_service` / the older `ai`
/// single-endpoint block. The legacy keys aren't deleted from `config.json`
/// (kept as harmless dead data) so an accidental downgrade still works.
class AiProfilesService extends ChangeNotifier {
  List<AiServiceProfile> _services = [];
  String? _activeId;

  static const _saveDebounce = Duration(milliseconds: 250);
  Timer? _saveTimer;

  List<AiServiceProfile> get services => List.unmodifiable(_services);
  String? get activeId => _activeId;

  /// The active profile, falling back to the first configured one.
  AiServiceProfile? get active {
    if (_services.isEmpty) return null;
    return _services.firstWhere(
      (s) => s.id == _activeId,
      orElse: () => _services.first,
    );
  }

  /// Runtime config for the active profile (consumed by [AiService]).
  AiConfig get aiConfig => active?.toAiConfig() ?? AiConfig.empty;

  Future<Directory> get _dir async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> get _file async => File(p.join((await _dir).path, 'ai_profiles.json'));
  Future<File> get _legacyConfig async => File(p.join((await _dir).path, 'config.json'));

  Future<void> init() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          _loadFromMap(data);
        }
      } else {
        await _migrateFromLegacy();
      }
    } catch (e) {
      debugPrint('Error loading ai profiles: $e');
    }
    notifyListeners();
  }

  Future<void> _migrateFromLegacy() async {
    final legacy = await _legacyConfig;
    if (!await legacy.exists()) return;
    try {
      final content = await legacy.readAsString();
      if (content.isEmpty) return;
      final data = jsonDecode(content) as Map<String, dynamic>;
      _loadFromMap(data);
      // Stamp our own file with the migrated state so we don't re-read the
      // legacy keys on the next launch.
      _scheduleSave();
    } catch (_) {
      // Best-effort migration; if the legacy file is malformed we just stay
      // empty and the user re-adds their profile in onboarding/settings.
    }
  }

  void _loadFromMap(Map<String, dynamic> data) {
    if (data['ai_services'] is List) {
      _services = (data['ai_services'] as List)
          .whereType<Map<String, dynamic>>()
          .map(AiServiceProfile.fromJson)
          .toList();
      _activeId = data['active_ai_service'] as String?;
    } else if (data['ai'] is Map<String, dynamic>) {
      // Older single-endpoint shape: promote to a one-profile list.
      final cfg = AiConfig.fromJson(data['ai']);
      final migrated = AiServiceProfile(
        id: newId(),
        name: cfg.provider == AiProviderType.googleGenAi ? 'Google GenAI' : 'OpenAI',
        provider: cfg.provider,
        endpoint: cfg.endpoint,
        apiKey: cfg.apiKey,
        model: cfg.model,
        temperature: cfg.temperature,
      );
      _services = [migrated];
      _activeId = migrated.id;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode({
        'ai_services': _services.map((s) => s.toJson()).toList(),
        'active_ai_service': _activeId,
      }));
    } catch (e) {
      debugPrint('Error saving ai profiles: $e');
    }
  }

  @override
  void dispose() {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      unawaited(_save());
    }
    super.dispose();
  }

  /// Adds a profile and makes it active. Returns the added profile.
  Future<AiServiceProfile> add(AiServiceProfile profile) async {
    _services = [..._services, profile];
    _activeId = profile.id;
    _scheduleSave();
    notifyListeners();
    return profile;
  }

  /// Replaces a profile in place (matched by id).
  Future<void> update(AiServiceProfile profile) async {
    final idx = _services.indexWhere((s) => s.id == profile.id);
    if (idx < 0) return;
    _services = [..._services]..[idx] = profile;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _services = _services.where((s) => s.id != id).toList();
    if (_activeId == id) {
      _activeId = _services.isNotEmpty ? _services.first.id : null;
    }
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    if (_services.every((s) => s.id != id)) return;
    _activeId = id;
    _scheduleSave();
    notifyListeners();
  }
}
