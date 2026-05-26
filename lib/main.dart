
cd ~/uxo_offline_app

cat > lib/main.dart <<'DART'
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
  static const MethodChannel _channel =
      MethodChannel('uxo_offline_fr/folder_reader');

  static Future<String?> pickFolder() async {
    final result = await _channel.invokeMethod<String>('pickFolder');
    return result;
  }

  static Future<String> readText({
    required String treeUri,
    required String path,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'readText',
      {
        'treeUri': treeUri,
        'path': path,
      },
    );

    if (result == null) {
      throw Exception('Lecture texte impossible : $path');
    }

    return result;
  }

  static Future<Uint8List> readBytes({
    required String treeUri,
    required String path,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'readBytes',
      {
        'treeUri': treeUri,
        'path': path,
      },
    );

    if (result == null) {
      throw Exception('Lecture image impossible : $path');
    }

    return result;
  }
}

class FolderConfig {
  static const String fileName = 'selected_folder_uri.txt';

  static Future<File> _configFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  static Future<String?> loadTreeUri() async {
    final file = await _configFile();

    if (!await file.exists()) {
      return null;
    }

    final value = await file.readAsString();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  static Future<void> saveTreeUri(String treeUri) async {
    final file = await _configFile();
    await file.writeAsString(treeUri);
  }

  static Future<void> clear() async {
    final file = await _configFile();

    if (await file.exists()) {
      await file.delete();
    }
  }
}

class OfflineDatabase {
  final Map<String, dynamic> stats;
  final List<HazardItem> items;
  final List<GlossaryTerm> glossary;

  OfflineDatabase({
    required this.stats,
    required this.items,
    required this.glossary,
  });

