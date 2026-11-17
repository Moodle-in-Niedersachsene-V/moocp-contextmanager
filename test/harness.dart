// Testgerüst am MCP-Seam: startet das Plugin so, wie moocp es startet (Port
// auf der Kommandozeile, Schlüssel in der Umgebung), gibt ihm eine falsche
// Adresse der App (ein Server, der nur mitzählt) und spricht JSON-RPC über
// Streamable HTTP. Jeder Test bekommt einen eigenen Ordner unter dem
// temporären Verzeichnis (TMPDIR, auf der Platte, nicht in /tmp).
//
// Jede Test-Datei läuft zweimal, einmal je Ort (lokal, WebDAV; siehe
// [fuerJedenOrt]). Der WebDAV-Ort ist ein Server im Testprozess, der den Ordner
// des Tests bedient; das Passwort kommt von einem Ersatz für `secret-tool`, der
// nur das Konto der Testanlage kennt. Der echte Schlüsselbund wird nie benutzt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'webdav_server.dart';

/// Der Schlüssel, den das Testgerüst dem Plugin mitgibt.
const testSchluessel = 'testschluessel-0123456789';

/// Benutzer und Passwort des WebDAV-Ortes der Testanlage (nur für Tests).
const testBenutzer = 'testnutzer';
const testPasswort = 'testgeheimnis-0123456789';

/// Die Orte, an denen jede Test-Datei läuft.
enum Ortsart { lokal, webdav }

/// Führt die Tests je Ort aus: einmal mit einem lokalen Ordner, einmal mit
/// einem WebDAV-Server im Test. Die Tests selbst unterscheiden den Ort nur,
/// wo der Ort eine Rolle spielt (etwa beim Ausfall).
void fuerJedenOrt(void Function(Ortsart art) tests) {
  for (final art in Ortsart.values) {
    group('Ort ${art.name}', () => tests(art));
  }
}

/// Das Token eines Aufrufs, den das Testgerüst an die Werkzeuge schickt.
const testAufruf = 'aufruf-testtoken';

/// Die Rangfolge der Freigabestufen (E20): Eine Anfrage mit `ab` wird
/// gestellt, wenn die Stufe der Lehrkraft mindestens so hoch ist.
const _rang = {'keine': 0, 'mittel': 1, 'alle': 2};

/// Die falsche Adresse der App, wie moocp sie für Plugins bereitstellt. Sie
/// zählt jede Anfrage und beantwortet Freigaben nach der Stufe der Lehrkraft,
/// damit die Tests sehen, was das Plugin gefragt hat.
class FakeApp {
  /// Die Stufe der Lehrkraft: „keine“, „mittel“ oder „alle“.
  String stufe = 'mittel';

  /// Was die Lehrkraft antwortet, wenn sie gefragt wird.
  String antwort = 'freigegeben';

  /// Alle Anfragen als „METHODE pfad“; ohne Freigaben bleibt die Liste leer.
  final List<String> anfragen = [];

  /// Die Freigabeanfragen (Inhalt) je Aufruf, mit dem Token des Aufrufs.
  final List<Map<String, dynamic>> freigaben = [];

  /// Die Antworten, die das Plugin erhalten hat (für Freigaben: `ohneFrage`).
  final List<Map<String, dynamic>> freigabeAntworten = [];

  /// Der Ordner, den die Lehrkraft im Ordnerdialog wählt; null: sie bricht ab.
  String? dialogPfad;

  /// Die Ordnerdialoge, die das Plugin geöffnet hat (Titel und Art).
  final List<Map<String, dynamic>> dialoge = [];

  /// Läuft beim Antworten auf eine Freigabe, bevor sie beantwortet wird. Ein Test
  /// ändert hier die Datei, um zu prüfen, dass nach der Freigabe noch der gelesene
  /// Stand gilt (Lehrkraft oder Sync-Client während der Wartezeit).
  void Function()? beiFreigabe;
}

/// Eine laufende Instanz des Plugins samt Hilfsmitteln.
class PluginProzess {
  PluginProzess._(
    this.prozess,
    this.port,
    this.ordner,
    this.einstellungen,
    this.appServer,
    this.app,
    this.ort,
    this.webdav,
  );

  final Process prozess;
  final int port;
  final Directory ordner;
  final File einstellungen;
  final HttpServer appServer;

