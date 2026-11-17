// Tests am MCP-Seam für Konfliktkopien von Sync-Clients: context_list
// meldet die Konfliktkopien eines Ordners, context_start die im ganzen Kontextbereich.
// Jede Meldung nennt beide Dateinamen. Das Plugin löscht und ändert nichts.
// Die Namen sind erfunden; die Muster stehen in docs/adr/0007-konfliktkopien-melden.md.
import 'dart:io';

import 'package:path/path.dart' as pfad;
import 'package:test/test.dart';

import 'package:contextmanager/src/konflikt.dart';
import 'package:contextmanager/src/speicher.dart';

import 'harness.dart';

void main() => fuerJedenOrt(_tests);

void _tests(Ortsart art) {
  late Directory ordner;
  late String root;
  PluginProzess? plugin;

  setUp(() async {
    ordner = await tempOrdner('konflikt');
    root = pfad.join(ordner.path, 'kontext');
    await Directory(root).create();
  });

  tearDown(() async {
    await plugin?.beenden();
    plugin = null;
    await ordner.delete(recursive: true);
  });

  Future<PluginProzess> laufendesPlugin() async {
    plugin = await PluginProzess.starten(ordner: ordner, ort: art);
    await plugin!.initialisieren();
    return plugin!;
  }

  Future<void> schreibe(String relativ, String inhalt) async {
    final datei = File(pfad.join(root, relativ));
    await datei.parent.create(recursive: true);
    await datei.writeAsString(inhalt);
  }

  group('context_list meldet Konfliktkopien des Ordners', () {
    test('Dropbox- und Nextcloud-Kopie nennen beide Dateinamen', () async {
      await schreibe('klassen/plan.md', 'Original\n');
      await schreibe('klassen/plan (Conflicted copy 2026-11-17).md', 'Kopie\n');
      final p = await laufendesPlugin();
      final ergebnis = await p.werkzeug('context_list', {'pfad': 'klassen'});
      expect(ergebnis['isError'], isNot(true));
      final text = PluginProzess.text(ergebnis);
      expect(text, contains('conflict copies:'));
      expect(text, contains("'plan (Conflicted copy 2026-11-17).md'"));
      expect(text, contains("'plan.md'"));
      expect(text, contains('both files exist'));
    });

    test('Syncthing-Kopie wird dem Original mit Endung zugeordnet', () async {
      await schreibe('notizen.md', 'Original\n');
      await schreibe(
        'notizen.sync-conflict-20261117-143000-ABC1234.md',
        'Kopie\n',
      );
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_list', {'pfad': ''}),
      );
      expect(
        text,
        contains(
          "'notizen.sync-conflict-20261117-143000-ABC1234.md' is a conflict copy of 'notizen.md'",
        ),
      );
    });

    test('ist das Original nicht da, steht das dabei', () async {
      await schreibe('wochen_conflict-20261117-143000.md', 'Kopie\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_list', {'pfad': ''}),
      );
      expect(text, contains("'wochen.md'"));
      expect(text, contains('not there'));
    });

    test('Seafile-Kopie wird erkannt', () async {
      await schreibe('stand.md', 'Original\n');
      await schreibe(
        'stand (SFConflict nutzer 2026-11-17-14-30-00).md',
        'Kopie\n',
      );
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_list', {'pfad': ''}),
      );
      expect(text, contains("'stand.md'"));
      expect(text, contains('SFConflict'));
    });

    test('Syncthing-Kopie ohne Gerätekennung wird erkannt', () async {
      await schreibe('notizen.md', 'Original\n');
      await schreibe('notizen.sync-conflict-20261117-143000.md', 'Kopie\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_list', {'pfad': ''}),
      );
      expect(
        text,
        contains(
          "'notizen.sync-conflict-20261117-143000.md' is a conflict copy of 'notizen.md'",
        ),
      );
    });

    test('Nextcloud-Kopie mit Benutzer im Namen wird erkannt', () async {
      await schreibe('wochen.md', 'Original\n');
      await schreibe('wochen_conflict-nutzer-20261117-143000.md', 'Kopie\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_list', {'pfad': ''}),
      );
      expect(
        text,
        contains(
          "'wochen_conflict-nutzer-20261117-143000.md' is a conflict copy of 'wochen.md'",
        ),
      );
    });

    test(
      '„conflicted copy“ mit Benutzer und Zeit (neuere Form) wird erkannt',
      () async {
        await schreibe('plan.md', 'Original\n');
        await schreibe(
          'plan (conflicted copy nutzer 2026-11-17 143000).md',
          'Kopie\n',
        );
        final p = await laufendesPlugin();
        final text = PluginProzess.text(
          await p.werkzeug('context_list', {'pfad': ''}),
        );
        expect(text, contains("'plan.md'"));
        expect(text, contains('conflicted copy nutzer 2026-11-17 143000'));
      },
    );

    test('gewöhnliche Namen ohne Muster werden nicht gemeldet', () async {
      await schreibe('plan (1).md', 'x\n');
      await schreibe('conflict.md', 'x\n');
      await schreibe('sync-conflict-notizen.md', 'x\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(
        await p.werkzeug('context_list', {'pfad': ''}),
      );
      expect(text, isNot(contains('conflict copies')));
      expect(text, contains('plan (1).md'));
    });
  });

  if (art == Ortsart.lokal) {
    // Die Zeitgrenze lässt sich am MCP-Seam nicht verkürzen; sie wird am Modul
    // geprüft, mit einer Grenze von null Sekunden.
    test(
      'läuft die Zeitgrenze ab, ist die Suche als unvollständig gekennzeichnet',
      () async {
        await schreibe('plan.md', 'Original\n');
        await schreibe('plan (Conflicted copy).md', 'Kopie\n');
        final speicher = await LokalerSpeicher.oeffnen(root);
        final suche = await sucheKonfliktkopien(
          speicher,
          zeitlimit: Duration.zero,
        );
        expect(suche.zeitlimitErreicht, isTrue);
        expect(suche.funde, isEmpty);
      },
    );
  }

  group('context_start meldet Konfliktkopien im ganzen Kontextbereich', () {
    test(
      'eine Kopie in einem Unterordner wird gefunden und beide Namen genannt',
      () async {
        await schreibe('index.md', 'Index\n');
        await schreibe('klassen/7b/mathe/plan.md', 'Original\n');
        await schreibe(
          'klassen/7b/mathe/plan (conflicted copy 2026-11-17).md',
          'Kopie\n',
        );
        final p = await laufendesPlugin();
        final ergebnis = await p.werkzeug('context_start', {});
        expect(ergebnis['isError'], isNot(true));
        final text = PluginProzess.text(ergebnis);
        expect(text, contains('conflict copies: 1 found'));
        expect(
          text,
          contains(
            "'klassen/7b/mathe/plan (conflicted copy 2026-11-17).md' is a conflict copy of 'klassen/7b/mathe/plan.md'",
          ),
        );
      },
    );

    test('ohne Konfliktkopien steht „none“ da', () async {
      await schreibe('index.md', 'Index\n');
      final p = await laufendesPlugin();
      final text = PluginProzess.text(await p.werkzeug('context_start', {}));
      expect(text, contains('conflict copies: none.'));
    });

    test('Kopien werden nur gemeldet: Dateien bleiben unverändert', () async {
      await schreibe('plan.md', 'Original\n');
      await schreibe('plan (Conflicted copy).md', 'Kopie\n');
      final p = await laufendesPlugin();
      await p.werkzeug('context_start', {});
      expect(File(pfad.join(root, 'plan.md')).readAsStringSync(), 'Original\n');
      expect(
        File(pfad.join(root, 'plan (Conflicted copy).md')).readAsStringSync(),
        'Kopie\n',
      );
    });

    test('ohne Kontextbereich steht „not checked“ in der Antwort', () async {
      await schreibe('index.md', 'Index\n');
      final p = await laufendesPlugin();
      await p.ausfallen();
      final ergebnis = await p.werkzeug('context_start', {});
      expect(ergebnis['isError'], isNot(true));
      expect(
        PluginProzess.text(ergebnis),
        contains('conflict copies: not checked'),
      );
    });
  });
}
