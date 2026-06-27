import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const PitStopApp());
}

// ---- Shared config & theme ----

// Chrome/web reaches the backend at localhost.
// (For the Android emulator, change this to http://10.0.2.2:8000)
const String kBaseUrl = 'http://localhost:8000';

const Color kPitRed = Color(0xFFE10600);
const Color kBg = Color(0xFF0A0A0A);
const Color kCard = Color(0xFF141414);

// ---- Image service: local assets first, then OpenF1, then placeholder ----

class ImageService {
  static final ImageService instance = ImageService._();
  ImageService._();

  final Map<String, String> _codeToHeadshot = {}; // "VER" -> openf1 url
  bool _loaded = false;
  Future<void>? _loading;

  // Driver codes we have local assets for (lowercase).
  static const Set<String> _localDrivers = {
    'ant', 'bea', 'bor', 'bot', 'col', 'gas', 'ham', 'hul',
    'law', 'lec', 'nor', 'oco', 'pia', 'rus', 'sai', 'ver',
  };

  // Team refs we have local assets for.
  static const Set<String> _localTeams = {
    'alpine', 'aston_martin', 'audi', 'cadillac', 'ferrari',
    'haas', 'mclaren', 'mercedes', 'rb', 'red_bull', 'williams',
  };

  // Aliases: map a backend constructor_ref to our local file name.
  // (None needed currently — every ref has its own file.)
  static const Map<String, String> _teamAlias = {};

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.openf1.org/v1/drivers'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        for (final d in data) {
          final code = (d['name_acronym'] ?? '').toString().toUpperCase();
          final url = (d['headshot_url'] ?? '').toString();
          if (code.isNotEmpty && url.isNotEmpty) {
            _codeToHeadshot[code] = url;
          }
        }
      }
    } catch (_) {
      // OpenF1 unavailable; local assets still work.
    } finally {
      _loaded = true;
    }
  }

  // Returns a local asset path if we have one, else null.
  String? localDriverAsset(String? code) {
    if (code == null) return null;
    final c = code.toLowerCase();
    return _localDrivers.contains(c) ? 'assets/drivers/$c.png' : null;
  }

  String? localTeamAsset(String? ref) {
    if (ref == null) return null;
    var r = ref.toLowerCase();
    if (_teamAlias.containsKey(r)) r = _teamAlias[r]!;
    return _localTeams.contains(r) ? 'assets/teams/$r.png' : null;
  }

  // OpenF1 fallback for drivers without a local asset.
  String? headshotForCode(String? code) {
    if (code == null || code.isEmpty) return null;
    return _codeToHeadshot[code.toUpperCase()];
  }
}

// Shows a local asset, then a network url, then a fallback widget.
class SmartImage extends StatelessWidget {
  final String? assetPath;
  final String? networkUrl;
  final double width;
  final double height;
  final Widget fallback;
  final BoxFit fit;
  const SmartImage({
    super.key,
    required this.assetPath,
    required this.networkUrl,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (assetPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          assetPath!,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _networkOrFallback(),
        ),
      );
    }
    return _networkOrFallback();
  }

  Widget _networkOrFallback() {
    if (networkUrl == null || networkUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        networkUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: kPitRed),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PitStopApp extends StatelessWidget {
  const PitStopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIT STOP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        fontFamily: 'Orbitron',
        colorScheme: const ColorScheme.dark(primary: kPitRed),
      ),
      home: const RootScaffold(),
    );
  }
}

// ---- Root scaffold with bottom navigation ----

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;

  final List<Widget> _pages = const [
    HomePanel(),
    RacesPanel(),
    StandingsPanel(),
    SearchPanel(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: kCard,
        selectedItemColor: kPitRed,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'HOME'),
          BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'RACES'),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'STANDINGS'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'SEARCH'),
        ],
      ),
    );
  }
}

// ---- Shared header widget ----