  /// Der Ort, für den die Einstellungen eingerichtet wurden (null: keiner).
  final Ortsart? ort;

  /// Der WebDAV-Server des Tests, nur am Ort webdav.
  final WebDavTestServer? webdav;

  /// Der Ordner des Kontextbereichs auf der Platte (am Ort webdav bedient ihn der Server).
  String get root => p.join(ordner.path, 'kontext');

  /// Die falsche App: Anfragen und Freigaben, siehe [FakeApp].
  final FakeApp app;

  /// Anfragen, die beim falschen App-Server ankamen (sollen in den Tests leer bleiben).
  List<String> get appAnfragen => app.anfragen;

  /// Die Aufrufe des Einstellungsfensters (je Zeile ein Aufruf mit Argumenten).
  List<String> get fensterAufrufe {
    final datei = File(p.join(ordner.path, 'fenster-aufrufe.txt'));
    return datei.existsSync() ? datei.readAsLinesSync() : <String>[];
  }

  String? _sitzung;
  int _nummer = 0;

  /// Startet das Plugin. [ort] richtet die Einstellungen für diesen Ort ein
  /// (und startet am Ort webdav den Server samt Schlüsselbund-Ersatz);
  /// [einstellungenInhalt] schreibt die Datei verbatim und hat Vorrang. Ohne
  /// beides gibt es keine Einstellungsdatei. [webdavPasswort] null: der
  /// Schlüsselbund hat keinen Eintrag. [mitEntwicklung] setzt `--entwicklung`.
  static Future<PluginProzess> starten({
    required Directory ordner,
    Ortsart? ort,
    String? einstellungenInhalt,
    String? webdavPasswort = testPasswort,
    String? schluessel = testSchluessel,
    bool mitPort = true,
    bool mitEntwicklung = false,
    String? fenster,
  }) async {
    final port = await _freierPort();
    final app = FakeApp();
    final appServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    appServer.listen((anfrage) async {
      final koerper = await utf8.decoder.bind(anfrage).join();
      app.anfragen.add('${anfrage.method} ${anfrage.uri.path}');
      if (anfrage.method == 'POST' && anfrage.uri.path == '/v1/freigabe') {
        final aufruf = anfrage.headers.value('Moocp-Aufruf');
        if (aufruf == null || aufruf.isEmpty) {
          await _antworte(anfrage, HttpStatus.forbidden, {
            'fehler': 'Kein Aufruf-Token.',
          });
          return;
        }
        final daten = (jsonDecode(koerper) as Map).cast<String, dynamic>();
        app.freigaben.add(daten);
        app.beiFreigabe?.call();
        final gefragt = _rang[app.stufe]! >= _rang[daten['ab']]!;
        final ergebnis = {
          'ausgang': gefragt ? app.antwort : 'freigegeben',
          'ohneFrage': !gefragt,
        };
        app.freigabeAntworten.add(ergebnis);
        await _antworte(anfrage, HttpStatus.ok, ergebnis);
        return;
      }
      if (anfrage.method == 'POST' && anfrage.uri.path == '/v1/dialog/pfad') {
        final daten = (jsonDecode(koerper) as Map).cast<String, dynamic>();
        app.dialoge.add(daten);
        final gewaehlt = app.dialogPfad;
        await _antworte(
          anfrage,
          HttpStatus.ok,
          gewaehlt == null ? {'abgebrochen': true} : {'pfad': gewaehlt},
        );
        return;
      }
      await _antworte(anfrage, HttpStatus.notFound, {'fehler': 'Testserver'});
    });

    final root = p.join(ordner.path, 'kontext');
    WebDavTestServer? webdav;
    var pfadMitSchluesselbund = Platform.environment['PATH'] ?? '';
    if (ort == Ortsart.webdav) {
      webdav = WebDavTestServer(
        ordner: Directory(root),
        benutzer: testBenutzer,
        passwort: testPasswort,
      );
      await webdav.starten();
      // Ein Ersatz für secret-tool: Er kennt nur das Konto dieser Testanlage und
      // gibt sonst nichts aus. Das Plugin ruft ihn über den Suchpfad auf.
      final werkzeuge = Directory(p.join(ordner.path, 'schluesselbund'))
        ..createSync();
      final konto = '$testBenutzer@${webdav.adresse}';
      final skript = File(p.join(werkzeuge.path, 'secret-tool'));
      await skript.writeAsString(
        '#!/bin/sh\n'
        '# Test-Ersatz für secret-tool: nur das Konto der Testanlage hat ein Passwort.\n'
        'case "\$*" in\n'
        '  *"account $konto"*)\n'
        '${webdavPasswort == null ? '    exit 1\n' : "    printf '%s' '$webdavPasswort'\n    exit 0\n"}'
        '    ;;\n'
        'esac\n'
        'exit 1\n',
      );
      Process.runSync('chmod', ['755', skript.path]);
      pfadMitSchluesselbund = '${werkzeuge.path}:$pfadMitSchluesselbund';
    }

    final einstellungen = File(p.join(ordner.path, 'einstellungen.json'));
    final inhalt =
        einstellungenInhalt ??
        switch (ort) {
          null => null,
          Ortsart.lokal => jsonEncode({'art': 'lokal', 'pfad': root}),
          Ortsart.webdav => jsonEncode({
            'art': 'webdav',
            'adresse': webdav!.adresse.toString(),
            'benutzer': testBenutzer,
          }),
        };
    if (inhalt != null) {
      await einstellungen.writeAsString(inhalt);
    }

    // Das Einstellungsfenster ist im Test ein Skript, das nur aufzeichnet, was
    // es bekommt (Pfad der Einstellungen). So öffnet kein Test ein echtes Fenster.
    final aufrufe = File(p.join(ordner.path, 'fenster-aufrufe.txt'));
    final fensterSkript = File(p.join(ordner.path, 'fenster-skript'));
    await fensterSkript.writeAsString(
      '#!/bin/sh\necho "\$@" >> ${aufrufe.path}\n',
    );
    Process.runSync('chmod', ['755', fensterSkript.path]);

    final args = [
      'bin/context.dart',
      if (mitPort) ...['--port', '$port'],
      '--einstellungen',
      einstellungen.path,
      '--fenster',
      fenster ?? fensterSkript.path,
      if (mitEntwicklung) '--entwicklung',
    ];
    final prozess = await Process.start(
      Platform.resolvedExecutable,
      args,
      environment: {
        if (schluessel != null) 'MOOCP_PLUGIN_SCHLUESSEL': schluessel,
        'PATH': pfadMitSchluesselbund,
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
      app,
      ort,
      webdav,
    );
  }

  /// Der Ort antwortet nicht: lokal fehlt der Wurzelordner, bei WebDAV ist der
  /// Server aus. Nach [wiederherstellen] ist er wieder da, unter derselben Adresse.
  Future<void> ausfallen() async {
    if (webdav != null) {
      await webdav!.anhalten();
    } else {
      await Directory(root).delete(recursive: true);
    }
  }

  Future<void> wiederherstellen() async {
    if (webdav != null) {
      await webdav!.starten();
    } else {
      await Directory(root).create();
    }
  }

  Uri get adresse => Uri.parse('http://127.0.0.1:$port/mcp');

  static Future<void> _antworte(
    HttpRequest anfrage,
    int status,
    Map<String, Object?> daten,
  ) async {
    anfrage.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(daten));
    await anfrage.response.close();
  }

