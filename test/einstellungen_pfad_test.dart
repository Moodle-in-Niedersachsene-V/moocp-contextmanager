// Der Ort der Einstellungsdatei unter Windows (%APPDATA%, wie moocp).
import 'package:test/test.dart';

import 'package:contextmanager/src/einstellungen.dart';

void main() {
  test('unter Windows liegt die Einstellungsdatei in %APPDATA%', () {
    expect(
      standardEinstellungenPfad(
        umgebung: {'APPDATA': r'C:\Users\x\AppData\Roaming'},
        windows: true,
      ),
      r'C:\Users\x\AppData\Roaming\moocp-contextmanager\einstellungen.json',
    );
  });

  test('ohne %APPDATA% gilt der Roaming-Ordner im Benutzerprofil', () {
    expect(
      standardEinstellungenPfad(umgebung: {'USERPROFILE': r'C:\Users\x'}, windows: true),
      r'C:\Users\x\AppData\Roaming\moocp-contextmanager\einstellungen.json',
    );
  });
}
