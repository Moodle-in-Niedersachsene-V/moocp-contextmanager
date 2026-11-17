// Die Einrichtung des Kontextbereichs aus dem Einstellungsfenster (E8): Eingabe
// prüfen, Verbindung prüfen, speichern, und die Meldungen auf Deutsch. Die
// Oberfläche liegt im Ordner `einstellungsfenster/` und benutzt nur diese Datei.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'einstellungen.dart';
import 'fehler.dart';
import 'ort.dart';
import 'schluesselbund.dart';

/// Was das Einstellungsfenster eingetragen hat. [passwort] null oder leer heißt:
/// das bisherige Passwort im Schlüsselbund bleibt (das Fenster zeigt es nie).
class Einrichtung {
  const Einrichtung({
    required this.art,
    this.pfad = '',
    this.adresse = '',
    this.benutzer = '',
    this.passwort,
  });

  /// `lokal` oder `webdav`.
  final String art;
  final String pfad;
  final String adresse;
  final String benutzer;
  final String? passwort;
}

/// Eine Eingabe, die nicht gilt: [feld] nennt das Feld, [meldung] steht deutsch
/// darunter.
class EinrichtungsFehler implements Exception {
  const EinrichtungsFehler(this.feld, this.meldung);

  final String feld;
  final String meldung;

  @override
  String toString() => meldung;
}

/// Prüft die Eingabe und gibt die Einstellungen, die sie beschreibt. Die
/// Reihenfolge der Felder folgt dem Fenster, von oben nach unten.
Einstellungen pruefeEinrichtung(Einrichtung e) {
  if (e.art == 'lokal') {
    final pfad = e.pfad.trim();
    if (pfad.isEmpty) {
      throw const EinrichtungsFehler('pfad', 'Bitte einen Ordner wählen.');
    }
    if (!p.isAbsolute(pfad)) {
      throw const EinrichtungsFehler(
        'pfad',
        'Der Ordner muss mit einem vollständigen Pfad angegeben werden.',
      );
    }
    return Einstellungen.lokal(pfad);
  }
  final adresse = e.adresse.trim();
  if (adresse.isEmpty) {
    throw const EinrichtungsFehler(
      'adresse',
      'Bitte die Adresse des WebDAV-Servers eintragen.',
    );
  }
  final Uri geprueft;
  try {
    geprueft = pruefeAdresse(adresse);
  } on KontextFehler catch (f) {
    throw EinrichtungsFehler('adresse', deutscheMeldung(f));
  }
  final benutzer = e.benutzer.trim();
  if (benutzer.isEmpty) {
    throw const EinrichtungsFehler(
      'benutzer',
      'Bitte den Benutzer eintragen.',
    );
  }
  return Einstellungen.webdav(adresse: geprueft, benutzer: benutzer);
}

/// Die deutsche Meldung zu einer Meldung des Plugins. Der Schlüssel ist der
/// englische Text der Meldung; ein Test prüft jeden Eintrag gegen den echten
/// Fehler, damit eine geänderte Meldung nicht still auf Englisch fällt.
String deutscheMeldung(KontextFehler f) {
  for (final eintrag in _meldungen) {
    if (f.meldung.contains(eintrag.$1)) return eintrag.$2;
  }
  return 'Der Kontextbereich konnte nicht geprüft werden. Die Ursache ist nicht '
      'näher bekannt.';
}

/// Das Ergebnis der Verbindungsprüfung: [meldung] steht deutsch im Fenster.
class Verbindungsergebnis {
  const Verbindungsergebnis({required this.gelungen, required this.meldung});

  final bool gelungen;
  final String meldung;
}

/// Prüft, ob der Ort aus der Eingabe antwortet: öffnen und den Wurzelordner
/// auflisten. Ein eingetragenes Passwort gilt nur für diese Prüfung, ohne dass
/// es vorher im Schlüsselbund steht; sonst liest die Prüfung den Schlüsselbund.
/// Es wird nichts geschrieben.
Future<Verbindungsergebnis> pruefeVerbindung(
  Einrichtung e, {
  required Schluesselbund schluesselbund,
  Duration zeitlimit = const Duration(seconds: 20),
}) async {
  final Einstellungen einstellungen;
  try {
    einstellungen = pruefeEinrichtung(e);
  } on EinrichtungsFehler catch (f) {
    return Verbindungsergebnis(gelungen: false, meldung: f.meldung);
  }
  final eingetragen = e.passwort;
  final Schluesselbund pruefer =
      einstellungen.art == 'webdav' && eingetragen != null && eingetragen.isNotEmpty
      ? _EinmalPasswort(einstellungen.konto, eingetragen)
      : schluesselbund;
  try {
    final speicher = await oeffneOrt(
      einstellungen,
      schluesselbund: pruefer,
      zeitlimit: zeitlimit,
    );
    await speicher.liste('');
    return const Verbindungsergebnis(
      gelungen: true,
      meldung: 'Verbindung in Ordnung: Der Kontextbereich antwortet.',
    );
  } on KontextFehler catch (f) {
    return Verbindungsergebnis(gelungen: false, meldung: deutscheMeldung(f));
  }
}

