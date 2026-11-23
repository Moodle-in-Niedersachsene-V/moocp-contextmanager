// Prüft einen installierten Plugin-Ordner auf einem Rechner ohne Dart-Quelltext:
// den Inhalt (Programm, Fenster, plugin.json, Skill), den Start des Plugins wie
// moocp ihn macht (Port, Schlüssel), das Lesen im lokalen Kontextbereich und das
// Öffnen des mitgelieferten Einstellungsfensters. Läuft im Workflow nach dem
// Installieren auf jedem System.
//
//   dart run tool/smoke.dart <Plugin-Ordner>
//
// Der Plugin-Ordner ist der installierte, nicht der Bauordner; das Skript
// schreibt nichts hinein. Einstellungen und der Kontextbereich liegen in einem
// Temp-Ordner, der danach verschwindet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _schluessel = 'smoke-schluessel-0123456789';

Never _fehl(String text) {
  stderr.writeln('SMOKE FEHLGESCHLAGEN: $text');
  exit(1);
}

void _ok(String text) => stdout.writeln('ok: $text');

Future<void> main(List<String> argumente) async {
  if (argumente.length != 1) {
    stderr.writeln('Aufruf: dart run tool/smoke.dart <Plugin-Ordner>');
    exit(2);
  }
  final ordner = Directory(argumente.single).absolute.path;
  final beschreibung = File(p.join(ordner, 'plugin.json'));
  if (!beschreibung.existsSync()) _fehl('plugin.json fehlt in $ordner');
  final json = jsonDecode(beschreibung.readAsStringSync()) as Map<String, dynamic>;
  final programm = json['programm'] as String;
  final skills = (json['skills'] as List).cast<String>();
  final fenster = Platform.isMacOS
      ? p.join(ordner, 'einstellungsfenster.zip')
      : p.join(
          ordner,
          'einstellungsfenster',
          Platform.isWindows ? 'kontext_einstellungen.exe' : 'kontext_einstellungen',
        );

  // 1. Inhalt.
  if (!File(p.join(ordner, programm)).existsSync()) _fehl('Programm $programm fehlt');
  if (!Platform.isWindows &&
      File(p.join(ordner, programm)).statSync().mode & 0x49 == 0) {
    _fehl('Programm $programm ist nicht ausführbar');
  }
  if (!File(fenster).existsSync()) _fehl('Einstellungsfenster fehlt: $fenster');
  if (!Platform.isWindows &&
      !Platform.isMacOS &&
      File(fenster).statSync().mode & 0x49 == 0) {
    _fehl('Einstellungsfenster ist nicht ausführbar');
  }
  for (final links in Directory(ordner).listSync(recursive: true, followLinks: false)) {
    if (links is Link) _fehl('Verknüpfung im Plugin-Ordner: ${links.path}');
  }
  _ok('Inhalt vollständig, keine Verknüpfungen');

  // 2. Skill-Erkennung: moocp findet skills/<name>/SKILL.md mit name im Kopf.
  if (skills.isEmpty) _fehl('plugin.json nennt keine Skills');
  for (final skill in skills) {
    final datei = File(p.join(ordner, 'skills', skill, 'SKILL.md'));
    if (!datei.existsSync()) _fehl('Skill $skill fehlt: ${datei.path}');
    final kopf = datei.readAsStringSync();
    if (!RegExp('^name:\\s*$skill\\s*\$', multiLine: true).hasMatch(kopf)) {
      _fehl('SKILL.md von $skill nennt seinen Namen nicht');
    }
  }
  _ok('Skill(s) $skills erkannt');

  // 3. Start wie durch moocp, mit einem lokalen Kontextbereich.
  final temp = await Directory.systemTemp.createTemp('kontext-smoke');
  Process? plugin;
  try {
    final kontext = Directory(p.join(temp.path, 'kontext'))..createSync();
    File(p.join(kontext.path, 'index.md')).writeAsStringSync('# Smoke\n\nhallo-smoke\n');
    final daten = Directory(p.join(temp.path, 'daten'))..createSync();
    final einstellungen = File(p.join(daten.path, 'einstellungen.json'))
      ..writeAsStringSync(jsonEncode({'art': 'lokal', 'pfad': kontext.path}));
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    plugin = await Process.start(
      p.join(ordner, programm),
      ['--port', '$port', '--einstellungen', einstellungen.path],
      environment: {'MOOCP_PLUGIN_SCHLUESSEL': _schluessel},
    );
    plugin.stdout.drain<void>();
    plugin.stderr.transform(utf8.decoder).listen(stderr.write);

    final mcp = _Mcp(port);
    await mcp.starte();
    final start = await mcp.werkzeug('context_start', {});
    if (!start.contains('hallo-smoke')) _fehl('context_start zeigt den Kontextbereich nicht: $start');
    final lesen = await mcp.werkzeug('context_read', {'pfad': 'index.md'});
    if (!lesen.contains('hallo-smoke') || !lesen.contains('version:')) {
      _fehl('context_read liefert Inhalt und Version nicht: $lesen');
    }
    _ok('Plugin startet, context_start und context_read lesen den Kontextbereich');

    // 4. Einstellungsfenster: öffnet sich und bleibt offen (ein zweiter Aufruf
    // sagt „already open“, solange der Prozess lebt).
    final auf = await mcp.werkzeug('context_settings', {});
    if (!auf.contains('is open')) _fehl('Einstellungsfenster öffnet nicht: $auf');
    await Future<void>.delayed(const Duration(seconds: 6));
    final noch = await mcp.werkzeug('context_settings', {});
    if (!noch.contains('already open')) {
      _fehl('Einstellungsfenster endete nach dem Start: $noch');
    }
    _ok('Einstellungsfenster geöffnet und nach 6 Sekunden noch offen');
  } finally {
    plugin?.kill();
    // Das Fenster endet mit dem Plugin (E8); unter Windows beendet kill() das
    // Plugin hart, dann räumt der nächste Start auf. Die Pid-Datei zeigt den Rest.
    await Future<void>.delayed(const Duration(seconds: 1));
    final pid = File(p.join(temp.path, 'daten', 'fenster.pid'));
    if (pid.existsSync()) {
      final nummer = int.tryParse(pid.readAsStringSync().trim());
      if (nummer != null) Process.killPid(nummer);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // Unter Windows hält ein eben beendetes Fenster die Datei kurz offen.
    }
  }
  stdout.writeln('SMOKE BESTANDEN');
}

