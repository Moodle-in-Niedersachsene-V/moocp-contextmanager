import 'fehler.dart';
import 'speicher.dart';

/// Die Obergrenzen der Suche im ganzen Kontextbereich. Ein Ordner, der tiefer
/// liegt oder nach diesen Ordnern drankommt, wird nicht geprüft; die Antwort sagt es.
const konfliktHoechstTiefe = 10;
const konfliktHoechstOrdner = 500;

/// Die Muster der Namen, die Sync-Clients für Konfliktkopien vergeben (Spec #74,
/// ADR 0007). Jedes Muster hat als erste Gruppe den Stamm und als zweite die
/// Endung des Originals.
final _muster = <RegExp>[
  // Syncthing: name.sync-conflict-JJJJMMTT-HHMMSS-GERÄT.endung
  RegExp(r'^(.+)\.sync-conflict-\d{8}-\d{6}-[A-Za-z0-9]+(\.[^.]+)?$'),
  // Nextcloud-Desktop (neuere Versionen): name_conflict-JJJJMMTT-HHMMSS.endung
  RegExp(r'^(.+)_conflict-\d{8}-\d{6}(\.[^.]+)?$'),
  // Dropbox und ältere Nextcloud-Versionen: name (conflicted copy …).endung
  RegExp(
    r'^(.+) \([^()]*conflicted copy[^()]*\)(\.[^.]+)?$',
    caseSensitive: false,
  ),
  // Seafile: name (SFConflict Benutzer Zeit).endung
  RegExp(r'^(.+) \(SFConflict [^()]*\)(\.[^.]+)?$'),
];

/// Der Name des Originals, wenn [name] eine Konfliktkopie ist; sonst null.
String? originalName(String name) {
  for (final muster in _muster) {
    final treffer = muster.firstMatch(name);
    if (treffer != null) return treffer.group(1)! + (treffer.group(2) ?? '');
  }
  return null;
}

/// Eine Konfliktkopie in einem Ordner des Kontextbereichs. [ordner] ist relativ
/// zur Wurzel (leer für die Wurzel); [name] und [originalNamen] sind Namen im Ordner.
class Konfliktkopie {
  const Konfliktkopie({
    required this.ordner,
    required this.name,
    required this.originalName,
    required this.originalDa,
  });

  final String ordner;
  final String name;
  final String originalName;

  /// Ob das Original im selben Ordner liegt.
  final bool originalDa;

  /// Der Pfad der Kopie relativ zur Wurzel.
  String get pfad => verbinde(ordner, name);

  /// Der Pfad des Originals relativ zur Wurzel.
  String get originalPfad => verbinde(ordner, originalName);

  static String verbinde(String ordner, String name) =>
      ordner.isEmpty ? name : '$ordner/$name';
}

/// Die Konfliktkopien unter den Einträgen eines Ordners (ohne Unterordner).
List<Konfliktkopie> konfliktkopienIn(String ordner, List<Eintrag> eintraege) {
  final namen = {for (final e in eintraege) e.name};
  return [
    for (final e in eintraege)
      if (originalName(e.name) case final original?)
        Konfliktkopie(
          ordner: ordner,
          name: e.name,
          originalName: original,
          originalDa: namen.contains(original),
        ),
  ];
}

/// Das Ergebnis der Suche im ganzen Kontextbereich. [unpruefbar] nennt Ordner,
/// die nicht gelesen werden konnten; [begrenzt] sagt, dass die Obergrenzen
/// gegriffen haben.
class KonfliktSuche {
  const KonfliktSuche({
    required this.funde,
    required this.unpruefbar,
    required this.begrenzt,
  });

  final List<Konfliktkopie> funde;
  final List<String> unpruefbar;
  final bool begrenzt;
}

/// Sucht Konfliktkopien im ganzen Kontextbereich, breit zuerst. Ein Ordner, der
/// sich nicht lesen lässt, wird genannt und übergangen. Antwortet der Ort nicht,
/// wirft es [KontextNichtErreichbar].
Future<KonfliktSuche> sucheKonfliktkopien(Kontextspeicher speicher) async {
  final funde = <Konfliktkopie>[];
  final unpruefbar = <String>[];
  var begrenzt = false;
  var geprueft = 0;
  final warteschlange = <(String, int)>[('', 0)];
  while (warteschlange.isNotEmpty) {
    if (geprueft >= konfliktHoechstOrdner) {
      begrenzt = true;
      break;
    }
    final (ordner, tiefe) = warteschlange.removeAt(0);
    geprueft++;
    final List<Eintrag> eintraege;
    try {
      eintraege = await speicher.liste(ordner);
    } on KontextNichtErreichbar {
      rethrow;
    } on KontextFehler catch (f) {
      unpruefbar.add(f.meldung);
      continue;
    }
    funde.addAll(konfliktkopienIn(ordner, eintraege));
    for (final e in eintraege.where((e) => e.istOrdner)) {
      if (tiefe + 1 > konfliktHoechstTiefe) {
        begrenzt = true;
        continue;
      }
      warteschlange.add((Konfliktkopie.verbinde(ordner, e.name), tiefe + 1));
    }
  }
  return KonfliktSuche(funde: funde, unpruefbar: unpruefbar, begrenzt: begrenzt);
}

/// Die Zeilen je Konfliktkopie. [vollerPfad]: Pfade relativ zur Wurzel statt
/// Namen im Ordner.
List<String> konfliktZeilen(
  List<Konfliktkopie> funde, {
  required bool vollerPfad,
}) {
  return [
    for (final k in funde)
      () {
        final kopie = vollerPfad ? k.pfad : k.name;
        final original = vollerPfad ? k.originalPfad : k.originalName;
        final stand = k.originalDa
            ? 'both files exist'
            : 'the original is not there';
        return "- '$kopie' is a conflict copy of '$original' ($stand)";
      }(),
  ];
}
