import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'fehler.dart';
import 'speicher.dart';

/// Wo der Kontextbereich liegt. Die Datei schreibt bis zum Einstellungsfenster
/// von Hand, wer das Plugin einrichtet; das Secret eines entfernten Speichers
/// kommt später in den Schlüsselbund, nie in diese Datei.
class Einstellungen {
  const Einstellungen({required this.art, this.pfad});

  final String art;
  final String? pfad;
}

/// Der Ort der Einstellungsdatei im Datenordner des Plugins (außerhalb des
/// Plugin-Ordners, damit eine Aktualisierung sie nicht überschreibt).
String standardEinstellungenPfad({Map<String, String>? umgebung}) {
  final env = umgebung ?? Platform.environment;
  final home = env['HOME'] ?? '';
  final String basis;
  if (Platform.isMacOS) {
    basis = p.join(home, 'Library', 'Application Support');
  } else {
    final xdg = env['XDG_CONFIG_HOME'];
    basis = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.config');
  }
  return p.join(basis, 'moocp-contextmanager', 'einstellungen.json');
}

/// Liest die Einstellungen. Jede Ursache eines Fehlers wird genannt.
Future<Einstellungen> leseEinstellungen(File datei) async {
  if (!await datei.exists()) {
    throw const KontextFehler(
      'The context area has not been set up yet: no settings file found. '
      'Ask the teacher to set up the context area in the plugin settings.',
    );
  }
  final String inhalt;
  try {
    inhalt = await datei.readAsString();
  } on FileSystemException {
    throw const KontextFehler(
      'The settings file cannot be read: check that it is readable by this user.',
    );
  } on FormatException {
    throw const KontextFehler(
      'The settings file cannot be read: it is not UTF-8 text.',
    );
  }
  final Object? json;
  try {
    json = jsonDecode(inhalt);
  } on FormatException {
    throw const KontextFehler(
      'The settings file cannot be read: it is not valid JSON.',
    );
  }
  if (json is! Map) {
    throw const KontextFehler(
      'The settings file cannot be read: it is not an object.',
    );
  }
  final art = json['art'];
  if (art != 'lokal') {
    throw KontextFehler(
      "The location type '$art' is not supported yet; only 'lokal' (local folder) works.",
    );
  }
  final pfad = json['pfad'];
  if (pfad is! String || pfad.isEmpty) {
    throw const KontextFehler(
      'The settings file names no folder for the local location.',
    );
  }
  // Ein relativer Pfad hinge am Ordner, aus dem moocp das Plugin startet.
  if (!p.isAbsolute(pfad)) {
    throw const KontextFehler(
      'The settings file must name an absolute folder path for the local location.',
    );
  }
  return Einstellungen(art: art!.toString(), pfad: pfad);
}

/// Liest die Einstellungen und öffnet den Kontextbereich, jedes Mal neu: Ändert
/// die Lehrkraft den Ort, wirkt das beim nächsten Aufruf, ohne Neustart.
Future<LokalerSpeicher> oeffneKontextbereich(File einstellungen) async {
  final e = await leseEinstellungen(einstellungen);
  return LokalerSpeicher.oeffnen(e.pfad!);
}