class PitHeader extends StatelessWidget {
  final String subtitle;
  final String? source;
  const PitHeader({super.key, required this.subtitle, this.source});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PIT STOP',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                subtitle,
                style: const TextStyle(
                  color: kPitRed,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              if (source != null && source!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '($source)',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HOME PANEL  (placeholder for now)
// ============================================================

class HomePanel extends StatefulWidget {
  const HomePanel({super.key});

  @override
  State<HomePanel> createState() => _HomePanelState();
}

class _HomePanelState extends State<HomePanel> {
  final String _season = '2026';

  Map<String, dynamic>? _nextRace;
  DateTime? _raceDate;
  List<dynamic> _constructors = [];
  List<dynamic> _drivers = [];

  bool _loading = true;
  String? _error;

  Duration _remaining = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch races, constructors, drivers in parallel.
      final results = await Future.wait([
        http.get(Uri.parse('$kBaseUrl/races/$_season')),
        http.get(Uri.parse('$kBaseUrl/standings/constructors/$_season')),
        http.get(Uri.parse('$kBaseUrl/standings/drivers/$_season')),
      ]).timeout(const Duration(seconds: 30));

      final racesData = jsonDecode(results[0].body);
      final consData = jsonDecode(results[1].body);
      final drvData = jsonDecode(results[2].body);

      final races = (racesData['races'] ?? []) as List<dynamic>;
      _nextRace = _findNextRace(races);
      if (_nextRace != null && _nextRace!['date'] != null) {
        _raceDate = _parseRaceDate(_nextRace!);
        _startCountdown();
      }

      setState(() {
        _constructors = (consData['standings'] ?? []) as List<dynamic>;
        _drivers = (drvData['standings'] ?? []) as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not connect: $e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _findNextRace(List<dynamic> races) {
    final now = DateTime.now();
    Map<String, dynamic>? upcoming;
    for (final r in races) {
      final d = _parseRaceDate(r);
      if (d != null && d.isAfter(now)) {
        if (upcoming == null || d.isBefore(_parseRaceDate(upcoming)!)) {
          upcoming = Map<String, dynamic>.from(r);
        }
      }
    }
    // If no upcoming race, fall back to the last race of the season.
    if (upcoming == null && races.isNotEmpty) {
      upcoming = Map<String, dynamic>.from(races.last);
    }
    return upcoming;
  }

  DateTime? _parseRaceDate(dynamic race) {
    final dateStr = race['date'];
    if (dateStr == null) return null;
    final timeStr = race['time']; // may be null or "HH:MM:SSZ"
    try {
      if (timeStr != null && timeStr.toString().isNotEmpty) {
        return DateTime.parse('${dateStr}T$timeStr').toLocal();
      }
      return DateTime.parse(dateStr.toString());
    } catch (_) {
      return null;
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_raceDate == null) return;
    final diff = _raceDate!.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPitRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }

    return RefreshIndicator(
      color: kPitRed,
      onRefresh: _loadAll,
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('PIT STOP',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2)),
          ),
          _sectionLabel('F1 2026 OPENING TITLES'),
          _videoCard(),
          _sectionLabel('NEXT RACE'),
          _nextRaceCard(),
          _sectionLabel('CONSTRUCTOR STANDINGS'),
          ..._miniList(_constructors, isDriver: false),
          _sectionLabel('DRIVERS STANDINGS'),
          ..._miniList(_drivers, isDriver: true),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Container(width: 4, height: 16, color: kPitRed),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: kPitRed,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _videoCard() {
    return GestureDetector(
      onTap: () async {
        final url =
            Uri.parse('https://www.youtube.com/watch?v=7U_fFy9vOyY');
        try {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 160,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            // opening image (falls back to gradient if missing)
            Image.asset(
              'assets/misc/opening.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPitRed.withOpacity(0.25), Colors.black],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            // dark overlay for contrast
            Container(color: Colors.black.withOpacity(0.25)),
            // play button
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                  color: kPitRed, shape: BoxShape.circle),
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 32),
            ),
            const Positioned(
              bottom: 12,
              right: 12,
              child: Text('▷ TAP TO PLAY',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextRaceCard() {
    if (_nextRace == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No upcoming race found',
            style: TextStyle(color: Colors.grey)),
      );
    }
    final r = _nextRace!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kPitRed),
            ),
            child: Text('ROUND ${r['round'] ?? '-'}',
                style: const TextStyle(
                    color: kPitRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(height: 10),
          Text('${r['race_name'] ?? ''}'.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${r['circuit_name'] ?? ''}',
              style: const TextStyle(color: Colors.grey)),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                const Icon(Icons.place, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text('${r['country'] ?? ''}',
                    style: const TextStyle(color: Colors.grey)),
              ]),
              Row(children: [
                const Icon(Icons.calendar_today, color: Colors.grey, size: 14),
                const SizedBox(width: 4),
                Text('${r['date'] ?? ''}',
                    style: const TextStyle(color: Colors.grey)),
              ]),
            ],
          ),
          if (_raceDate != null) ...[
            const SizedBox(height: 16),
            _countdownRow(),
          ],
        ],
      ),
    );
  }

