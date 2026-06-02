import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String appVersionLabel = 'v1.2.2 — mode cache';

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  runApp(const UxoOfflineApp());
}

class UxoOfflineApp extends StatelessWidget {
  const UxoOfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UXO Offline FR',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    const seed = Color(0xFFD84315);
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: seed,
      scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: Color(0xFFD84315),
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NATIVE CHANNEL
// ─────────────────────────────────────────────────────────────────────────────

class NativeFolderReader {
  static const MethodChannel _channel =
      MethodChannel('uxo_offline_fr/folder_reader');

  static final Map<String, String> _resolvedCache = {};
  static final Map<String, Future<String>> _inFlight = {};

  static Future<String?> pickFolder() =>
      _channel.invokeMethod<String>('pickFolder');

  static Future<String> copyDatabaseToCache({required String treeUri}) async {
    final result = await _channel
        .invokeMethod<String>('copyDatabaseToCache', {'treeUri': treeUri});
    if (result == null || result.trim().isEmpty) {
      throw Exception('Copie locale impossible : catuxo_database.json');
    }
    return result;
  }

  static Future<String> cacheImage({
    required String treeUri,
    required String path,
  }) {
    final key = '$treeUri|$path';
    final cached = _resolvedCache[key];
    if (cached != null) return Future.value(cached);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final result = await _channel
            .invokeMethod<String>('cacheImage', {'treeUri': treeUri, 'path': path});
        if (result == null || result.trim().isEmpty) {
          throw Exception('Image introuvable : $path');
        }
        _resolvedCache[key] = result;
        return result;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static void clearMemoryCache() {
    _resolvedCache.clear();
    _inFlight.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOLDER CONFIG
// ─────────────────────────────────────────────────────────────────────────────

class FolderConfig {
  static const String _fileName = 'selected_folder_uri.txt';

  static Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$_fileName');

  static Future<String?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    final v = (await f.readAsString()).trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> save(String uri) async => (await _file()).writeAsString(uri);

  static Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────

class UxoDatabase {
  final List<UxoItem> items;
  final List<GlossaryItem> glossary;

  const UxoDatabase({required this.items, required this.glossary});

  factory UxoDatabase.fromJson(Map<String, dynamic> json) {
    final items = asList(json['items'])
        .whereType<Map>()
        .map((e) => UxoItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final glossary = asList(json['glossary'])
        .whereType<Map>()
        .map((e) => GlossaryItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.term.isNotEmpty)
        .toList();

    return UxoDatabase(items: items, glossary: glossary);
  }
}

UxoDatabase _parseDatabase(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('catuxo_database.json invalide.');
  }
  return UxoDatabase.fromJson(decoded);
}

class UxoItem {
  final String id, name, slug, category, categorySlug, type, country,
      description, sourceUrl, safetyNoticeFr, searchText;
  final List<String> keywords, variants;
  final List<UxoImage> images;

  const UxoItem({
    required this.id, required this.name, required this.slug,
    required this.category, required this.categorySlug, required this.type,
    required this.country, required this.description, required this.sourceUrl,
    required this.safetyNoticeFr, required this.keywords, required this.variants,
    required this.images, required this.searchText,
  });

  factory UxoItem.fromJson(Map<String, dynamic> json) {
    final countries = asStringList(json['countries']);
    final images = asList(json['images'])
        .whereType<Map>()
        .map((e) => UxoImage.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.path.isNotEmpty)
        .toList();
    final keywords = <String>{
      ...asStringList(json['technologyKeywords']),
      ...asStringList(json['keywords']),
      ...asList(json['metaKeys']).whereType<Map>().map((e) => textOf(e['name'])),
      ...asList(json['meta_keys']).whereType<Map>().map((e) => textOf(e['name'])),
    }.where((e) => e.isNotEmpty).toList()..sort();
    final category = textFromObject(json['category']);
    final type = textFromObject(json['type']);
    final country = countries.isNotEmpty
        ? countries.join(', ')
        : textFromObject(json['country']);
    final description = cleanText(firstNotEmpty([
      textOf(json['descriptionText']), textOf(json['description']),
      textOf(json['descriptionOriginalHtml']), textOf(json['content']),
    ]));
    final name = textOf(json['name']);
    final searchText =
        normalizeSearch([name, category, type, country, keywords.join(' ')].join(' '));
    return UxoItem(
      id: textOf(json['id']), name: name, slug: textOf(json['slug']),
      category: category, categorySlug: textOf(json['categorySlug']),
      type: type, country: country, description: description,
      sourceUrl: firstNotEmpty([
        textOf(json['sourceUrl']), textOf(json['permalink']), textOf(json['url']),
      ]),
      safetyNoticeFr: textOf(json['safetyNoticeFr']),
      keywords: keywords,
      variants: {...asStringList(json['variants']), ...asStringList(json['aliases'])}.toList(),
      images: images, searchText: searchText,
    );
  }
}

class UxoImage {
  final String path, caption;
  final bool placeholder;

  const UxoImage({required this.path, required this.caption, required this.placeholder});

  factory UxoImage.fromJson(Map<String, dynamic> json) => UxoImage(
        path: firstNotEmpty([
          textOf(json['path']), textOf(json['localPath']), textOf(json['file']),
        ]),
        caption: firstNotEmpty([textOf(json['caption']), textOf(json['filename'])]),
        placeholder: json['placeholder'] == true,
      );
}

class GlossaryItem {
  final String term, fullName, category, description;

  const GlossaryItem({
    required this.term, required this.fullName,
    required this.category, required this.description,
  });

  factory GlossaryItem.fromJson(Map<String, dynamic> json) => GlossaryItem(
        term: firstNotEmpty([textOf(json['term']), textOf(json['name'])]),
        fullName: firstNotEmpty([textOf(json['fullName']), textOf(json['full_name'])]),
        category: textOf(json['category']),
        description: cleanText(firstNotEmpty([
          textOf(json['shortDescription']), textOf(json['description']),
          textOf(json['definition']),
        ])),
      );
}

class KeywordInfo {
  final String term, fullName, category, description;

  const KeywordInfo({
    required this.term, required this.fullName,
    required this.category, required this.description,
  });

  GlossaryItem toGlossaryItem() => GlossaryItem(
        term: term, fullName: fullName, category: category, description: description,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// KEYWORD MAP
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, KeywordInfo> keywordInfoMap = {
  'FUNCTION': KeywordInfo(term: 'Function', fullName: '', category: 'Champ technique', description: 'Indique le rôle ou la fonction décrite dans la fiche.'),
  'FILL': KeywordInfo(term: 'Fill', fullName: '', category: 'Champ technique', description: 'Indique le type de remplissage ou de contenu mentionné dans la fiche.'),
  'EXPOSED': KeywordInfo(term: 'Exposed', fullName: '', category: 'État / configuration', description: 'Indique un élément exposé ou visible selon la description de l’objet.'),
  'DELAY': KeywordInfo(term: 'Delay', fullName: '', category: 'Fonction temps', description: 'Désigne un retard, une temporisation ou un délai de fonctionnement.'),
  'SELF-DESTRUCT': KeywordInfo(term: 'Self-Destruct', fullName: '', category: 'Fonction', description: 'Fonction d’autodestruction mentionnée dans certaines fiches.'),
  'HE': KeywordInfo(term: 'HE', fullName: 'High Explosive', category: 'Type de charge', description: 'Charge explosive à effet de souffle ou de fragmentation selon le contexte.'),
  'HEAT': KeywordInfo(term: 'HEAT', fullName: 'High-Explosive Anti-Tank', category: 'Type de charge', description: 'Charge antichar à effet dirigé.'),
  'HESH': KeywordInfo(term: 'HESH', fullName: 'High-Explosive Squash Head', category: 'Type de charge', description: 'Type de charge explosive utilisée contre surfaces dures ou blindées.'),
  'AP': KeywordInfo(term: 'AP', fullName: 'Armor-Piercing', category: 'Effet / usage', description: 'Terme descriptif pour une munition perforante.'),
  'APERS': KeywordInfo(term: 'APERS', fullName: 'Anti-Personnel', category: 'Effet / usage', description: 'Terme utilisé pour des effets ou munitions destinés aux personnes.'),
  'AT': KeywordInfo(term: 'AT', fullName: 'Anti-Tank', category: 'Effet / usage', description: 'Munition ou système destiné aux cibles blindées.'),
  'AA': KeywordInfo(term: 'AA', fullName: 'Anti-Aircraft', category: 'Effet / usage', description: 'Munition ou système destiné aux cibles aériennes.'),
  'WP': KeywordInfo(term: 'WP', fullName: 'White Phosphorus', category: 'Composition / effet', description: 'Phosphore blanc.'),
  'SMK': KeywordInfo(term: 'SMK', fullName: 'Smoke', category: 'Effet', description: 'Effet fumigène.'),
  'ILLUM': KeywordInfo(term: 'ILLUM', fullName: 'Illumination', category: 'Effet', description: 'Effet éclairant.'),
  'INC': KeywordInfo(term: 'INC', fullName: 'Incendiary', category: 'Effet', description: 'Effet incendiaire.'),
  'FRAG': KeywordInfo(term: 'FRAG', fullName: 'Fragmentation', category: 'Effet', description: 'Effet de fragmentation.'),
  'PD': KeywordInfo(term: 'PD', fullName: 'Point Detonating', category: 'Fusée / fonctionnement', description: 'Fusée à action au point d’impact.'),
  'BD': KeywordInfo(term: 'BD', fullName: 'Base Detonating', category: 'Fusée / fonctionnement', description: 'Fusée située en base.'),
  'PIBD': KeywordInfo(term: 'PIBD', fullName: 'Point-Initiating Base-Detonating', category: 'Fusée / fonctionnement', description: 'Abréviation technique descriptive de type de fusée.'),
  'MTSQ': KeywordInfo(term: 'MTSQ', fullName: 'Mechanical Time and Super Quick', category: 'Fusée / fonctionnement', description: 'Fonctions temps mécanique et action rapide.'),
  'VT': KeywordInfo(term: 'VT', fullName: 'Variable Time', category: 'Fusée / fonctionnement', description: 'Fonction de temps variable ou de proximité selon le contexte.'),
  'MT': KeywordInfo(term: 'MT', fullName: 'Mechanical Time', category: 'Fusée / fonctionnement', description: 'Fonction temps mécanique.'),
  'SD': KeywordInfo(term: 'SD', fullName: 'Self-Destruct', category: 'Fonction', description: 'Fonction d’autodestruction.'),
  'GRZ': KeywordInfo(term: 'GRZ', fullName: 'Graze', category: 'Fusée / fonctionnement', description: 'Terme lié à une sensibilité à impact rasant selon le contexte.'),
  'IIF': KeywordInfo(term: 'IIF', fullName: 'Impact-Inertia-Fired', category: 'Fusée / fonctionnement', description: 'Fonctionnement décrit par impact et inertie.'),
  'IED': KeywordInfo(term: 'IED', fullName: 'Improvised Explosive Device', category: 'Terme général', description: 'Engin explosif improvisé.'),
  'UXO': KeywordInfo(term: 'UXO', fullName: 'Unexploded Ordnance', category: 'Terme général', description: 'Munition explosive non explosée.'),
  'ERW': KeywordInfo(term: 'ERW', fullName: 'Explosive Remnants of War', category: 'Terme général', description: 'Restes explosifs de guerre.'),
  'EOD': KeywordInfo(term: 'EOD', fullName: 'Explosive Ordnance Disposal', category: 'Terme général', description: 'Domaine professionnel de traitement des munitions explosives.'),
  'LAW': KeywordInfo(term: 'LAW', fullName: 'Light Anti-Tank Weapon', category: 'Système', description: 'Arme antichar légère.'),
  'RPG': KeywordInfo(term: 'RPG', fullName: 'Rocket-Propelled Grenade', category: 'Système', description: 'Grenade ou roquette propulsée.'),
  'ATGM': KeywordInfo(term: 'ATGM', fullName: 'Anti-Tank Guided Missile', category: 'Système', description: 'Missile guidé antichar.'),
  'MANPADS': KeywordInfo(term: 'MANPADS', fullName: 'Man-Portable Air-Defense System', category: 'Système', description: 'Système portable de défense antiaérienne.'),
  'AFV': KeywordInfo(term: 'AFV', fullName: 'Armoured Fighting Vehicle', category: 'Véhicule', description: 'Véhicule blindé de combat.'),
};

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────

enum ScreenTab { fiches, categories, lexique, securite }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String? treeUri;
  UxoDatabase? database;
  bool loading = true;
  String query = '';
  ScreenTab tab = ScreenTab.fiches;
  Timer? _debounce;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    loadSavedFolder();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadSavedFolder() async {
    setState(() => loading = true);
    try {
      final saved = await FolderConfig.load();
      if (saved == null) {
        setState(() { treeUri = null; database = null; });
        return;
      }
      await _loadDatabase(saved);
    } catch (e) {
      await FolderConfig.clear();
      NativeFolderReader.clearMemoryCache();
      if (mounted) _showMessage('Dossier oublié : $e');
      setState(() { treeUri = null; database = null; });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> chooseFolder() async {
    setState(() => loading = true);
    try {
      final selected = await NativeFolderReader.pickFolder();
      if (selected == null || selected.trim().isEmpty) {
        throw Exception('Aucun dossier sélectionné.');
      }
      await FolderConfig.save(selected);
      NativeFolderReader.clearMemoryCache();
      await _loadDatabase(selected);
    } catch (e) {
      if (mounted) _showMessage('Erreur dossier : $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadDatabase(String uri) async {
    final cachePath = await NativeFolderReader.copyDatabaseToCache(treeUri: uri);
    final text = await File(cachePath).readAsString();
    final db = await compute(_parseDatabase, text);
    if (mounted) {
      setState(() {
        treeUri = uri; database = db;
        query = ''; _searchController.clear();
        tab = ScreenTab.fiches;
      });
    }
  }

  Future<void> resetFolder() async {
    await FolderConfig.clear();
    NativeFolderReader.clearMemoryCache();
    setState(() {
      treeUri = null; database = null;
      query = ''; _searchController.clear();
      tab = ScreenTab.fiches;
    });
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  List<UxoItem> get _filteredItems {
    final db = database;
    if (db == null) return const [];
    final q = normalizeSearch(query);
    if (q.isEmpty) return db.items;
    return db.items.where((item) => item.searchText.contains(q)).toList();
  }

  Map<String, List<UxoItem>> get _byCategory {
    final db = database;
    final map = <String, List<UxoItem>>{};
    if (db == null) return map;
    for (final item in db.items) {
      final key = item.category.trim().isEmpty ? 'Non classé' : item.category;
      map.putIfAbsent(key, () => []);
      map[key]!.add(item);
    }
    return Map.fromEntries(
      map.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
  }

  Map<String, GlossaryItem> get _glossaryMap {
    final db = database;
    if (db == null) return const {};
    return { for (final item in db.glossary) normalizeSearch(item.term): item };
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = database;
    return Scaffold(
      appBar: AppBar(
        title: const Text('UXO Offline FR'),
        actions: [
          IconButton(
            tooltip: 'Choisir le dossier',
            onPressed: loading ? null : chooseFolder,
            icon: const Icon(Icons.folder_open),
          ),
          if (db != null)
            IconButton(
              tooltip: 'Réinitialiser',
              onPressed: loading ? null : resetFolder,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: loading
          ? const _LoadingView()
          : db == null
              ? _EmptyState(onChoose: chooseFolder)
              : _AppBody(
                  database: db,
                  treeUri: treeUri!,
                  tab: tab,
                  filteredItems: _filteredItems,
                  byCategory: _byCategory,
                  glossaryMap: _glossaryMap,
                  searchController: _searchController,
                  onSearchChanged: _onSearchChanged,
                  onTabChanged: (v) => setState(() => tab = v),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP BODY
// ─────────────────────────────────────────────────────────────────────────────

class _AppBody extends StatelessWidget {
  final UxoDatabase database;
  final String treeUri;
  final ScreenTab tab;
  final List<UxoItem> filteredItems;
  final Map<String, List<UxoItem>> byCategory;
  final Map<String, GlossaryItem> glossaryMap;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ScreenTab> onTabChanged;

  const _AppBody({
    required this.database, required this.treeUri, required this.tab,
    required this.filteredItems, required this.byCategory,
    required this.glossaryMap, required this.searchController,
    required this.onSearchChanged, required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeaderStats(database: database),
        _TabSelector(selected: tab, onChanged: onTabChanged),
        Expanded(
          child: switch (tab) {
            ScreenTab.fiches => _FichesView(
                items: filteredItems, treeUri: treeUri,
                glossaryMap: glossaryMap, allItems: database.items,
                searchController: searchController,
                onSearchChanged: onSearchChanged,
              ),
            ScreenTab.categories => _CategoriesView(
                byCategory: byCategory, treeUri: treeUri,
                glossaryMap: glossaryMap, allItems: database.items,
              ),
            ScreenTab.lexique => _GlossaryView(glossary: database.glossary),
            ScreenTab.securite => const _SafetyView(),
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FICHES LIST VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _FichesView extends StatelessWidget {
  final List<UxoItem> items;
  final String treeUri;
  final Map<String, GlossaryItem> glossaryMap;
  final List<UxoItem> allItems;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _FichesView({
    required this.items, required this.treeUri, required this.glossaryMap,
    required this.allItems, required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Rechercher une fiche…',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${items.length} fiche${items.length > 1 ? 's' : ''}',
              style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black54,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: items.length,
            itemBuilder: (context, index) => RepaintBoundary(
              child: _UxoCard(
                item: items[index], treeUri: treeUri,
                glossaryMap: glossaryMap, allItems: allItems,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UXO CARD
// ─────────────────────────────────────────────────────────────────────────────

class _UxoCard extends StatelessWidget {
  final UxoItem item;
  final String treeUri;
  final Map<String, GlossaryItem> glossaryMap;
  final List<UxoItem> allItems;

  const _UxoCard({
    required this.item, required this.treeUri,
    required this.glossaryMap, required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              item: item, treeUri: treeUri,
              glossaryMap: glossaryMap, allItems: allItems,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64, height: 64,
                  child: item.images.isNotEmpty
                      ? _ThumbnailImage(treeUri: treeUri, path: item.images.first.path)
                      : const _NoThumb(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _CardMeta(item: item),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMeta extends StatelessWidget {
  final UxoItem item;
  const _CardMeta({required this.item});

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (item.category.isNotEmpty) item.category,
      if (item.country.isNotEmpty) item.country,
    ];
    return Wrap(
      spacing: 6, runSpacing: 4,
      children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(c, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        if (item.images.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.deepOrange.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${item.images.length} image${item.images.length > 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 12, color: Colors.deepOrange.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THUMBNAIL IMAGE
// ─────────────────────────────────────────────────────────────────────────────

class _ThumbnailImage extends StatefulWidget {
  final String treeUri, path;
  const _ThumbnailImage({required this.treeUri, required this.path});
  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = NativeFolderReader.cacheImage(treeUri: widget.treeUri, path: widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFFEEEEEE),
            child: Center(child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
          );
        }
        if (snap.hasError || snap.data == null) return const _NoThumb();
        final file = File(snap.data!);
        if (!file.existsSync()) return const _NoThumb();
        return Image.file(
          file, fit: BoxFit.cover, width: 64, height: 64,
          cacheWidth: 128,
          errorBuilder: (_, __, ___) => const _NoThumb(),
        );
      },
    );
  }
}

class _NoThumb extends StatelessWidget {
  const _NoThumb();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFFEEEEEE),
        child: Center(child: Icon(Icons.image_not_supported, size: 24, color: Colors.black38)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORIES VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriesView extends StatelessWidget {
  final Map<String, List<UxoItem>> byCategory;
  final String treeUri;
  final Map<String, GlossaryItem> glossaryMap;
  final List<UxoItem> allItems;

  const _CategoriesView({
    required this.byCategory, required this.treeUri,
    required this.glossaryMap, required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    final entries = byCategory.entries.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return RepaintBoundary(
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: Colors.deepOrange.shade50,
                child: Icon(Icons.category, color: Colors.deepOrange.shade700, size: 20),
              ),
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${entry.value.length} fiche${entry.value.length > 1 ? 's' : ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _CategoryScreen(
                    title: entry.key, items: entry.value, treeUri: treeUri,
                    glossaryMap: glossaryMap, allItems: allItems,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOSSARY VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _GlossaryView extends StatelessWidget {
  final List<GlossaryItem> glossary;
  const _GlossaryView({required this.glossary});

  @override
  Widget build(BuildContext context) {
    final sorted = glossary.toList()
      ..sort((a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final term = sorted[index];
        return RepaintBoundary(
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFF0F2F5),
                child: Text(
                  term.term.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
                ),
              ),
              title: Text(term.term, style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text(
                term.fullName.trim().isEmpty ? term.description : term.fullName,
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _showGlossaryDialog(context, term),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAFETY VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _SafetyView extends StatelessWidget {
  const _SafetyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _InfoCard(
          title: '⚠ Consignes principales',
          child: Text(
            'Cette application sert uniquement à la consultation hors ligne.\n\n'
            'Ne pas toucher, déplacer, démonter, transporter, nettoyer ou tenter '
            'de neutraliser une munition ou un objet suspect.\n\n'
            'Éloignez-vous, empêchez les autres personnes de s’approcher et '
            'contactez les autorités compétentes.',
            style: TextStyle(height: 1.5),
          ),
        ),
        _InfoCard(
          title: 'Limites',
          child: Text(
            'Les informations peuvent être incomplètes ou incorrectes. '
            'Elles ne remplacent jamais une procédure officielle ou '
            'l’intervention de spécialistes qualifiés.',
            style: TextStyle(height: 1.5),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER STATS
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderStats extends StatelessWidget {
  final UxoDatabase database;
  const _HeaderStats({required this.database});

  @override
  Widget build(BuildContext context) {
    final imageCount = database.items.where((e) => e.images.isNotEmpty).length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepOrange.shade100),
      ),
      child: Wrap(
        spacing: 8, runSpacing: 6,
        children: [
          _StatChip(appVersionLabel, Icons.info_outline),
          _StatChip('${database.items.length} fiches', Icons.list_alt),
          _StatChip('$imageCount avec image', Icons.image),
          _StatChip('${database.glossary.length} termes', Icons.menu_book),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _StatChip(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.deepOrange.shade700),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13, color: Colors.deepOrange.shade900,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB SELECTOR
// ─────────────────────────────────────────────────────────────────────────────

class _TabSelector extends StatelessWidget {
  final ScreenTab selected;
  final ValueChanged<ScreenTab> onChanged;
  const _TabSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          _tabBtn('Fiches', Icons.list_alt, ScreenTab.fiches),
          _tabBtn('Catégories', Icons.category, ScreenTab.categories),
          _tabBtn('Lexique', Icons.menu_book, ScreenTab.lexique),
          _tabBtn('Sécurité', Icons.warning_amber, ScreenTab.securite),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, IconData icon, ScreenTab value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      child: ChoiceChip(
        selected: selected == value,
        avatar: Icon(icon, size: 17),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onSelected: (_) => onChanged(value),
        showCheckmark: false,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryScreen extends StatelessWidget {
  final String title;
  final List<UxoItem> items;
  final String treeUri;
  final Map<String, GlossaryItem> glossaryMap;
  final List<UxoItem> allItems;

  const _CategoryScreen({
    required this.title, required this.items, required this.treeUri,
    required this.glossaryMap, required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = items.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: sorted.length,
        itemBuilder: (context, index) => RepaintBoundary(
          child: _UxoCard(
            item: sorted[index], treeUri: treeUri,
            glossaryMap: glossaryMap, allItems: allItems,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class DetailScreen extends StatelessWidget {
  final UxoItem item;
  final String treeUri;
  final Map<String, GlossaryItem> glossaryMap;
  final List<UxoItem> allItems;

  const DetailScreen({
    super.key, required this.item, required this.treeUri,
    required this.glossaryMap, required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    final similar = _findSimilarItems(item, allItems, limit: 6);
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (item.images.isNotEmpty)
            _ImageGallery(item: item, treeUri: treeUri)
          else
            const _MissingImageBox(),
          const SizedBox(height: 14),

          _InfoCard(
            title: 'Description',
            child: item.description.isEmpty
                ? const Text('Aucune description disponible.',
                    style: TextStyle(height: 1.5))
                : _LinkedText(
                    text: item.description,
                    keywords: item.keywords,
                    glossaryMap: glossaryMap,
                  ),
          ),

          _InfoCard(
            title: 'Identification',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(label: 'Nom', value: item.name),
                _InfoLine(label: 'Catégorie', value: item.category),
                _InfoLine(label: 'Type', value: item.type),
                _InfoLine(label: 'Pays', value: item.country),
                _InfoLine(label: 'Slug', value: item.slug),
              ],
            ),
          ),

          if (item.variants.isNotEmpty)
            _InfoCard(
              title: 'Variantes',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: item.variants.map((e) => Chip(label: Text(e))).toList(),
              ),
            ),

          if (similar.isNotEmpty)
            _InfoCard(
              title: 'Objets similaires',
              child: Column(
                children: similar.map((other) => _SimilarTile(
                  item: other, treeUri: treeUri,
                  glossaryMap: glossaryMap, allItems: allItems,
                )).toList(),
              ),
            ),

          _InfoCard(
            title: '⚠ Sécurité',
            child: _LinkedText(
              text: item.safetyNoticeFr.isEmpty
                  ? 'Ne pas toucher, déplacer, démonter, transporter ou tenter de '
                      'neutraliser un objet suspect. Éloignez-vous et contactez '
                      'les autorités compétentes.'
                  : item.safetyNoticeFr,
              keywords: item.keywords,
              glossaryMap: glossaryMap,
              baseStyle: const TextStyle(height: 1.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE GALLERY
// ─────────────────────────────────────────────────────────────────────────────

class _ImageGallery extends StatefulWidget {
  final UxoItem item;
  final String treeUri;
  const _ImageGallery({required this.item, required this.treeUri});
  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final images = widget.item.images;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 260,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) => _FullImage(
                treeUri: widget.treeUri, path: images[index].path,
              ),
            ),
          ),
        ),
        if (images[_currentPage].caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              images[_currentPage].caption,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        if (images.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) {
                return GestureDetector(
                  onTap: () => _pageCtrl.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? const Color(0xFFD84315)
                          : Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _FullImage extends StatefulWidget {
  final String treeUri, path;
  const _FullImage({required this.treeUri, required this.path});
  @override
  State<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends State<_FullImage> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = NativeFolderReader.cacheImage(treeUri: widget.treeUri, path: widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFFEEEEEE),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || snap.data == null) return const _MissingImageBox();
        final file = File(snap.data!);
        if (!file.existsSync()) return const _MissingImageBox();
        return ColoredBox(
          color: Colors.white,
          child: Image.file(file, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _MissingImageBox()),
        );
      },
    );
  }
}

class _MissingImageBox extends StatelessWidget {
  const _MissingImageBox();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('Image non disponible', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIMILAR TILE
// ─────────────────────────────────────────────────────────────────────────────

class _SimilarTile extends StatelessWidget {
  final UxoItem item;
  final String treeUri;
  final Map<String, GlossaryItem> glossaryMap;
  final List<UxoItem> allItems;

  const _SimilarTile({
    required this.item, required this.treeUri,
    required this.glossaryMap, required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 46, height: 46,
          child: item.images.isNotEmpty
              ? _ThumbnailImage(treeUri: treeUri, path: item.images.first.path)
              : const _NoThumb(),
        ),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(item.category.isEmpty ? 'Fiche similaire' : item.category,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            item: item, treeUri: treeUri,
            glossaryMap: glossaryMap, allItems: allItems,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE UI WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.2,
            )),
            const SizedBox(height: 10),
            DefaultTextStyle(
              style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.45),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label, value;
  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label : ', style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: value),
      ])),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chargement…', style: TextStyle(color: Colors.black54)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onChoose;
  const _EmptyState({required this.onChoose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.deepOrange.shade300),
                const SizedBox(height: 18),
                const Text('Aucun dossier sélectionné',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                const Text(
                  'Choisis le dossier catuxo_offline_pack dans Téléchargements. '
                  'Il doit contenir catuxo_database.json et le dossier images.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onChoose,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choisir le dossier'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

void _showGlossaryDialog(BuildContext context, GlossaryItem item) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(item.term),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.fullName.isNotEmpty) ...[
              const Text('Nom complet', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(item.fullName),
              const SizedBox(height: 12),
            ],
            const Text('Catégorie', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(item.category.isEmpty ? 'Non renseigné' : item.category),
            const SizedBox(height: 12),
            const Text('Définition', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(item.description.isEmpty ? 'Définition non disponible.' : item.description),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LINKED TEXT — mots-clés détectés inline avec hyperliens cliquables
// ─────────────────────────────────────────────────────────────────────────────

class _LinkedText extends StatelessWidget {
  final String text;
  final List<String> keywords;
  final Map<String, GlossaryItem> glossaryMap;
  final TextStyle? baseStyle;

  const _LinkedText({
    required this.text,
    required this.keywords,
    required this.glossaryMap,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return Text('Aucun contenu disponible.', style: _effectiveBase);
    }
    if (keywords.isEmpty) {
      return Text(text, style: _effectiveBase);
    }
    final spans = _buildSpans(context);
    return Text.rich(TextSpan(children: spans, style: _effectiveBase));
  }

  TextStyle get _effectiveBase =>
      (baseStyle ?? const TextStyle()).copyWith(height: 1.5, fontSize: 15);

  List<InlineSpan> _buildSpans(BuildContext context) {
    final sortedKw = keywords
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    if (sortedKw.isEmpty) {
      return [TextSpan(text: text)];
    }

    final lowerText = text.toLowerCase();
    final spans = <InlineSpan>[];
    var cursor = 0;

    while (cursor < text.length) {
      int bestStart = -1;
      String? bestKeyword;

      for (final keyword in sortedKw) {
        final lowerKeyword = keyword.toLowerCase();
        var pos = lowerText.indexOf(lowerKeyword, cursor);

        while (pos != -1) {
          final end = pos + lowerKeyword.length;

          final beforeOk = pos == 0 || !_isKeywordChar(text[pos - 1]);
          final afterOk = end >= text.length || !_isKeywordChar(text[end]);

          if (beforeOk && afterOk) {
            if (bestStart == -1 || pos < bestStart) {
              bestStart = pos;
              bestKeyword = text.substring(pos, end);
            }
            break;
          }

          pos = lowerText.indexOf(lowerKeyword, pos + 1);
        }
      }

      if (bestStart == -1 || bestKeyword == null) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }

      if (bestStart > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, bestStart)));
      }

      final info = _resolveKeyword(bestKeyword, glossaryMap.values);

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => _showGlossaryDialog(context, info.toGlossaryItem()),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFFD84315).withOpacity(0.7),
                    width: 1.5,
                  ),
                ),
              ),
              child: Text(
                bestKeyword,
                style: _effectiveBase.copyWith(
                  color: const Color(0xFFD84315),
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      );

      cursor = bestStart + bestKeyword.length;
    }

    return spans;
  }
}

bool _isKeywordChar(String char) {
  return RegExp(r'[A-Za-z0-9À-ÿ-]').hasMatch(char);
}

// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS LOGIC HELPERS
// ─────────────────────────────────────────────────────────────────────────────

KeywordInfo _resolveKeyword(String keyword, Iterable<GlossaryItem> glossary) {
  final normalized = normalizeSearch(keyword);
  final direct = keywordInfoMap[keyword.trim().toUpperCase()] ??
      keywordInfoMap[normalized.toUpperCase()];
  if (direct != null) return direct;
  for (final item in glossary) {
    if (normalizeSearch(item.term) == normalized ||
        normalizeSearch(item.fullName) == normalized) {
      return KeywordInfo(
        term: item.term, fullName: item.fullName,
        category: item.category, description: item.description,
      );
    }
  }
  return KeywordInfo(
    term: keyword, fullName: '', category: 'Terme technique',
    description: 'Terme technique présent dans la fiche. '
        'Définition détaillée non encore renseignée dans le lexique local.',
  );
}

List<UxoItem> _findSimilarItems(UxoItem item, List<UxoItem> allItems, {int limit = 6}) {
  final scored = allItems
      .where((o) => o.id != item.id)
      .map((o) => MapEntry(o, _similarityScore(item, o)))
      .where((e) => e.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return scored.take(limit).map((e) => e.key).toList();
}

int _similarityScore(UxoItem a, UxoItem b) {
  var score = 0;
  if (a.category.isNotEmpty && a.category == b.category) score += 70;
  if (a.type.isNotEmpty && a.type == b.type) score += 40;
  if (a.country.isNotEmpty && a.country == b.country) score += 10;
  return score;
}

// ─────────────────────────────────────────────────────────────────────────────
// STRING / JSON UTILITIES
// ─────────────────────────────────────────────────────────────────────────────

List<dynamic> asList(dynamic value) => value is List ? value : const [];

String textOf(dynamic value) => value == null ? '' : '$value'.trim();

String textFromObject(dynamic value, {String fallback = ''}) {
  if (value is Map) {
    return firstNotEmpty([
      textOf(value['name']), textOf(value['title']),
      textOf(value['slug']), fallback,
    ]);
  }
  final t = textOf(value);
  return t.isEmpty ? fallback : t;
}

List<String> asStringList(dynamic value) =>
    asList(value).map((e) => textOf(e)).where((e) => e.isNotEmpty).toList();

String firstNotEmpty(List<String> values) {
  for (final v in values) {
    final t = v.trim();
    if (t.isNotEmpty && t != 'null') return t;
  }
  return '';
}

String normalizeSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9À-ÿ]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String cleanText(String input) => input
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
