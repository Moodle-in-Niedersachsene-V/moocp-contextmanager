import 'dart:io';

import 'package:path/path.dart' as p;

import 'einstellungsfenster.dart' show FensterVorbereitungsFehler;

/// Das Einstellungsfenster auf dem Mac (E11): ein Flutter-Bündel
/// (`kontext_einstellungen.app`), das in seinen Frameworks Verknüpfungen hat.
/// moocp lehnt einen Plugin-Ordner mit Verknüpfungen ab (Prüfsumme der
/// Zustimmung), deshalb legt `bauen.sh` das Bündel als Archiv
/// `einstellungsfenster.zip` in den Plugin-Ordner. Das Archiv zählt zur
/// Prüfsumme; das Plugin packt es vor jedem Öffnen frisch in seinen Datenordner
/// aus und startet das Fenster von dort. So läuft nie ein Fenster, das nicht
/// aus dem zugestimmten Stand kommt.
const fensterArchivName = 'einstellungsfenster.zip';

/// Das Programm des Fensters in einem ausgepackten Ordner [ziel].
String fensterProgrammIn(Directory ziel) => p.join(
  ziel.path,
  'kontext_einstellungen.app',
  'Contents',
  'MacOS',
  'kontext_einstellungen',
);

/// Packt [archiv] nach [ziel] aus. Ein früherer Stand in [ziel] wird vorher
/// ganz entfernt, auch wenn das Archiv fehlt: Dann bleibt kein Fenster stehen,
/// das das Plugin starten könnte. Steht an der Stelle von [ziel] eine
/// Verknüpfung, wird sie entfernt, nie gefolgt.
///
/// Ausgepackt wird mit `ditto` (macOS), das Verknüpfungen und Rechte im Bündel
/// erhält. Wirft [FensterarchivFehler] mit dem Grund.
Future<void> packeFensterAus({
  required File archiv,
  required Directory ziel,
}) async {
  try {
    if (FileSystemEntity.isLinkSync(ziel.path)) {
      await Link(ziel.path).delete();
    } else if (ziel.existsSync()) {
      await ziel.delete(recursive: true);
    }
  } on FileSystemException catch (e) {
    throw FensterarchivFehler(
      'the previous settings window could not be removed (${e.message})',
    );
  }
  if (!archiv.existsSync()) {
    throw const FensterarchivFehler(
      'the plugin folder has no $fensterArchivName',
    );
  }
  await ziel.parent.create(recursive: true);
  final ProcessResult r;
  try {
    r = await Process.run('ditto', ['-x', '-k', archiv.path, ziel.path]);
  } on ProcessException {
    throw const FensterarchivFehler(
      'the system tool ditto could not be started',
    );
  }
  if (r.exitCode != 0) {
    throw FensterarchivFehler('ditto failed (${(r.stderr as String).trim()})');
  }
  if (!File(fensterProgrammIn(ziel)).existsSync()) {
    throw const FensterarchivFehler(
      'the archive does not contain the settings window',
    );
  }
}

/// Das Archiv des Fensters ließ sich nicht auspacken.
class FensterarchivFehler extends FensterVorbereitungsFehler {
  const FensterarchivFehler(super.grund);
}