  factory OfflineDatabase.fromJson(Map<String, dynamic> json) {
    return OfflineDatabase(
      stats: Map<String, dynamic>.from(json['stats'] ?? {}),
      items: ((json['items'] ?? []) as List)
          .whereType<Map>()
          .map((e) => HazardItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      glossary: ((json['glossary'] ?? []) as List)
          .whereType<Map>()
          .map((e) => GlossaryTerm.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class HazardItem {
  final String id;
  final String name;
  final String slug;
  final String category;
  final String categorySlug;
  final List<String> countries;
  final List<HazardImage> images;
  final String descriptionText;
  final Map<String, dynamic> identification;
  final List<String> variants;
  final List<String> technologyKeywords;
  final String sourceUrl;
  final String safetyNoticeFr;

  HazardItem({
    required this.id,
    required this.name,
    required this.slug,
    required this.category,
    required this.categorySlug,
    required this.countries,
    required this.images,
    required this.descriptionText,
    required this.identification,
    required this.variants,
    required this.technologyKeywords,
    required this.sourceUrl,
    required this.safetyNoticeFr,
  });

  factory HazardItem.fromJson(Map<String, dynamic> json) {
    return HazardItem(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      slug: '${json['slug'] ?? ''}',
      category: '${json['category'] ?? ''}',
      categorySlug: '${json['categorySlug'] ?? ''}',
      countries: ((json['countries'] ?? []) as List)
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      images: ((json['images'] ?? []) as List)
          .whereType<Map>()
          .map((e) => HazardImage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      descriptionText: stripHtml('${json['descriptionText'] ?? ''}'),
      identification:
          Map<String, dynamic>.from(json['identification'] ?? <String, dynamic>{}),
      variants: ((json['variants'] ?? []) as List).map((e) => '$e').toList(),
      technologyKeywords:
          ((json['technologyKeywords'] ?? []) as List).map((e) => '$e').toList(),
      sourceUrl: '${json['sourceUrl'] ?? ''}',
      safetyNoticeFr: '${json['safetyNoticeFr'] ?? ''}',
    );
  }
}

class HazardImage {
  final String path;
  final String caption;
  final bool isPrimary;
  final bool placeholder;

  HazardImage({
    required this.path,
    required this.caption,
    required this.isPrimary,
    required this.placeholder,
  });

  factory HazardImage.fromJson(Map<String, dynamic> json) {
    return HazardImage(
      path: '${json['path'] ?? ''}',
      caption: '${json['caption'] ?? ''}',
      isPrimary: json['isPrimary'] == true,
      placeholder: json['placeholder'] == true,
    );
  }
}

class GlossaryTerm {
  final String term;
  final String fullName;
  final String category;
  final String shortDescription;
  final List<String> appearsIn;

  GlossaryTerm({
    required this.term,
    required this.fullName,
    required this.category,
    required this.shortDescription,
    required this.appearsIn,
  });

  factory GlossaryTerm.fromJson(Map<String, dynamic> json) {
    return GlossaryTerm(
      term: '${json['term'] ?? ''}',
      fullName: '${json['fullName'] ?? ''}',
      category: '${json['category'] ?? ''}',
      shortDescription: '${json['shortDescription'] ?? ''}',
      appearsIn: ((json['appearsIn'] ?? []) as List).map((e) => '$e').toList(),
    );
  }
}

String stripHtml(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum HomeTab {
  fiches,
  categories,
  lexique,
  securite,
}

class _HomeScreenState extends State<HomeScreen> {
  String? treeUri;
  OfflineDatabase? database;
  bool loading = true;
  String query = '';
  HomeTab tab = HomeTab.fiches;

  @override
  void initState() {
    super.initState();
    loadSavedFolder();
  }

  Future<void> loadSavedFolder() async {
    setState(() {
      loading = true;
    });

    try {
      final savedUri = await FolderConfig.loadTreeUri();

      if (savedUri == null) {
        setState(() {
          treeUri = null;
          database = null;
        });
        return;
      }

      await loadDatabaseFromFolder(savedUri);
    } catch (e) {
      await FolderConfig.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lecture dossier : $e')),
        );
      }

      setState(() {
        treeUri = null;
        database = null;
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> chooseFolder() async {
    setState(() {
      loading = true;
    });

    try {
      final selectedUri = await NativeFolderReader.pickFolder();

      if (selectedUri == null || selectedUri.trim().isEmpty) {
        throw Exception('Aucun dossier sélectionné.');
      }

      await FolderConfig.saveTreeUri(selectedUri);
      await loadDatabaseFromFolder(selectedUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur sélection dossier : $e')),
        );
      }
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> loadDatabaseFromFolder(String selectedUri) async {
    final text = await NativeFolderReader.readText(
      treeUri: selectedUri,
      path: 'catuxo_database.json',
    );

    final jsonMap = jsonDecode(text) as Map<String, dynamic>;
    final db = OfflineDatabase.fromJson(jsonMap);

    setState(() {
      treeUri = selectedUri;
      database = db;
      tab = HomeTab.fiches;
      query = '';
    });
  }

  Future<void> resetFolder() async {
    await FolderConfig.clear();

    setState(() {
      treeUri = null;
      database = null;
      query = '';
      tab = HomeTab.fiches;
    });
  }

  List<HazardItem> get filteredItems {
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
          item.descriptionText.toLowerCase().contains(q) ||
          item.technologyKeywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  Map<String, List<HazardItem>> get itemsByCategory {
    final db = database;

    if (db == null) {
      return {};
    }

    final map = <String, List<HazardItem>>{};

    for (final item in db.items) {
      final category = item.category.trim().isEmpty ? 'Non classé' : item.category;
      map.putIfAbsent(category, () => []);
      map[category]!.add(item);
    }

    final entries = map.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return Map.fromEntries(entries);
  }

  Map<String, GlossaryTerm> get glossaryMap {
    final db = database;

    if (db == null) {
      return {};
    }

    return {
      for (final term in db.glossary) term.term.toLowerCase(): term,
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
            onPressed: loading ? null : chooseFolder,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Choisir le dossier de données',
          ),
          IconButton(
            onPressed: loading ? null : resetFolder,
            icon: const Icon(Icons.refresh),
            tooltip: 'Changer de dossier',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : db == null
              ? EmptyFolderView(onChooseFolder: chooseFolder)
              : Column(
                  children: [
                    DatabaseHeader(database: db),
                    NavigationTabs(
                      selected: tab,
                      onChanged: (value) {
                        setState(() {
                          tab = value;
                        });
                      },
                    ),
                    Expanded(
                      child: switch (tab) {
                        HomeTab.fiches => buildFichesView(db),
                        HomeTab.categories => buildCategoriesView(),
                        HomeTab.lexique => buildGlossaryView(db),
                        HomeTab.securite => const SafetyView(),
                      },
                    ),
                  ],
                ),
    );
  }

  Widget buildFichesView(OfflineDatabase db) {
    final items = filteredItems;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Rechercher une fiche, catégorie ou mot-clé',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                query = value;
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${items.length} fiche(s)',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              return HazardListCard(
                item: items[index],
                treeUri: treeUri!,
                glossaryMap: glossaryMap,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildCategoriesView() {
    final entries = itemsByCategory.entries.toList();

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
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${entry.value.length} fiche(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryScreen(
                    categoryName: entry.key,
                    items: entry.value,
                    treeUri: treeUri!,
                    glossaryMap: glossaryMap,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget buildGlossaryView(OfflineDatabase db) {
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
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              term.fullName.trim().isEmpty
                  ? term.shortDescription
                  : term.fullName,
            ),
            onTap: () {
              showGlossaryDialog(context, term);
            },
          ),
        );
      },
    );
  }
}

class EmptyFolderView extends StatelessWidget {
  final VoidCallback onChooseFolder;

  const EmptyFolderView({
    super.key,
    required this.onChooseFolder,
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
              const Icon(Icons.folder_open, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Aucun dossier de données sélectionné',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Choisis le dossier catuxo_offline_pack contenant catuxo_database.json et le dossier images.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onChooseFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choisir le dossier de données'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DatabaseHeader extends StatelessWidget {
  final OfflineDatabase database;

  const DatabaseHeader({
    super.key,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    final stats = database.stats;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          StatChip(
            label: 'Fiches',
            value: '${stats['items'] ?? database.items.length}',
          ),
          StatChip(
            label: 'Lexique',
            value: '${stats['glossaryTerms'] ?? database.glossary.length}',
          ),
          StatChip(
            label: 'Images',
            value: '${stats['downloadedImages'] ?? '-'}',
          ),
          StatChip(
            label: 'Placeholder',
            value: '${stats['placeholderImages'] ?? '-'}',
          ),
        ],
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  final String label;
  final String value;

  const StatChip({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label : $value'),
      backgroundColor: Colors.white,
    );
  }
}

class NavigationTabs extends StatelessWidget {
  final HomeTab selected;
  final ValueChanged<HomeTab> onChanged;

  const NavigationTabs({
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
          TabButton(
            label: 'Fiches',
            icon: Icons.list,
            selected: selected == HomeTab.fiches,
            onTap: () => onChanged(HomeTab.fiches),
          ),
          TabButton(
            label: 'Catégories',
            icon: Icons.category,
            selected: selected == HomeTab.categories,
            onTap: () => onChanged(HomeTab.categories),
          ),
          TabButton(
            label: 'Lexique',
            icon: Icons.menu_book,
            selected: selected == HomeTab.lexique,
            onTap: () => onChanged(HomeTab.lexique),
          ),
          TabButton(
            label: 'Sécurité',
            icon: Icons.warning_amber,
            selected: selected == HomeTab.securite,
            onTap: () => onChanged(HomeTab.securite),
          ),
        ],
      ),
    );
  }
}

class TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const TabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class HazardListCard extends StatelessWidget {
  final HazardItem item;
  final String treeUri;
  final Map<String, GlossaryTerm> glossaryMap;

  const HazardListCard({
    super.key,
    required this.item,
    required this.treeUri,
    required this.glossaryMap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ListTile(
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (item.category.trim().isNotEmpty) item.category,
            if (item.countries.isNotEmpty) item.countries.join(', '),
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HazardDetailScreen(
                item: item,
                treeUri: treeUri,
                glossaryMap: glossaryMap,
              ),
            ),
          );
        },
      ),
    );
  }
}

class CategoryScreen extends StatelessWidget {
  final String categoryName;
  final List<HazardItem> items;
  final String treeUri;
  final Map<String, GlossaryTerm> glossaryMap;

  const CategoryScreen({
    super.key,
    required this.categoryName,
    required this.items,
    required this.treeUri,
    required this.glossaryMap,
  });

  @override
  Widget build(BuildContext context) {
    final sortedItems = items.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
      ),
      body: ListView.builder(
        itemCount: sortedItems.length,
        itemBuilder: (context, index) {
          return HazardListCard(
            item: sortedItems[index],
            treeUri: treeUri,
            glossaryMap: glossaryMap,
          );
        },
      ),
    );
  }
}

class HazardDetailScreen extends StatelessWidget {
  final HazardItem item;
  final String treeUri;
  final Map<String, GlossaryTerm> glossaryMap;

  const HazardDetailScreen({
    super.key,
    required this.item,
    required this.treeUri,
    required this.glossaryMap,
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
          HazardMainImage(item: item, treeUri: treeUri),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Description',
            child: Text(
              item.descriptionText.trim().isEmpty
                  ? 'Aucune description disponible.'
                  : item.descriptionText,
              style: const TextStyle(height: 1.45),
            ),
          ),
          SectionCard(
            title: 'Identification',
            child: IdentificationView(item: item),
          ),
          if (item.variants.isNotEmpty)
            SectionCard(
              title: 'Variantes',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: item.variants
                    .map((v) => Chip(label: Text(v)))
                    .toList(),
              ),
            ),
          SectionCard(
            title: 'Technologie / mots-clés',
            child: item.technologyKeywords.isEmpty
                ? const Text('Aucun mot-clé technique détecté.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.technologyKeywords.map((keyword) {
                      final term = glossaryMap[keyword.toLowerCase()];

                      return ActionChip(
                        label: Text(keyword),
                        onPressed: term == null
                            ? null
                            : () {
                                showGlossaryDialog(context, term);
                              },
                      );
                    }).toList(),
                  ),
          ),
          SectionCard(
            title: 'Source',
            child: SelectableText(
              item.sourceUrl.trim().isEmpty
                  ? 'Source non disponible.'
                  : item.sourceUrl,
            ),
          ),
          SectionCard(
            title: 'Sécurité',
            child: Text(
              item.safetyNoticeFr.trim().isEmpty
                  ? 'Ne pas toucher, déplacer, démonter, transporter ou tenter de neutraliser un objet suspect.'
                  : item.safetyNoticeFr,
              style: const TextStyle(
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HazardMainImage extends StatelessWidget {
  final HazardItem item;
  final String treeUri;

  const HazardMainImage({
    super.key,
    required this.item,
    required this.treeUri,
  });

  @override
  Widget build(BuildContext context) {
    final image = item.images.isEmpty ? null : item.images.first;

    if (image == null || image.path.trim().isEmpty) {
      return const ImagePlaceholder();
    }

    return FutureBuilder<Uint8List>(
      future: NativeFolderReader.readBytes(
        treeUri: treeUri,
        path: image.path,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AspectRatio(
            aspectRatio: 1,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const ImagePlaceholder();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }
}

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({super.key});

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

class IdentificationView extends StatelessWidget {
  final HazardItem item;

  const IdentificationView({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final measurements = item.identification['measurements'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoLine(label: 'Nom', value: item.name),
        InfoLine(label: 'Catégorie', value: item.category),
        if (item.countries.isNotEmpty)
          InfoLine(label: 'Pays', value: item.countries.join(', ')),
        if (measurements is Map && measurements.isNotEmpty)
          ...measurements.entries.map((entry) {
            final value = entry.value;

            if (value == null || '$value'.trim().isEmpty) {
              return const SizedBox.shrink();
            }

            return InfoLine(label: '${entry.key}', value: '$value');
          }),
      ],
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

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const SectionCard({
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
              const SizedBox(height: 12),
              child,
            ],
          ),
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
        SectionCard(
          title: 'Consignes de sécurité',
          child: Text(
            'Cette application sert uniquement à la consultation, à l’identification prudente et à la sensibilisation.\n\n'
            'Ne pas toucher, déplacer, démonter, transporter, nettoyer, photographier de près ou tenter de neutraliser une munition ou un objet suspect.\n\n'
            'Éloignez-vous, empêchez les autres personnes de s’approcher et contactez les autorités compétentes.',
            style: TextStyle(height: 1.5),
          ),
        ),
        SectionCard(
          title: 'Limites',
          child: Text(
            'Les informations peuvent être incomplètes, anciennes ou incorrectes. '
            'Elles ne remplacent jamais une formation professionnelle, une procédure officielle ou l’intervention de spécialistes qualifiés.',
            style: TextStyle(height: 1.5),
          ),
        ),
      ],
    );
  }
}

void showGlossaryDialog(BuildContext context, GlossaryTerm term) {
  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        title: Text(term.term),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (term.fullName.trim().isNotEmpty) ...[
                const Text(
                  'Nom complet',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(term.fullName),
                const SizedBox(height: 12),
              ],
              const Text(
                'Catégorie',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                term.category.trim().isEmpty
                    ? 'Non renseigné'
                    : term.category,
              ),
              const SizedBox(height: 12),
              const Text(
                'Définition',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                term.shortDescription.trim().isEmpty
                    ? 'Définition à compléter.'
                    : term.shortDescription,
              ),
              const SizedBox(height: 12),
              Text(
                'Apparaît dans ${term.appearsIn.length} fiche(s).',
                style: const TextStyle(color: Colors.black54),
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
