import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class OfflineDatabase {
  final Map<String, dynamic> databaseInfo;
  final Map<String, dynamic> stats;
  final List<HazardItem> items;
  final List<GlossaryTerm> glossary;

  OfflineDatabase({
    required this.databaseInfo,
    required this.stats,
    required this.items,
    required this.glossary,
  });

  factory OfflineDatabase.fromJson(Map<String, dynamic> json) {
    return OfflineDatabase(
      databaseInfo: Map<String, dynamic>.from(json['databaseInfo'] ?? {}),
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
  final List<dynamic> publicNotes;
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
    required this.publicNotes,
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
      descriptionText: '${json['descriptionText'] ?? ''}',
      identification:
          Map<String, dynamic>.from(json['identification'] ?? <String, dynamic>{}),
      variants: ((json['variants'] ?? []) as List).map((e) => '$e').toList(),
      technologyKeywords:
          ((json['technologyKeywords'] ?? []) as List).map((e) => '$e').toList(),
      publicNotes: List<dynamic>.from(json['publicNotes'] ?? []),
      sourceUrl: '${json['sourceUrl'] ?? ''}',
      safetyNoticeFr: '${json['safetyNoticeFr'] ?? ''}',
    );
  }
}

class HazardImage {
  final String path;
  final String caption;
  final bool isPrimary;
  final String sourceUrl;
  final bool placeholder;

  HazardImage({
    required this.path,
    required this.caption,
    required this.isPrimary,
    required this.sourceUrl,
    required this.placeholder,
  });

  factory HazardImage.fromJson(Map<String, dynamic> json) {
    return HazardImage(
      path: '${json['path'] ?? ''}',
      caption: '${json['caption'] ?? ''}',
      isPrimary: json['isPrimary'] == true,
      sourceUrl: '${json['sourceUrl'] ?? ''}',
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
  final List<String> sourceUrls;

  GlossaryTerm({
    required this.term,
    required this.fullName,
    required this.category,
    required this.shortDescription,
    required this.appearsIn,
    required this.sourceUrls,
  });

  factory GlossaryTerm.fromJson(Map<String, dynamic> json) {
    return GlossaryTerm(
      term: '${json['term'] ?? ''}',
      fullName: '${json['fullName'] ?? ''}',
      category: '${json['category'] ?? ''}',
      shortDescription: '${json['shortDescription'] ?? ''}',
      appearsIn: ((json['appearsIn'] ?? []) as List).map((e) => '$e').toList(),
      sourceUrls: ((json['sourceUrls'] ?? []) as List).map((e) => '$e').toList(),
    );
  }
}

class DatabaseStorage {
  static const String databaseFileName = 'catuxo_database.json';

  static Future<Directory> appDataDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${dir.path}/catuxo_offline_pack');
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return dbDir;
  }

  static Future<File> databaseFile() async {
    final dir = await appDataDir();
    return File('${dir.path}/$databaseFileName');
  }

  static Future<OfflineDatabase?> loadInstalledDatabase() async {
    final file = await databaseFile();

    if (!await file.exists()) {
      return null;
    }

    final text = await file.readAsString();
    final jsonMap = jsonDecode(text) as Map<String, dynamic>;
    return OfflineDatabase.fromJson(jsonMap);
  }

  static const MethodChannel _filePickerChannel =
      MethodChannel('uxo_offline_fr/file_picker');

  static Future<OfflineDatabase> importZip() async {
    final dynamic result = await _filePickerChannel.invokeMethod('pickZip');

    if (result == null) {
      throw Exception('Aucun fichier ZIP sélectionné.');
    }

    final Uint8List bytes;

    if (result is Uint8List) {
      bytes = result;
    } else if (result is List) {
      bytes = Uint8List.fromList(result.cast<int>());
    } else {
      throw Exception('Format de fichier reçu invalide.');
    }

    final appDir = await appDataDir();

    if (await appDir.exists()) {
      await appDir.delete(recursive: true);
    }

    await appDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive.files) {
      final outputPath = '${appDir.path}/${file.name}';

      if (file.isFile) {
        final outputFile = File(outputPath);
        await outputFile.parent.create(recursive: true);
        await outputFile.writeAsBytes(file.content as List<int>);
      } else {
        final outputDir = Directory(outputPath);
        await outputDir.create(recursive: true);
      }
    }

    final dbFile = await databaseFile();

    if (!await dbFile.exists()) {
      throw Exception('catuxo_database.json absent du ZIP.');
    }

    final dbText = await dbFile.readAsString();
    final jsonMap = jsonDecode(dbText) as Map<String, dynamic>;
    return OfflineDatabase.fromJson(jsonMap);
  }