/// Ein kleiner MCP-Client über Streamable HTTP, nur so viel, wie der Test braucht.
class _Mcp {
  _Mcp(this.port);

  final int port;
  String? _sitzung;
  int _nummer = 0;

  Future<Map<String, dynamic>> _anfrage(String methode, Map<String, Object?>? params,
      {bool warten = false}) async {
    final koerper = {
      'jsonrpc': '2.0',
      'method': methode,
      if (params != null) 'params': params,
      if (!methode.startsWith('notifications/')) 'id': ++_nummer,
    };
    final ende = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      final client = HttpClient();
      try {
        final a = await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
        a.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
          ..set(HttpHeaders.authorizationHeader, 'Bearer $_schluessel');
        if (_sitzung != null) a.headers.set('mcp-session-id', _sitzung!);
        a.add(utf8.encode(jsonEncode(koerper)));
        final r = await a.close();
        _sitzung = r.headers.value('mcp-session-id') ?? _sitzung;
        final text = await utf8.decoder.bind(r).join();
        if (r.statusCode != 200 && r.statusCode != 202) _fehl('HTTP ${r.statusCode}: $text');
        if (text.isEmpty) return {};
        final antwort = jsonDecode(text) as Map<String, dynamic>;
        if (antwort['error'] != null) _fehl('MCP-Fehler: ${antwort['error']}');
        return (antwort['result'] as Map).cast<String, dynamic>();
      } on SocketException {
        if (!warten || DateTime.now().isAfter(ende)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<void> starte() async {
    await _anfrage('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {
        'experimental': {
          'moocp': {'schnittstelle': 1, 'adresse': 'http://127.0.0.1:1'},
        },
      },
      'clientInfo': {'name': 'smoke', 'version': '1.0.0'},
    }, warten: true);
    await _anfrage('notifications/initialized', null);
  }

  Future<String> werkzeug(String name, Map<String, Object?> argumente) async {
    final r = await _anfrage('tools/call', {
      'name': name,
      'arguments': argumente,
      '_meta': {'moocp/aufruf': 'smoke-aufruf'},
    });
    return ((r['content'] as List?) ?? const []).map((e) => (e as Map)['text']).join('\n');
  }
}
