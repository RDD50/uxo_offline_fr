import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),
      home: const HomeScreen(),
    );
  }
}

class NativeFolderReader {
  static const MethodChannel _channel = MethodChannel(
    'uxo_offline_fr/folder_reader',
  );

  static final Map<String, Future<Uint8List>> _bytesCache = {};

  static Future<String?> pickFolder() async {
    return _channel.invokeMethod<String>('pickFolder');
  }

  static Future<String> copyDatabaseToCache({
    required String treeUri,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'copyDatabaseToCache',
      {'treeUri': treeUri},
    );

    if (result == null || result.trim().isEmpty) {
      throw Exception('Copie locale impossible : catuxo_database.json');
    }

    return result;
  }

  static Future<Uint8List> readBytes({
    required String treeUri,
    required String path,
  }) {
    final key = '$treeUri|$path';

    return _bytesCache.putIfAbsent(key, () async {
      final result = await _channel.invokeMethod<Uint8List>(
        'readBytes',
        {'treeUri': treeUri, 'path': path},
      );

      if (result == null) {
        throw Exception('Image illisible : $path');
      }

      return result;
    });
  }

  static void clearImageCache() {
    _bytesCache.clear();
  }
}

class FolderConfig {
  static const String fileName = 'selected_folder_uri.txt';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  static Future<String?> load() async {
    final file = await _file();

    if (!await file.exists()) {
      return null;
    }

    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  static Future<void> save(String uri) async {
    final file = await _file();
    await file.writeAsString(uri);
  }

  static Future<void> clear() async {
    final file = await _file();

    if (await file.exists()) {
      await file.delete();
    }
  }
}

class UxoDatabase {
  final List<UxoItem> items;
  final List<GlossaryItem> glossary;
  final int count;

  const UxoDatabase({
    required this.items,
    required this.glossary,
    required this.count,
  });

  factory UxoDatabase.fromJson(Map<String, dynamic> json) {
    final rawItems = asList(json['items']);
    final rawGlossary = asList(json['glossary']);

    final items = rawItems
        .whereType<Map>()
        .map((e) => UxoItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.name.trim().isNotEmpty)
        .toList();

    final glossary = rawGlossary
        .whereType<Map>()
        .map((e) => GlossaryItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.term.trim().isNotEmpty)
        .toList();

    return UxoDatabase(
      items: items,
      glossary: glossary,
      count: asInt(json['count'], fallback: items.length),
    );
  }
}

class UxoItem {
  final String id;
  final String name;
  final String slug;
  final String category;
  final String categorySlug;
  final String type;
  final String country;
  final String description;
  final String sourceUrl;
  final List<String> keywords;
  final List<String> variants;
  final List<UxoImage> images;
  final Map<String, dynamic> raw;

  const UxoItem({
    required this.id,
    required this.name,
    required this.slug,
    required this.category,
    required this.categorySlug,
    required this.type,
    required this.country,
    required this.description,
    required this.sourceUrl,
    required this.keywords,
    required this.variants,
    required this.images,
    required this.raw,
  });

  factory UxoItem.fromJson(Map<String, dynamic> json) {
    final categoryObj = json['category'];
    final typeObj = json['type'];
    final countryObj = json['country'];

    final images = asList(json['images'])
        .whereType<Map>()
        .map((e) => UxoImage.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.path.trim().isNotEmpty)
        .toList();

    final keywords = <String>{
      ...asStringList(json['technologyKeywords']),
      ...asStringList(json['keywords']),
      ...asList(json['meta_keys'])
          .whereType<Map>()
          .map((e) => textOf(e['name']))
          .where((e) => e.trim().isNotEmpty),
    }.toList();

    final variants = <String>{
      ...asStringList(json['variants']),
      ...asStringList(json['aliases']),
    }.toList();

    return UxoItem(
      id: textOf(json['id']),
      name: textOf(json['name']),
      slug: textOf(json['slug']),
      category: textFromObject(categoryObj, fallback: textOf(json['categoryName'])),
      categorySlug: slugFromObject(categoryObj),
      type: textFromObject(typeObj, fallback: textOf(json['typeName'])),
      country: textFromObject(countryObj, fallback: textOf(json['countryName'])),
      description: cleanText(
        firstNotEmpty([
          textOf(json['descriptionText']),
          textOf(json['description']),
          textOf(json['html']),
          textOf(json['content']),
          textOf(json['body']),
        ]),
      ),
      sourceUrl: firstNotEmpty([
        textOf(json['sourceUrl']),
        textOf(json['permalink']),
        textOf(json['url']),
      ]),
      keywords: keywords,
      variants: variants,
      images: images,
      raw: json,
    );
  }
}

class UxoImage {
  final String path;
  final String caption;
  final bool placeholder;