  /// Meldet die Sitzung an (initialize mit der Adresse der App). Wartet,
  /// bis das Plugin antwortet.
  Future<Map<String, dynamic>> initialisieren({
    String? schluessel = testSchluessel,
    String? adresse,
  }) async {
    final antwort = await anfragen(
      'initialize',
      {
        'protocolVersion': '2025-06-18',
        'capabilities': {
          'experimental': {
            'moocp': {
              'schnittstelle': 1,
              'adresse': adresse ?? 'http://127.0.0.1:${appServer.port}',
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
  /// Mit [aufruf] als Token des Aufrufs (moocp setzt es in `_meta`).
  Future<Map<String, dynamic>> werkzeug(
    String name,
    Map<String, Object?> argumente, {
    String? aufruf = testAufruf,
  }) async {
    return anfragen('tools/call', {
      'name': name,
      'arguments': argumente,
      if (aufruf != null) '_meta': {'moocp/aufruf': aufruf},
    });
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
            ..set(
              HttpHeaders.acceptHeader,
              'application/json, text/event-stream',
            );
          if (schluessel != null) {
            anfrage.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $schluessel',
            );
          }
          if (_sitzung != null)
            anfrage.headers.set('mcp-session-id', _sitzung!);
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
    await webdav?.beenden();
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
