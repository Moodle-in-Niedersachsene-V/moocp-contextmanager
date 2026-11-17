// Tests am MCP-Seam für einen WebDAV-Server ohne ETag (ADR 0009): Die Version ist
// die Prüfsumme der gelesenen Bytes, das Plugin prüft den Stand selbst und sagt in
// der Schreibantwort, dass der Server die Bedingung nicht erzwungen hat. Ein
// Server mit starkem ETag behält `If-Match` und bekommt keine solche Meldung.
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'harness.dart';
import 'schreiben_test.dart' show fehlerMeldung, versionHallo;

/// Die Version von `hallo\n` ohne ETag: Präfix und sha256 der Bytes.
const versionOhneEtag = 'sha256:$versionHallo';

/// Das Wort, an dem die Antwort die nicht erzwungene Prüfung zeigt.
const hinweis = 'not enforced by the server';

void main() {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('ohne-etag');
    root = pfad.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin({bool etag = false}) async {
    plugin = await PluginProzess.starten(
      ordner: ordner,
      ort: Ortsart.webdav,
      webdavSendetEtag: etag,
    );
    await plugin!.initialisieren();
    plugin!.app.stufe = 'alle';
    return plugin!;
  }

  String datei(String relativ) => pfad.join(root, relativ);

  Future<void> schreibeDatei(String relativ, String inhalt) async {
    final f = File(datei(relativ));
    await f.parent.create(recursive: true);
    await f.writeAsString(inhalt);
  }

  Map<String, Object?> schreiben(
    String pfadArg,
    String inhalt, {
    String art = 'plan_change',
    String? version,
  }) => {
    'pfad': pfadArg,
    'inhalt': inhalt,
    'art': art,
    'zusammenfassung': 'Kurze Zusammenfassung.',
    if (version != null) 'version': version,
  };

  group('Lesen', () {
    test('context_read liefert Text und Version als Prüfsumme', () async {
      await schreibeDatei('index.md', 'hallo\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_read', {'pfad': 'index.md'});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('hallo'));
      expect(text, contains('version: $versionOhneEtag'));
    });

    test('context_start liest den Index', () async {
      await schreibeDatei('index.md', 'Indexinhalt\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(text, contains('Indexinhalt'));
      expect(text, isNot(contains('cannot be read')));
    });
  });

  group('Schreiben', () {
    test('ersetzt mit der gelesenen Version, meldet verified und dass der Server nicht erzwungen hat', () async {
      await schreibeDatei('plan.md', 'hallo\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben('plan.md', 'neu\n', version: versionOhneEtag),
      );
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('verified'));
      expect(text, contains(hinweis));
      expect(text, contains('version: sha256:'));
      expect(await File(datei('plan.md')).readAsString(), 'neu\n');
      // Ohne ETag gibt es nichts, was als If-Match gelten könnte.
      expect(
        p.webdav!.protokoll.where((z) => z.startsWith('PUT')),
        everyElement(isNot(contains('If-Match'))),
      );
    });

    test('Konflikt, wenn die Datei seit dem Lesen geändert wurde; nichts wird geschrieben', () async {
      await schreibeDatei('plan.md', 'anders\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben('plan.md', 'neu\n', version: versionOhneEtag),
      );
      expect(fehlerMeldung(ergebnis), contains('changed since it was read'));
      expect(await File(datei('plan.md')).readAsString(), 'anders\n');
      expect(p.app.freigaben, isEmpty);
    });

    test('Konflikt, wenn die Datei während der Freigabe geändert wird', () async {
      await schreibeDatei('plan.md', 'hallo\n');
      final p = await laufendesPlugin();
      p.app.beiFreigabe = () =>
          File(datei('plan.md')).writeAsStringSync('Sync-Client\n');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben('plan.md', 'neu\n', version: versionOhneEtag),
      );
      expect(fehlerMeldung(ergebnis), contains('changed since it was read'));
      expect(await File(datei('plan.md')).readAsString(), 'Sync-Client\n');
    });

    test('das Fenster zwischen Prüfung und PUT bleibt offen und wird in der Antwort gesagt', () async {
      await schreibeDatei('plan.md', 'hallo\n');
      final p = await laufendesPlugin();
      // Ändert ein anderer Schreiber erst, wenn das PUT beim Server liegt, kann
      // das Plugin es nicht mehr sehen: Der Server hat keine Bedingung erzwungen.
      p.webdav!.vorSchreiben = (_) =>
          File(datei('plan.md')).writeAsStringSync('Fremd\n');
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben('plan.md', 'neu\n', version: versionOhneEtag),
      );
      final text = PluginProzess.text(ergebnis);
      expect(text, contains(hinweis));
      expect(text, contains('overwritten'));
      expect(await File(datei('plan.md')).readAsString(), 'neu\n');
    });

    test('legt eine neue Datei an und lehnt eine vorhandene ohne Version ab', () async {
      await schreibeDatei('da.md', 'hallo\n');
      final p = await laufendesPlugin();
      final neu = await p.werkzeug(
        'context_write',
        schreiben('ordner/neu.md', 'hallo\n', art: 'new_file'),
      );
      expect(neu['isError'], isNot(true));
      expect(PluginProzess.text(neu), startsWith('verified'));
      expect(PluginProzess.text(neu), contains(hinweis));
      expect(await File(datei('ordner/neu.md')).readAsString(), 'hallo\n');

      final vorhanden = await p.werkzeug(
        'context_write',
        schreiben('da.md', 'x\n', art: 'new_file'),
      );
      expect(fehlerMeldung(vorhanden), contains('already exists'));
      expect(await File(datei('da.md')).readAsString(), 'hallo\n');
    });

    test('hängt an und meldet dasselbe', () async {
      await schreibeDatei('journal/tag.md', 'hallo\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_append', {
        'pfad': 'journal/tag.md',
        'inhalt': 'mehr\n',
        'art': 'journal',
        'zusammenfassung': 'Eintrag.',
        'version': versionOhneEtag,
      });
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('verified'));
      expect(text, contains(hinweis));
      expect(await File(datei('journal/tag.md')).readAsString(), 'hallo\nmehr\n');
    });
  });

  group('Archivieren', () {
    test('verschiebt nach archive/, meldet verified und die nicht erzwungene Prüfung', () async {
      await schreibeDatei('klasse/plan.md', 'Plan\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_archive', {
        'ordner': 'klasse',
        'dateien': ['plan.md'],
        'zusammenfassung': 'Altes Layout',
      });
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('verified'));
      expect(text, contains(hinweis));
      expect(File(datei('klasse/plan.md')).existsSync(), isFalse);
      expect(await File(datei('klasse/archive/plan.md')).readAsString(), 'Plan\n');
      expect(
        p.webdav!.protokoll.where((z) => z.startsWith('MOVE')),
        everyElement(isNot(contains('If-Match'))),
      );
    });

    test('Konflikt, wenn sich die Datei während der Freigabe ändert; nichts wandert', () async {
      await schreibeDatei('klasse/plan.md', 'Plan\n');
      final p = await laufendesPlugin();
      p.app.beiFreigabe = () =>
          File(datei('klasse/plan.md')).writeAsStringSync('Fremd\n');
      final ergebnis = await p.werkzeug('context_archive', {
        'ordner': 'klasse',
        'dateien': ['plan.md'],
        'zusammenfassung': 'Altes Layout',
      });
      expect(ergebnis['isError'], true);
      expect(await File(datei('klasse/plan.md')).readAsString(), 'Fremd\n');
      expect(File(datei('klasse/archive/plan.md')).existsSync(), isFalse);
    });
  });

  group('Server mit starkem ETag bleibt unverändert', () {
    test('If-Match im PUT und keine Meldung über eine nicht erzwungene Prüfung', () async {
      await schreibeDatei('plan.md', 'hallo\n');
      final p = await laufendesPlugin(etag: true);
      final lesen = PluginProzess.text(
        await p.werkzeug('context_read', {'pfad': 'plan.md'}),
      );
      expect(lesen, contains('version: $versionHallo'));
      final ergebnis = await p.werkzeug(
        'context_write',
        schreiben('plan.md', 'neu\n', version: versionHallo),
      );
      final text = PluginProzess.text(ergebnis);
      expect(text, startsWith('verified'));
      expect(text, isNot(contains(hinweis)));
      expect(
        p.webdav!.protokoll.where((z) => z.startsWith('PUT')),
        contains(contains('If-Match')),
      );
    });
  });
}