  const UxoImage({
    required this.path,
    required this.caption,
    required this.placeholder,
  });

  factory UxoImage.fromJson(Map<String, dynamic> json) {
    return UxoImage(
      path: firstNotEmpty([
        textOf(json['path']),
        textOf(json['localPath']),
        textOf(json['file']),
      ]),
      caption: firstNotEmpty([
        textOf(json['caption']),
        textOf(json['filename']),
      ]),
      placeholder: json['placeholder'] == true,
    );
  }
}

class GlossaryItem {
  final String term;
  final String fullName;
  final String category;
  final String description;

  const GlossaryItem({
    required this.term,
    required this.fullName,
    required this.category,
    required this.description,
  });

  factory GlossaryItem.fromJson(Map<String, dynamic> json) {
    return GlossaryItem(
      term: firstNotEmpty([
        textOf(json['term']),
        textOf(json['name']),
      ]),
      fullName: firstNotEmpty([
        textOf(json['fullName']),
        textOf(json['full_name']),
      ]),
      category: textOf(json['category']),
      description: cleanText(
        firstNotEmpty([
          textOf(json['shortDescription']),
          textOf(json['description']),
          textOf(json['definition']),
        ]),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ScreenTab {
  fiches,
  categories,
  lexique,
  securite,
}

class _HomeScreenState extends State<HomeScreen> {
  String? treeUri;
  UxoDatabase? database;
  bool loading = true;
  String query = '';
  ScreenTab tab = ScreenTab.fiches;

  @override
  void initState() {
    super.initState();
    loadSavedFolder();
  }

  Future<void> loadSavedFolder() async {
    setState(() => loading = true);

    try {
      final saved = await FolderConfig.load();

      if (saved == null) {
        setState(() {
          treeUri = null;
          database = null;
        });
        return;
      }

      await loadDatabase(saved);
    } catch (e) {
      await FolderConfig.clear();

      if (mounted) {
        showMessage('Dossier oublié : $e');
      }

      setState(() {
        treeUri = null;
        database = null;
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
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
      await loadDatabase(selected);
    } catch (e) {
      if (mounted) {
        showMessage('Erreur dossier : $e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadDatabase(String uri) async {
    final cachePath = await NativeFolderReader.copyDatabaseToCache(
      treeUri: uri,
    );

    final text = await File(cachePath).readAsString();
    final decoded = jsonDecode(text);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('catuxo_database.json invalide.');
    }

    final db = UxoDatabase.fromJson(decoded);

    setState(() {
      treeUri = uri;
      database = db;
      query = '';
      tab = ScreenTab.fiches;
    });
  }

  Future<void> resetFolder() async {
    await FolderConfig.clear();

    setState(() {
      treeUri = null;
      database = null;
      query = '';
      tab = ScreenTab.fiches;
    });
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  List<UxoItem> get filteredItems {
    final db = database;

    if (db == null) {
      return [];
    }

    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      return db.items;
    }

    return db.items.where((item) {
      return item.name.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q) ||
          item.type.toLowerCase().contains(q) ||
          item.country.toLowerCase().contains(q) ||
          item.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  Map<String, List<UxoItem>> get byCategory {
    final db = database;
    final map = <String, List<UxoItem>>{};

    if (db == null) {
      return map;
    }

    for (final item in db.items) {
      final key = item.category.trim().isEmpty ? 'Non classé' : item.category;
      map.putIfAbsent(key, () => []);
      map[key]!.add(item);
    }

    final entries = map.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return Map.fromEntries(entries);
  }

  Map<String, GlossaryItem> get glossaryMap {
    final db = database;

    if (db == null) {
      return {};
    }

    return {
      for (final item in db.glossary) item.term.toLowerCase(): item,
    };
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
          IconButton(
            tooltip: 'Réinitialiser',
            onPressed: loading ? null : resetFolder,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : db == null
              ? EmptyState(onChoose: chooseFolder)
              : Column(
                  children: [
                    HeaderStats(database: db),
                    TabSelector(
                      selected: tab,
                      onChanged: (value) => setState(() => tab = value),
                    ),
                    Expanded(
                      child: switch (tab) {
                        ScreenTab.fiches => buildListView(),
                        ScreenTab.categories => buildCategoriesView(),
                        ScreenTab.lexique => buildGlossaryView(db),
                        ScreenTab.securite => const SafetyView(),
                      },
                    ),
                  ],
                ),
    );
  }

  Widget buildListView() {
    final items = filteredItems;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Rechercher une fiche',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${items.length} fiche(s)',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              return UxoListTile(
                item: items[index],
                treeUri: treeUri!,
                glossary: glossaryMap,
                allItems: database!.items,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildCategoriesView() {
    final entries = byCategory.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(
              entry.key,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('${entry.value.length} fiche(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryScreen(
                    title: entry.key,
                    items: entry.value,
                    treeUri: treeUri!,
                    glossary: glossaryMap,
                    allItems: database!.items,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget buildGlossaryView(UxoDatabase db) {
    final terms = db.glossary.toList()
      ..sort((a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: terms.length,
      itemBuilder: (context, index) {
        final term = terms[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(
              term.term,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              term.fullName.trim().isEmpty ? term.description : term.fullName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => showGlossaryDialog(context, term),
          ),
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  final VoidCallback onChoose;

  const EmptyState({
    super.key,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 58),
              const SizedBox(height: 16),
              const Text(
                'Aucun dossier sélectionné',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Choisis le dossier catuxo_offline_pack dans Téléchargements. '
                'Il doit contenir catuxo_database.json et le dossier images.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onChoose,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choisir le dossier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HeaderStats extends StatelessWidget {
  final UxoDatabase database;

  const HeaderStats({
    super.key,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    final imageCount = database.items.where((e) => e.images.isNotEmpty).length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(label: Text('Fiches : ${database.items.length}')),
          Chip(label: Text('Images : $imageCount')),
          Chip(label: Text('Lexique : ${database.glossary.length}')),
        ],
      ),
    );
  }
}

class TabSelector extends StatelessWidget {
  final ScreenTab selected;
  final ValueChanged<ScreenTab> onChanged;

  const TabSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          tabButton('Fiches', Icons.list, ScreenTab.fiches),
          tabButton('Catégories', Icons.category, ScreenTab.categories),
          tabButton('Lexique', Icons.menu_book, ScreenTab.lexique),
          tabButton('Sécurité', Icons.warning_amber, ScreenTab.securite),
        ],
      ),
    );
  }

  Widget tabButton(String label, IconData icon, ScreenTab value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected == value,
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onSelected: (_) => onChanged(value),
      ),
    );
  }
}

class UxoListTile extends StatelessWidget {
  final UxoItem item;
  final String treeUri;
  final Map<String, GlossaryItem> glossary;
  final List<UxoItem> allItems;

  const UxoListTile({
    super.key,
    required this.item,
    required this.treeUri,
    required this.glossary,
    required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (item.category.trim().isNotEmpty) item.category,
      if (item.country.trim().isNotEmpty) item.country,
      if (item.images.isNotEmpty) 'image',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ListTile(
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle.isEmpty ? 'Fiche UXO' : subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                item: item,
                treeUri: treeUri,
                glossary: glossary,
                allItems: allItems,
              ),
            ),
          );
        },
      ),
    );
  }
}

class CategoryScreen extends StatelessWidget {
  final String title;
  final List<UxoItem> items;
  final String treeUri;
  final Map<String, GlossaryItem> glossary;
  final List<UxoItem> allItems;

  const CategoryScreen({
    super.key,
    required this.title,
    required this.items,
    required this.treeUri,
    required this.glossary,
    required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = items.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          return UxoListTile(
            item: sorted[index],
            treeUri: treeUri,
            glossary: glossary,
            allItems: allItems,
          );
        },
      ),
    );
  }
}

class DetailScreen extends StatelessWidget {
  final UxoItem item;
  final String treeUri;
  final Map<String, GlossaryItem> glossary;
  final List<UxoItem> allItems;

  const DetailScreen({
    super.key,
    required this.item,
    required this.treeUri,
    required this.glossary,
    required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          UxoImageView(item: item, treeUri: treeUri),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Description',
            child: Text(
              item.description.trim().isEmpty
                  ? 'Aucune description disponible.'
                  : item.description,
              style: const TextStyle(height: 1.45),
            ),
          ),
          InfoCard(
            title: 'Identification',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoLine(label: 'Nom', value: item.name),
                InfoLine(label: 'Catégorie', value: item.category),
                InfoLine(label: 'Type', value: item.type),
                InfoLine(label: 'Pays', value: item.country),
                InfoLine(label: 'Slug', value: item.slug),
              ],
            ),
          ),
          if (item.variants.isNotEmpty)
            InfoCard(
              title: 'Variantes',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: item.variants
                    .map((e) => Chip(label: Text(e)))
                    .toList(),
              ),
            ),
          InfoCard(
            title: 'Mots-clés',
            child: item.keywords.isEmpty
                ? const Text('Aucun mot-clé disponible.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.keywords.map((keyword) {
                      final term = findGlossaryTerm(keyword, glossary.values);

                      return ActionChip(
                        label: Text(keyword),
                        onPressed: () {
                          if (term == null) {
                            showGlossaryDialog(
                              context,
                              GlossaryItem(
                                term: keyword,
                                fullName: '',
                                category: 'Non trouvé',
                                description: fallbackGlossaryDefinition(keyword),
                              ),
                            );
                            return;
                          }

                          showGlossaryDialog(context, term);
                        },
                      );
                    }).toList(),
                  ),
          ),
          SimilarItemsCard(
            item: item,
            allItems: allItems,
            treeUri: treeUri,
            glossary: glossary,
          ),
          const InfoCard(
            title: 'Sécurité',
            child: Text(
              'Ne pas toucher, déplacer, démonter, transporter ou tenter de neutraliser un objet suspect. '
              'Éloignez-vous et contactez les autorités compétentes.',
              style: TextStyle(
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class SimilarItemsCard extends StatelessWidget {
  final UxoItem item;
  final List<UxoItem> allItems;
  final String treeUri;
  final Map<String, GlossaryItem> glossary;

  const SimilarItemsCard({
    super.key,
    required this.item,
    required this.allItems,
    required this.treeUri,
    required this.glossary,
  });

  @override
  Widget build(BuildContext context) {
    final similar = allItems
        .where((other) => other.id != item.id)
        .map((other) => MapEntry(other, similarityScore(item, other)))
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = similar.take(6).map((e) => e.key).toList();

    if (selected.isEmpty) {
      return const InfoCard(
        title: 'Similaire',
        child: Text('Aucun objet similaire trouvé.'),
      );
    }

    return InfoCard(
      title: 'Similaire',
      child: SizedBox(
        height: 178,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: selected.length,
          itemBuilder: (context, index) {
            final other = selected[index];
            return SimilarItemTile(
              item: other,
              treeUri: treeUri,
              glossary: glossary,
              allItems: allItems,
            );
          },
        ),
      ),
    );
  }
}

class SimilarItemTile extends StatelessWidget {
  final UxoItem item;
  final String treeUri;
  final Map<String, GlossaryItem> glossary;
  final List<UxoItem> allItems;

  const SimilarItemTile({
    super.key,
    required this.item,
    required this.treeUri,
    required this.glossary,
    required this.allItems,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                item: item,
                treeUri: treeUri,
                glossary: glossary,
                allItems: allItems,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SimilarThumb(item: item, treeUri: treeUri),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (item.category.trim().isNotEmpty)
                Text(
                  item.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SimilarThumb extends StatelessWidget {
  final UxoItem item;
  final String treeUri;

  const SimilarThumb({
    super.key,
    required this.item,
    required this.treeUri,
  });

  @override
  Widget build(BuildContext context) {
    if (item.images.isEmpty) {
      return thumbBox(const Icon(Icons.image_not_supported));
    }

    return FutureBuilder<Uint8List>(
      future: NativeFolderReader.readBytes(
        treeUri: treeUri,
        path: item.images.first.path,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              snapshot.data!,
              width: 122,
              height: 96,
              fit: BoxFit.cover,
            ),
          );
        }

        return thumbBox(
          snapshot.hasError
              ? const Icon(Icons.broken_image)
              : const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        );
      },
    );
  }

  Widget thumbBox(Widget child) {
    return Container(
      width: 122,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class UxoImageView extends StatelessWidget {
  final UxoItem item;
  final String treeUri;

  const UxoImageView({
    super.key,
    required this.item,
    required this.treeUri,
  });

  @override
  Widget build(BuildContext context) {
    if (item.images.isEmpty) {
      return const MissingImageBox();
    }

    final image = item.images.first;

    return FutureBuilder<Uint8List>(
      future: NativeFolderReader.readBytes(
        treeUri: treeUri,
        path: image.path,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const MissingImageBox();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: Colors.white,
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }
}

class MissingImageBox extends StatelessWidget {
  const MissingImageBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported, size: 48),
          SizedBox(height: 8),
          Text('Image non disponible'),
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const InfoCard({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 15.5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const InfoLine({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class SafetyView extends StatelessWidget {
  const SafetyView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        InfoCard(
          title: 'Consignes principales',
          child: Text(
            'Cette application sert uniquement à la consultation hors ligne.\n\n'
            'Ne pas toucher, déplacer, démonter, transporter, nettoyer ou tenter de neutraliser une munition ou un objet suspect.\n\n'
            'Éloignez-vous, empêchez les autres personnes de s’approcher et contactez les autorités compétentes.',
            style: TextStyle(height: 1.5),
          ),
        ),
        InfoCard(
          title: 'Limites',
          child: Text(
            'Les informations peuvent être incomplètes ou incorrectes. '
            'Elles ne remplacent jamais une procédure officielle ou l’intervention de spécialistes qualifiés.',
            style: TextStyle(height: 1.5),
          ),
        ),
      ],
    );
  }
}

void showGlossaryDialog(BuildContext context, GlossaryItem item) {
  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        title: Text(item.term),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.fullName.trim().isNotEmpty) ...[
                const Text(
                  'Nom complet',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(item.fullName),
                const SizedBox(height: 12),
              ],
              const Text(
                'Catégorie',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                item.category.trim().isEmpty
                    ? 'Non renseigné'
                    : item.category,
              ),
              const SizedBox(height: 12),
              const Text(
                'Définition',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                item.description.trim().isEmpty
                    ? 'Définition non disponible.'
                    : item.description,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      );
    },
  );
}

List<dynamic> asList(dynamic value) {
  if (value is List) {
    return value;
  }

  return const [];
}

int asInt(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse('$value') ?? fallback;
}

String textOf(dynamic value) {
  if (value == null) {
    return '';
  }

  return '$value'.trim();
}

String textFromObject(dynamic value, {String fallback = ''}) {
  if (value is Map) {
    return firstNotEmpty([
      textOf(value['name']),
      textOf(value['title']),
      textOf(value['slug']),
      fallback,
    ]);
  }

  final text = textOf(value);
  return text.isEmpty ? fallback : text;
}

String slugFromObject(dynamic value) {
  if (value is Map) {
    return textOf(value['slug']);
  }

  return '';
}

List<String> asStringList(dynamic value) {
  return asList(value)
      .map((e) => textOf(e))
      .where((e) => e.trim().isNotEmpty)
      .toList();
}

String firstNotEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();

    if (trimmed.isNotEmpty && trimmed != 'null') {
      return trimmed;
    }
  }

  return '';
}


GlossaryItem? findGlossaryTerm(String keyword, Iterable<GlossaryItem> terms) {
  final q = normalizeSearch(keyword);

  if (q.isEmpty) {
    return null;
  }

  GlossaryItem? best;
  var bestScore = 0;

  for (final term in terms) {
    final termText = normalizeSearch(term.term);
    final fullText = normalizeSearch(term.fullName);
    final categoryText = normalizeSearch(term.category);
    final descriptionText = normalizeSearch(term.description);

    var score = 0;

    if (termText == q) score += 100;
    if (fullText == q) score += 90;
    if (termText.contains(q) || q.contains(termText)) score += 60;
    if (fullText.contains(q) || q.contains(fullText)) score += 45;
    if (categoryText.contains(q)) score += 15;
    if (descriptionText.contains(q)) score += 8;

    if (score > bestScore) {
      bestScore = score;
      best = term;
    }
  }

  return bestScore >= 8 ? best : null;
}

int similarityScore(UxoItem a, UxoItem b) {
  var score = 0;

  if (a.category.trim().isNotEmpty && a.category == b.category) {
    score += 70;
  }

  if (a.type.trim().isNotEmpty && a.type == b.type) {
    score += 40;
  }

  if (a.country.trim().isNotEmpty && a.country == b.country) {
    score += 10;
  }

  return score;
}


String fallbackGlossaryDefinition(String keyword) {
  final key = keyword.trim().toUpperCase();

  const definitions = {
    'HE': 'High Explosive. Charge explosive à effet de souffle ou de fragmentation selon le contexte.',
    'HEAT': 'High-Explosive Anti-Tank. Charge antichar à effet dirigé.',
    'HESH': 'High-Explosive Squash Head. Type de charge explosive utilisée contre surfaces dures ou blindées.',
    'AP': 'Armor-Piercing. Munition perforante.',
    'APERS': 'Anti-Personnel. Effet ou munition destiné aux personnes.',
    'AT': 'Anti-Tank. Munition ou système destiné aux cibles blindées.',
    'AA': 'Anti-Aircraft. Munition ou système destiné aux cibles aériennes.',
    'WP': 'White Phosphorus. Phosphore blanc.',
    'SMK': 'Smoke. Munition fumigène.',
    'ILLUM': 'Illumination. Munition éclairante.',
    'INC': 'Incendiary. Effet incendiaire.',
    'FRAG': 'Fragmentation. Effet de fragmentation.',
    'PD': 'Point Detonating. Fusée à action au point d’impact.',
    'BD': 'Base Detonating. Fusée située en base.',
    'SD': 'Self-Destruct. Fonction d’autodestruction.',
    'VT': 'Variable Time. Fusée temps variable ou proximité selon le contexte.',
    'MT': 'Mechanical Time. Fonction temps mécanique.',
    'UXO': 'Unexploded Ordnance. Munition explosive non explosée.',
    'ERW': 'Explosive Remnants of War. Restes explosifs de guerre.',
    'EOD': 'Explosive Ordnance Disposal. Traitement spécialisé des munitions explosives.',
    'IED': 'Improvised Explosive Device. Engin explosif improvisé.',
    'RPG': 'Rocket-Propelled Grenade. Grenade ou roquette propulsée.',
    'ATGM': 'Anti-Tank Guided Missile. Missile guidé antichar.',
    'MANPADS': 'Man-Portable Air-Defense System. Système portable de défense antiaérienne.',
    'AFV': 'Armoured Fighting Vehicle. Véhicule blindé de combat.',
  };

  return definitions[key] ??
      'Terme technique présent dans la fiche. Définition détaillée non encore renseignée dans le lexique local.';
}

String normalizeSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9À-ÿ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String cleanText(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
