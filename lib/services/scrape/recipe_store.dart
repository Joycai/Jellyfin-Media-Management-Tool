/// Persists learned / user-edited recipes to `scrapers.json` and decides which
/// recipe wins for a given URL.
///
/// Built-in recipes are never mutated: a learned recipe for the same domain is
/// stored alongside and takes precedence while it is healthy, so a bad
/// learning run can be discarded without shipping a fix.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/scrape_recipe.dart';
import 'builtin_recipes.dart';

class RecipeStore extends ChangeNotifier {
  List<ScrapeRecipe> _learned = [];

  /// Recipes that were learned or hand-edited, newest first.
  List<ScrapeRecipe> get learned => List.unmodifiable(_learned);

  /// Everything available for display in settings: learned first, then the
  /// built-ins they may shadow.
  List<ScrapeRecipe> get all => [..._learned, ...BuiltinRecipes.all];

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'scrapers.json'));
  }

  Future<void> init() async {
    try {
      final file = await _file;
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final data = jsonDecode(content);
      if (data is List) {
        _learned = [
          for (final e in data)
            if (e is Map) ScrapeRecipe.fromJson(Map<String, dynamic>.from(e)),
        ];
      }
    } catch (e) {
      debugPrint('Error loading scrapers.json: $e');
    }
    notifyListeners();
  }

  /// The recipe to use for [url], or null when nothing matches.
  ScrapeRecipe? forUrl(Uri url) => select(_learned, url);

  /// Pure selection, extracted so it can be tested without a filesystem.
  ///
  /// A learned recipe wins over the built-in one for the same domain, unless
  /// it has been retired by repeated failures or was written against an older
  /// schema — in either case we fall back rather than parse with a rule set we
  /// no longer understand.
  static ScrapeRecipe? select(List<ScrapeRecipe> learned, Uri url) {
    for (final r in learned) {
      if (!r.matches(url)) continue;
      if (r.isRetired || r.isStale) continue;
      return r;
    }
    return BuiltinRecipes.forUrl(url);
  }

  /// Stores [recipe], replacing any existing entry for the same
  /// domain + path pattern.
  Future<void> save(ScrapeRecipe recipe) async {
    _learned = [
      recipe,
      ..._learned.where(
        (r) => r.domain != recipe.domain || r.pathPattern != recipe.pathPattern,
      ),
    ];
    await _flush();
    notifyListeners();
  }

  Future<void> remove(ScrapeRecipe recipe) async {
    _learned = _learned.where((r) => !identical(r, recipe)).toList();
    await _flush();
    notifyListeners();
  }

  /// Records that [recipe] parsed a page successfully, clearing its failure
  /// streak. Built-in recipes are not persisted, so their counters are
  /// in-memory only.
  Future<void> recordSuccess(ScrapeRecipe recipe) async {
    recipe.successCount++;
    if (recipe.failCount == 0) return;
    recipe.failCount = 0;
    if (recipe.origin != RecipeOrigin.builtin) await _flush();
  }

  /// Records a parse that produced nothing usable. Two in a row retire the
  /// recipe — that is the whole "detect the site redesign" mechanism.
  Future<void> recordFailure(ScrapeRecipe recipe) async {
    recipe.failCount++;
    if (recipe.origin != RecipeOrigin.builtin) await _flush();
    notifyListeners();
  }

  Future<void> _flush() async {
    try {
      final file = await _file;
      await file.writeAsString(
        jsonEncode([for (final r in _learned) r.toJson()]),
      );
    } catch (e) {
      debugPrint('Error saving scrapers.json: $e');
    }
  }
}