  static Future<File?> resolveImage(HazardImage image) async {
    if (image.path.trim().isEmpty) {
      return null;
    }

    final dir = await appDataDir();
    final file = File('${dir.path}/${image.path}');

    if (await file.exists()) {
      return file;
    }

    return null;
  }
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
  OfflineDatabase? database;
  bool loading = true;
  String query = '';
  HomeTab tab = HomeTab.fiches;

  @override
  void initState() {
    super.initState();
    loadDatabase();
  }

  Future<void> loadDatabase() async {
    setState(() {
      loading = true;
    });

    try {
      final db = await DatabaseStorage.loadInstalledDatabase();
      setState(() {
        database = db;
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> importDatabase() async {
    setState(() {
      loading = true;
    });

    try {
      final db = await DatabaseStorage.importZip();

      setState(() {
        database = db;
        tab = HomeTab.fiches;
        query = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Base importée : ${db.items.length} fiches.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur import : $e'),
          ),
        );
      }
    } finally {
      setState(() {
        loading = false;
      });
    }
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

    final sorted = Map.fromEntries(
      map.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );

    return sorted;
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
            onPressed: loading ? null : importDatabase,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Importer une base',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : db == null
              ? EmptyDatabaseView(onImport: importDatabase)
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
                        HomeTab.categories => buildCategoriesView(db),
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
                glossaryMap: glossaryMap,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildCategoriesView(OfflineDatabase db) {
    final map = itemsByCategory;
    final entries = map.entries.toList();

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

class EmptyDatabaseView extends StatelessWidget {
  final VoidCallback onImport;

  const EmptyDatabaseView({
    super.key,
    required this.onImport,
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
              const Icon(Icons.folder_off, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Aucune base hors ligne installée',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Sélectionne le fichier catuxo_offline_pack.zip pour installer la base hors ligne.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choisir le fichier ZIP'),
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
          StatChip(label: 'Fiches', value: '${stats['items'] ?? database.items.length}'),
          StatChip(label: 'Lexique', value: '${stats['glossaryTerms'] ?? database.glossary.length}'),
          StatChip(label: 'Images', value: '${stats['downloadedImages'] ?? '-'}'),
          StatChip(label: 'Placeholder', value: '${stats['placeholderImages'] ?? '-'}'),
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
  final Map<String, GlossaryTerm> glossaryMap;

  const HazardListCard({
    super.key,
    required this.item,
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
  final Map<String, GlossaryTerm> glossaryMap;

  const CategoryScreen({
    super.key,
    required this.categoryName,
    required this.items,
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
            glossaryMap: glossaryMap,
          );
        },
      ),
    );
  }
}

class HazardDetailScreen extends StatelessWidget {
  final HazardItem item;
  final Map<String, GlossaryTerm> glossaryMap;

  const HazardDetailScreen({
    super.key,
    required this.item,
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
          HazardMainImage(item: item),
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
                children: item.variants.map((v) => Chip(label: Text(v))).toList(),
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
              item.sourceUrl.trim().isEmpty ? 'Source non disponible.' : item.sourceUrl,
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

  const HazardMainImage({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final image = item.images.isEmpty ? null : item.images.first;

    if (image == null) {
      return const ImagePlaceholder();
    }

    return FutureBuilder<File?>(
      future: DatabaseStorage.resolveImage(image),
      builder: (context, snapshot) {
        final file = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AspectRatio(
            aspectRatio: 1,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (file == null || image.placeholder) {
          return const ImagePlaceholder();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const ImagePlaceholder(),
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
              Text(term.category.trim().isEmpty ? 'Non renseigné' : term.category),
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