/// Ein Schlüsselbund mit genau einem Passwort für genau ein Konto, nur für die
/// Prüfung einer Eingabe. Er schreibt nie.
class _EinmalPasswort implements Schluesselbund {
  const _EinmalPasswort(this.konto, this.passwort);

  final String konto;
  final String passwort;

  @override
  Future<String> geheimnis(String konto) async {
    if (konto != this.konto) {
      throw const KontextFehler(
        'No password for the WebDAV location in the system keyring (or the '
        'keyring is locked). Enter it in the settings window; nothing was written.',
      );
    }
    return passwort;
  }

  @override
  Future<void> speichere(String konto, String geheimnis) async {
    throw const KontextFehler('This check does not write; nothing was written.');
  }
}

/// Das Ergebnis des Speicherns: [feld] nennt das Feld bei einer ungültigen Eingabe.
class Speicherergebnis {
  const Speicherergebnis({required this.gespeichert, required this.meldung, this.feld});

  final bool gespeichert;
  final String meldung;
  final String? feld;
}

/// Speichert die Eingabe (E8): erst prüfen, dann das Passwort in den
/// Schlüsselbund, dann die Einstellungsdatei. Scheitert der Schlüsselbund, bleibt
/// die Datei, wie sie war, und die Datei zeigt nie auf ein Passwort, das fehlt.
/// Ein leeres Passwort lässt den Schlüsselbund unberührt.
Future<Speicherergebnis> speichereEinrichtung(
  Einrichtung e, {
  required File datei,
  required Schluesselbund schluesselbund,
}) async {
  final Einstellungen einstellungen;
  try {
    einstellungen = pruefeEinrichtung(e);
  } on EinrichtungsFehler catch (f) {
    return Speicherergebnis(gespeichert: false, feld: f.feld, meldung: f.meldung);
  }
  final eingetragen = e.passwort;
  try {
    if (einstellungen.art == 'webdav' && eingetragen != null && eingetragen.isNotEmpty) {
      await schluesselbund.speichere(einstellungen.konto, eingetragen);
    }
    await schreibeEinstellungen(datei, einstellungen);
  } on KontextFehler catch (f) {
    return Speicherergebnis(gespeichert: false, meldung: deutscheMeldung(f));
  } on FileSystemException {
    return const Speicherergebnis(
      gespeichert: false,
      meldung: 'Die Einstellungen konnten nicht gespeichert werden. Prüfen, ob der Datenordner des Plugins beschreibbar ist.',
    );
  }
  return const Speicherergebnis(
    gespeichert: true,
    meldung: 'Gespeichert. Die nächste Anfrage an den Kontextbereich nutzt die neuen Einstellungen.',
  );
}

const _meldungen = <(String, String)>[
  (
    'could not be stored',
    'Das Passwort konnte nicht im Schlüsselbund gespeichert werden. Nichts wurde geschrieben.',
  ),
  (
    'The context root folder does not exist.',
    'Der Ordner existiert nicht.',
  ),
  (
    'The context root folder cannot be read.',
    'Der Ordner kann nicht gelesen werden.',
  ),
  (
    'refused the user or the password',
    'Der Server lehnt Benutzer oder Passwort ab. Bitte beides prüfen.',
  ),
  (
    'The WebDAV server cannot be reached.',
    'Der Server antwortet nicht. Adresse und Netzverbindung prüfen.',
  ),
  (
    'did not answer in time',
    'Der Server antwortet nicht. Adresse und Netzverbindung prüfen.',
  ),
  (
    'The WebDAV server closed the connection.',
    'Der Server antwortet nicht. Adresse und Netzverbindung prüfen.',
  ),
  (
    'root folder does not exist on the WebDAV server',
    'Der Kontextordner existiert auf dem Server nicht. Adresse prüfen.',
  ),
  (
    'names a file, not a folder',
    'Die Adresse nennt eine Datei, keinen Ordner.',
  ),
  (
    'denies access',
    'Der Server verweigert den Zugriff auf den Kontextordner. Rechte auf dem Server prüfen.',
  ),
  (
    'redirects the request',
    'Der Server leitet die Anfrage um. Die endgültige Adresse eintragen.',
  ),
  (
    'certificate not trusted',
    'Die sichere Verbindung zum Server ist fehlgeschlagen (Zertifikat nicht vertraut).',
  ),
  (
    'No password for the WebDAV location',
    'Im Schlüsselbund ist kein Passwort zu diesem Konto. Bitte eintragen.',
  ),
  (
    'is not installed',
    'Das Werkzeug für den Schlüsselbund fehlt (unter Linux das Paket libsecret-tools).',
  ),
  (
    'system keyring did not answer',
    'Der Schlüsselbund antwortet nicht (vermutlich ist er gesperrt).',
  ),
  (
    'The WebDAV address is not a valid absolute address.',
    'Die Adresse ist keine vollständige Adresse, etwa https://server.example.org/dav/.',
  ),
  (
    'must not contain a user or password',
    'Die Adresse darf keinen Benutzer und kein Passwort enthalten; sie stehen in den Feldern darunter.',
  ),
  (
    'must use https',
    'Die Adresse muss mit https:// beginnen. Nur 127.0.0.1 und localhost dürfen http:// verwenden.',
  ),
];
