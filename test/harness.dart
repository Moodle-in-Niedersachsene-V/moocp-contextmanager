// Testgerüst am MCP-Seam: startet das Plugin so, wie moocp es startet (Port
// auf der Kommandozeile, Schlüssel in der Umgebung), gibt ihm eine falsche
// Adresse der App (ein Server, der nur mitzählt) und spricht JSON-RPC über
// Streamable HTTP. Jeder Test bekommt einen eigenen Ordner unter dem
// temporären Verzeichnis (TMPDIR, auf der Platte, nicht in /tmp).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Der Schlüssel, den das Testgerüst dem Plugin mitgibt.
const testSchluessel = 'testschluessel-0123456789';

/// Eine laufende Instanz des Plugins samt Hilfsmitteln.
class PluginProzess {
  PluginProzess._(
    this.prozess,
    this.port,
    this.ordner,
    this.einstellungen,
    this.appServer,
    this.appAnfragen,
  );

  final Process prozess;
  final int port;
  final Directory ordner;
  final File einstellungen;
  final HttpServer appServer;

  /// Anfragen, die beim falschen App-Server ankamen (sollen in den Tests leer bleiben).
  final List<String> appAnfragen;

  String? _sitzung;
  int _nummer = 0;

  /// Startet das Plugin. [einstellungenInhalt] schreibt die Einstellungsdatei
  /// (null: es gibt keine). [mitEntwicklung] setzt `--entwicklung`.
  static Future<PluginProzess> starten({
    required Directory ordner,
    String? einstellungenInhalt,
    String? schluessel = testSchluessel,
    bool mitPort = true,
    bool mitEntwicklung = false,
  }) async {
    final port = await _freierPort();
    final appAnfragen = <String>[];
    final appServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    appServer.listen((anfrage) async {
      appAnfragen.add('${anfrage.method} ${anfrage.uri.path}');
      anfrage.response
        ..statusCode = HttpStatus.notFound
        ..write('{"fehler":"Testserver"}');
      await anfrage.response.close();
    });

    final einstellungen = File(p.join(ordner.path, 'einstellungen.json'));
    if (einstellungenInhalt != null) {
      await einstellungen.writeAsString(einstellungenInhalt);
    }

    final args = [
      'bin/context.dart',
      if (mitPort) ...['--port', '$port'],
      '--einstellungen',
      einstellungen.path,
      if (mitEntwicklung) '--entwicklung',
    ];
    final prozess = await Process.start(
      Platform.resolvedExecutable,
      args,
      environment: {
        if (schluessel != null) 'MOOCP_PLUGIN_SCHLUESSEL': schluessel,
      },
      includeParentEnvironment: true,
    );
    // Die Ausgabe des Plugins mitlesen, damit der Puffer nicht volläuft.
    prozess.stdout.drain<void>();
    prozess.stderr.drain<void>();

    return PluginProzess._(
      prozess,
      port,
      ordner,
      einstellungen,
      appServer,
      appAnfragen,
    );
  }

  Uri get adresse => Uri.parse('http://127.0.0.1:$port/mcp');

  /// Meldet die Sitzung an (initialize mit der Adresse der App). Wartet,
  /// bis das Plugin antwortet.
  Future<Map<String, dynamic>> initialisieren({String? schluessel = testSchluessel}) async {
    final antwort = await anfragen(
      'initialize',
      {
        'protocolVersion': '2025-06-18',
        'capabilities': {
          'experimental': {
            'moocp': {
              'schnittstelle': 1,
              'adresse': 'http://127.0.0.1:${appServer.port}',
            },
          },
        },
        'clientInfo': {'name': 'testgeruest', 'version': '1.0.0'},
      },
      schluessel: schluessel,
      warten: true,
    );
    await anfragen('notifications/initialized', null, schluessel: schluessel);
    return antwort;
  }

  /// Ruft ein Werkzeug auf und liefert das Ergebnis (`content`, `isError`).
  Future<Map<String, dynamic>> werkzeug(String name, Map<String, Object?> argumente) async {
    return anfragen('tools/call', {'name': name, 'arguments': argumente});
  }

  /// Schickt eine JSON-RPC-Anfrage. Ohne [id] ist es eine Benachrichtigung.
  Future<Map<String, dynamic>> anfragen(
    String methode,
    Map<String, Object?>? params, {
    String? schluessel = testSchluessel,
    bool warten = false,
  }) async {
    final nummer = ++_nummer;
    final koerper = <String, Object?>{
      'jsonrpc': '2.0',
      'method': methode,
      if (params != null) 'params': params,
      if (!methode.startsWith('notifications/')) 'id': nummer,
    };
    final client = HttpClient();
    try {
      HttpClientResponse? antwort;
      // Beim ersten Aufruf kann das Plugin noch starten: kurz wiederholen.
      final ende = DateTime.now().add(const Duration(seconds: 20));
      while (true) {
        try {
          final anfrage = await client.postUrl(adresse);
          anfrage.headers
            ..contentType = ContentType.json
            ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
          if (schluessel != null) {
            anfrage.headers.set(HttpHeaders.authorizationHeader, 'Bearer $schluessel');
          }
          if (_sitzung != null) anfrage.headers.set('mcp-session-id', _sitzung!);
          anfrage.add(utf8.encode(jsonEncode(koerper)));
          antwort = await anfrage.close();
          break;
        } on SocketException {
          if (!warten || DateTime.now().isAfter(ende)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      final sitzung = antwort.headers.value('mcp-session-id');
      if (sitzung != null) _sitzung = sitzung;
      final text = await utf8.decoder.bind(antwort).join();
      if (antwort.statusCode != HttpStatus.ok) {
        return {'_status': antwort.statusCode, '_text': text};
      }
      if (text.isEmpty) return {'_status': antwort.statusCode};
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json.containsKey('error')) return {'_fehler': json['error']};
      return (json['result'] as Map?)?.cast<String, dynamic>() ?? {};
    } finally {
      client.close(force: true);
    }
  }

  /// Der Text aller Inhalte eines Werkzeugergebnisses zusammen.
  static String text(Map<String, dynamic> ergebnis) {
    final inhalt = (ergebnis['content'] as List?) ?? const [];
    return inhalt.map((e) => (e as Map)['text']).join('\n');
  }

  /// Beendet das Plugin und den Testserver der App.
  Future<void> beenden() async {
    prozess.kill();
    await prozess.exitCode;
    await appServer.close(force: true);
  }

  static Future<int> _freierPort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }
}

/// Ein Ordner für einen Test, im temporären Verzeichnis.
Future<Directory> tempOrdner(String name) async {
  return Directory.systemTemp.createTemp('contextmanager-$name-');
}