  Widget _countdownRow() {
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final mins = _remaining.inMinutes % 60;
    final secs = _remaining.inSeconds % 60;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _countBox(days.toString().padLeft(2, '0'), 'DAY'),
        _glowColon(),
        _countBox(hours.toString().padLeft(2, '0'), 'HRS'),
        _glowColon(),
        _countBox(mins.toString().padLeft(2, '0'), 'MIN'),
        _glowColon(),
        _countBox(secs.toString().padLeft(2, '0'), 'SEC'),
      ],
    );
  }

  Widget _glowColon() {
    return const Text(':',
        style: TextStyle(
            color: kPitRed,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: kPitRed, blurRadius: 12),
              Shadow(color: kPitRed, blurRadius: 4),
            ]));
  }

  Widget _countBox(String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  List<Widget> _miniList(List<dynamic> rows, {required bool isDriver}) {
    final top = rows.take(5).toList();
    if (top.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('No data', style: TextStyle(color: Colors.grey)),
        )
      ];
    }
    return [
      for (int i = 0; i < top.length; i++)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: i == 0 ? kPitRed : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
              // vertical red accent line
              Container(
                width: 3,
                height: 34,
                color: kPitRed,
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDriver
                          ? '${top[i]['given_name'] ?? ''} ${top[i]['family_name'] ?? ''}'
                          : '${top[i]['name'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text('${top[i]['nationality'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                            fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${top[i]['points'] ?? 0} PTS',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text('${top[i]['wins'] ?? 0} WINS',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
    ];
  }
}

// ============================================================
// RACES PANEL  (placeholder for now)
// ============================================================

class RacesPanel extends StatefulWidget {
  const RacesPanel({super.key});

  @override
  State<RacesPanel> createState() => _RacesPanelState();
}

class _RacesPanelState extends State<RacesPanel> {
  String _season = '2026';
  List<dynamic> _races = [];
  bool _loading = true;
  String? _error;
  String _source = '';

  // Track which race rows are expanded, and their fetched podiums.
  final Set<int> _expanded = {};
  final Map<int, List<dynamic>> _podiums = {}; // round -> [first,second,third]
  final Set<int> _podiumLoading = {};

  final List<String> _years = [
    for (int y = DateTime.now().year; y >= 1950; y--) '$y'
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _expanded.clear();
      _podiums.clear();
    });
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/races/$_season'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _races = data['races'] ?? [];
          _source = data['source'] ?? '';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server returned ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleDetails(int round) async {
    if (_expanded.contains(round)) {
      setState(() => _expanded.remove(round));
      return;
    }
    setState(() => _expanded.add(round));

    // Fetch podium for this season if not already loaded.
    if (!_podiums.containsKey(round) && !_podiumLoading.contains(round)) {
      setState(() => _podiumLoading.add(round));
      try {
        final res = await http
            .get(Uri.parse('$kBaseUrl/races/$_season/winners'))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final winners = (data['winners'] ?? []) as List<dynamic>;
          // map every round's podium so other expansions are instant
          for (final w in winners) {
            final r = w['round'];
            final podium = w['podium'];
            if (r != null && podium != null) {
              _podiums[r] = [
                podium['first'],
                podium['second'],
                podium['third'],
              ];
            }
          }
        }
      } catch (_) {
        // leave podium missing; UI shows "unavailable"
      } finally {
        setState(() => _podiumLoading.remove(round));
      }
    }
  }

  bool _isPast(dynamic dateStr) {
    if (dateStr == null) return false;
    try {
      return DateTime.parse(dateStr.toString()).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _watchRace(dynamic race) async {
    final name = '${race['race_name'] ?? ''}'.trim();
    final query = 'F1 $_season $name highlights';
    final url = Uri.parse(
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // if launching fails, do nothing (button just won't open)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + year dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PIT STOP',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Text('RACE SCHEDULE',
                        style: TextStyle(
                            color: kPitRed,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 1)),
                    if (_source.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('($_source)',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ]),
                ],
              ),
              _yearDropdown(),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _yearDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPitRed.withOpacity(0.6)),
      ),
      child: DropdownButton<String>(
        value: _season,
        dropdownColor: kCard,
        underline: const SizedBox(),
        iconEnabledColor: kPitRed,
        style: const TextStyle(color: Colors.white, fontFamily: 'Orbitron'),
        items: _years
            .map((y) => DropdownMenuItem(value: y, child: Text(y)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _season = v);
          _fetch();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPitRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (_races.isEmpty) {
      return const Center(
          child: Text('No races found', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      color: kPitRed,
      onRefresh: _fetch,
      child: ListView.builder(
        itemCount: _races.length,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemBuilder: (context, index) => _raceCard(_races[index]),
      ),
    );
  }

  Widget _raceCard(dynamic r) {
    final round = r['round'] ?? 0;
    final past = _isPast(r['date']);
    final isExpanded = _expanded.contains(round);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Round badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kPitRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kPitRed),
                ),
                child: Text('R$round',
                    style: const TextStyle(
                        color: kPitRed,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['race_name'] ?? ''}'.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.place, color: Colors.grey, size: 14),
                      const SizedBox(width: 4),
                      Text('${r['country'] ?? ''}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 13)),
                    ]),
                  ],
                ),
              ),
              Row(children: [
                const Icon(Icons.calendar_today,
                    color: Colors.grey, size: 12),
                const SizedBox(width: 4),
                Text('${r['date'] ?? ''}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: past ? kPitRed : const Color(0xFF24C24C)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(past ? Icons.check_circle : Icons.circle,
                    size: 10,
                    color: past ? kPitRed : const Color(0xFF24C24C)),
                const SizedBox(width: 6),
                Text(past ? 'COMPLETED' : 'UPCOMING',
                    style: TextStyle(
                        color: past ? kPitRed : const Color(0xFF24C24C),
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // WATCH RACE button (centered, glowing, not full-width)
          Center(
            child: GestureDetector(
              onTap: () => _watchRace(r),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 12),
                decoration: BoxDecoration(
                  color: kPitRed,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: kPitRed.withOpacity(0.7),
                        blurRadius: 18,
                        spreadRadius: 1),
                    BoxShadow(
                        color: kPitRed.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 4),
                  ],
                ),
                child: const Text('WATCH RACE',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 1)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // DETAILS expander
          GestureDetector(
            onTap: () => _toggleDetails(round),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('DETAILS',
                      style: TextStyle(
                          color: Colors.grey[400],
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          fontSize: 12)),
                  Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[400],
                      size: 18),
                ],
              ),
            ),
          ),
          if (isExpanded) _podiumSection(round),
        ],
      ),
    );
  }

  Widget _podiumSection(int round) {
    if (_podiumLoading.contains(round)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: kPitRed))),
      );
    }
    final podium = _podiums[round];
    if (podium == null || podium.every((p) => p == null)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Podium data unavailable',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    const medals = ['🥇', '🥈', '🥉'];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (int i = 0; i < podium.length; i++)
            if (podium[i] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(medals[i], style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${podium[i]['driver'] ?? ''}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                    Text('${podium[i]['team'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ============================================================
// STANDINGS PANEL  (working - driver standings from backend)
// ============================================================

class StandingsPanel extends StatefulWidget {
  const StandingsPanel({super.key});

  @override
  State<StandingsPanel> createState() => _StandingsPanelState();
}

class _StandingsPanelState extends State<StandingsPanel> {
  bool _showDrivers = true; // true = DRIVERS, false = CONSTRUCTORS
  String _season = '2026';

  List<dynamic> _rows = [];
  bool _loading = true;
  String? _error;
  String _source = '';

  // Years for the dropdown (newest first). 1950 is F1's first season.
  final List<String> _years = [
    for (int y = DateTime.now().year; y >= 1950; y--) '$y'
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await ImageService.instance.ensureLoaded();
    final kind = _showDrivers ? 'drivers' : 'constructors';
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/standings/$kind/$_season'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _rows = data['standings'] ?? [];
          _source = data['source'] ?? '';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server returned ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect: $e';
        _loading = false;
      });
    }
  }

  void _switchTab(bool drivers) {
    if (_showDrivers == drivers) return;
    setState(() => _showDrivers = drivers);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: title + year dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PIT STOP',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('STANDINGS',
                          style: TextStyle(
                              color: kPitRed,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 1)),
                      if (_source.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('($_source)',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
              _yearDropdown(),
            ],
          ),
        ),
        // DRIVERS / CONSTRUCTORS toggle
        _toggle(),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _yearDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPitRed.withOpacity(0.6)),
      ),
      child: DropdownButton<String>(
        value: _season,
        dropdownColor: kCard,
        underline: const SizedBox(),
        iconEnabledColor: kPitRed,
        style: const TextStyle(color: Colors.white, fontFamily: 'Orbitron'),
        items: _years
            .map((y) => DropdownMenuItem(value: y, child: Text(y)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _season = v);
          _fetch();
        },
      ),
    );
  }

  Widget _toggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _toggleButton('DRIVERS', _showDrivers, () => _switchTab(true)),
            _toggleButton('CONSTRUCTORS', !_showDrivers, () => _switchTab(false)),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? kPitRed.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: kPitRed) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? kPitRed : Colors.grey,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPitRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
          child: Text('No standings found',
              style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      color: kPitRed,
      onRefresh: _fetch,
      child: ListView.builder(
        itemCount: _rows.length,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemBuilder: (context, index) =>
            _showDrivers ? _driverRow(_rows[index]) : _constructorRow(_rows[index]),
      ),
    );
  }

  Widget _driverRow(dynamic d) {
    final code = (d['code'] ?? '').toString();
    return _rowShell(
      position: d['position'],
      avatar: SmartImage(
        assetPath: ImageService.instance.localDriverAsset(code),
        networkUrl: ImageService.instance.headshotForCode(code),
        width: 44,
        height: 44,
        fallback: _circleAvatar(code.isNotEmpty ? code : '?'),
      ),
      title: '${d['given_name'] ?? ''} ${d['family_name'] ?? ''}',
      subtitleRich: Row(
        children: [
          Text(code,
              style: const TextStyle(
                  color: kPitRed,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                  fontSize: 12)),
          const SizedBox(width: 6),
          Text('${d['nationality'] ?? ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
      points: d['points'],
      wins: d['wins'],
    );
  }

  Widget _constructorRow(dynamic c) {
    final name = (c['name'] ?? '').toString();
    final initial = name.isNotEmpty ? name[0] : '?';
    final ref = (c['constructor_ref'] ?? '').toString();
    return _rowShell(
      position: c['position'],
      avatar: SmartImage(
        assetPath: ImageService.instance.localTeamAsset(ref),
        networkUrl: null,
        width: 44,
        height: 44,
        fit: BoxFit.contain,
        fallback: _circleAvatar(initial),
      ),
      title: name,
      subtitleRich: Text('${c['nationality'] ?? ''}',
          style: const TextStyle(
              color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12)),
      points: c['points'],
      wins: c['wins'],
    );
  }

  Widget _circleAvatar(String text) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _rowShell({
    required dynamic position,
    required Widget avatar,
    required String title,
    required Widget subtitleRich,
    required dynamic points,
    required dynamic wins,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: kPitRed, width: 4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${position ?? '-'}',
                style: TextStyle(
                    color: position == 1 ? kPitRed : Colors.grey,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                subtitleRich,
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${points ?? 0} PTS',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text('${wins ?? 0} WINS',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SEARCH PANEL  (placeholder for now)
// ============================================================

class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key});

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _drivers = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$kBaseUrl/search/drivers')
          .replace(queryParameters: {'q': q});
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _drivers = data['drivers'] ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server returned ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect: $e';
        _loading = false;
      });
    }
  }

  void _openDriver(String driverRef, String displayName) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DriverDetailScreen(
        driverRef: driverRef,
        displayName: displayName,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('PIT STOP',
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2)),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'SEARCH DRIVER...',
                hintStyle: TextStyle(color: Colors.grey, letterSpacing: 1),
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPitRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (_drivers.isEmpty) {
      return const Center(
          child: Text('No drivers found',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _drivers.length,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemBuilder: (context, index) {
        final d = _drivers[index];
        final name =
            '${d['given_name'] ?? ''} ${d['family_name'] ?? ''}'.trim();
        return GestureDetector(
          onTap: () => _openDriver('${d['driver_ref']}', name),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(10),
              border: const Border(
                  left: BorderSide(color: kPitRed, width: 4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${d['nationality'] ?? ''}',
                          style: const TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                              fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Driver career detail screen ----

class DriverDetailScreen extends StatefulWidget {
  final String driverRef;
  final String displayName;
  const DriverDetailScreen(
      {super.key, required this.driverRef, required this.displayName});

  @override
  State<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends State<DriverDetailScreen> {
  Map<String, dynamic>? _career;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    await ImageService.instance.ensureLoaded();
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/drivers/${widget.driverRef}/career'))
          .timeout(const Duration(seconds: 90));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _career = data['career'];
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server returned ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPitRed))
            : _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)))
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final c = _career ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        _careerCard(c),
        const SizedBox(height: 16),
        // Stat tiles grid
        Row(children: [
          _statTile('RACES', '${c['races'] ?? 0}'),
          const SizedBox(width: 12),
          _statTile('WINS', '${c['wins'] ?? 0}'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statTile('PODIUMS', '${c['podiums'] ?? 0}'),
          const SizedBox(width: 12),
          _statTile('POLES', '${c['poles'] ?? 0}'),
        ]),
        const SizedBox(height: 16),
        _totalPoints(c),
        const SizedBox(height: 16),
        _pointsPerSeason(c),
        const SizedBox(height: 16),
        _performance(c),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _careerCard(Map<String, dynamic> c) {
    final name =
        '${c['given_name'] ?? ''} ${c['family_name'] ?? ''}'.trim().isEmpty
            ? widget.displayName
            : '${c['given_name'] ?? ''} ${c['family_name'] ?? ''}'.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [const Color(0xFF2A0A0A), kCard],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(color: kPitRed.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // avatar (local asset, then OpenF1, then placeholder)
          SmartImage(
            assetPath:
                ImageService.instance.localDriverAsset('${c['code'] ?? ''}'),
            networkUrl:
                ImageService.instance.headshotForCode('${c['code'] ?? ''}'),
            width: 90,
            height: 110,
            fallback: Container(
              width: 90,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person, color: Colors.grey, size: 50),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kPitRed),
                  ),
                  child: const Text('CAREER STATS',
                      style: TextStyle(
                          color: kPitRed,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ),
                const SizedBox(height: 10),
                Text(name.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white24, height: 20),
                Row(children: [
                  const Icon(Icons.flag, color: kPitRed, size: 14),
                  const SizedBox(width: 6),
                  Text('${c['nationality'] ?? ''}'.toUpperCase(),
                      style: const TextStyle(color: Colors.grey)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.cake, color: kPitRed, size: 14),
                  const SizedBox(width: 6),
                  Text('${c['dob'] ?? ''}',
                      style: const TextStyle(color: Colors.grey)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _totalPoints(Map<String, dynamic> c) {
    final pts = c['total_points'];
    final ptsStr = pts == null
        ? '0'
        : (pts is num ? pts.toStringAsFixed(0) : '$pts');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [const Color(0xFF2A0A0A), kCard],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('TOTAL POINTS',
              style: TextStyle(
                  color: kPitRed,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          Text(ptsStr,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _pointsPerSeason(Map<String, dynamic> c) {
    final raw = (c['points_per_season'] ?? []) as List<dynamic>;
    if (raw.isEmpty) {
      return const SizedBox();
    }
    // find max for scaling
    double maxPts = 0;
    for (final s in raw) {
      final p = (s['points'] ?? 0);
      final v = p is num ? p.toDouble() : 0.0;
      if (v > maxPts) maxPts = v;
    }
    if (maxPts == 0) maxPts = 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 4, height: 14, color: kPitRed),
            const SizedBox(width: 8),
            const Text('POINTS PER SEASON',
                style: TextStyle(
                    color: kPitRed,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final s in raw)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // points value above the bar
                          Text(
                            '${((s['points'] ?? 0) is num ? (s['points'] as num).toDouble() : 0.0).toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          // the bar
                          Container(
                            height: (90 *
                                    (((s['points'] ?? 0) is num
                                            ? (s['points'] as num).toDouble()
                                            : 0.0) /
                                        maxPts))
                                .clamp(2.0, 90.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFF6B6B), kPitRed],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // full year below
                          Text(
                            '${s['season'] ?? ''}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _performance(Map<String, dynamic> c) {
    final winRate = (c['win_rate'] ?? 0);
    final podiumRate = (c['podium_rate'] ?? 0);
    final wr = winRate is num ? winRate.toDouble() : 0.0;
    final pr = podiumRate is num ? podiumRate.toDouble() : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 4, height: 14, color: kPitRed),
            const SizedBox(width: 8),
            const Text('PERFORMANCE',
                style: TextStyle(
                    color: kPitRed,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ]),
          const SizedBox(height: 16),
          _rateBar('WIN RATE', wr),
          const SizedBox(height: 14),
          _rateBar('PODIUM RATE', pr),
        ],
      ),
    );
  }

  Widget _rateBar(String label, double percent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text('${percent.toStringAsFixed(1)}%',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final fillWidth =
                constraints.maxWidth * (percent / 100).clamp(0.0, 1.0);
            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: fillWidth < 4 ? 4 : fillWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFFFF6B6B), kPitRed],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}