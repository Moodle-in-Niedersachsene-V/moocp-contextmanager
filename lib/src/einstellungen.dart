import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'fehler.dart';

/// Wo der Kontextbereich liegt. Die Datei schreibt bis zum Einstellungsfenster
/// von Hand, wer das Plugin einrichtet. Das Passwort eines WebDAV-Speichers
/// liegt nie in dieser Datei, sondern im Schlüsselbund (ADR 0004).
class Einstellungen {
  const Einstellungen._({
    required this.art,
    this.pfad,
    this.adresse,
    this.benutzer,
  });

  /// Ein lokaler Ordner als Wurzel.
  factory Einstellungen.lokal(String pfad) =>
      Einstellungen._(art: 'lokal', pfad: pfad);

  /// Ein WebDAV-Server als Wurzel, mit dem Benutzer; das Passwort kommt aus dem
  /// Schlüsselbund.
  factory Einstellungen.webdav({
    required Uri adresse,
    required String benutzer,
  }) => Einstellungen._(art: 'webdav', adresse: adresse, benutzer: benutzer);

  /// `lokal` oder `webdav`.
  final String art;

  /// Der absolute Ordner bei `lokal`.
  final String? pfad;

  /// Die Adresse der Wurzel bei `webdav`, ohne Zugangsdaten.
  final Uri? adresse;

  /// Der Benutzer bei `webdav`.
  final String? benutzer;

  /// Die Kennung des Ortes, ohne Geheimnis. Sie steht in jedem Ausstand-Vorgang,
  /// damit eine Wiederholung nur an dem Ort schreibt, an dem der Vorgang entstand.
  String get kennung => switch (art) {
    'webdav' => 'webdav:$adresse',
    _ => 'lokal:$pfad',
  };

  /// Das Konto im Schlüsselbund: der Benutzer an der Adresse.
  String get konto => '$benutzer@$adresse';

  /// Der Inhalt der Einstellungsdatei. Das Passwort steht nie darin (A6).
  Map<String, Object?> alsJson() => switch (art) {
    'webdav' => {'art': art, 'adresse': adresse.toString(), 'benutzer': benutzer},
    _ => {'art': art, 'pfad': pfad},
  };
}

/// Schreibt die Einstellungsdatei (E8). Der Inhalt geht zuerst in eine Datei
/// daneben und wird dann umbenannt: Bricht das Schreiben ab, bleibt die alte
/// Datei, wie sie war, und es liegt kein halber Inhalt im Datenordner.
Future<void> schreibeEinstellungen(File datei, Einstellungen einstellungen) async {
  await datei.parent.create(recursive: true);
  final tmp = File('${datei.path}.tmp');
  await tmp.writeAsString(jsonEncode(einstellungen.alsJson()), flush: true);
  await tmp.rename(datei.path);
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
  return switch (json['art']) {
    'lokal' => _lokal(json),
    'webdav' => _webdav(json),
    final art => throw KontextFehler(
      "The location type '$art' is not supported; use 'lokal' (local folder) or 'webdav'.",
    ),
  };
}

Einstellungen _lokal(Map<Object?, Object?> json) {
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
  return Einstellungen.lokal(pfad);
}

Einstellungen _webdav(Map<Object?, Object?> json) {
  final adresse = json['adresse'];
  final benutzer = json['benutzer'];
  if (adresse is! String || adresse.isEmpty) {
    throw const KontextFehler(
      'The settings file names no address for the WebDAV location.',
    );
  }
  if (benutzer is! String || benutzer.isEmpty) {
    throw const KontextFehler(
      'The settings file names no user for the WebDAV location.',
    );
  }
  return Einstellungen.webdav(
    adresse: pruefeAdresse(adresse),
    benutzer: benutzer,
  );
}

/// Prüft die Adresse eines WebDAV-Speichers. Sie braucht https; http nur zu
/// einer Schleife (127.0.0.1, ::1, localhost), weil das Passwort sonst offen
/// über das Netz ginge. Zugangsdaten gehören nicht in die Adresse (A6).
Uri pruefeAdresse(String text) {
  final adresse = Uri.tryParse(text);
  if (adresse == null || !adresse.hasAuthority || adresse.host.isEmpty) {
    throw const KontextFehler(
      'The WebDAV address is not a valid absolute address.',
    );
  }
  if (adresse.userInfo.isNotEmpty) {
    throw const KontextFehler(
      'The WebDAV address must not contain a user or password; enter them in the settings window.',
    );
  }
  final schleife =
      adresse.host == 'localhost' ||
      (InternetAddress.tryParse(adresse.host)?.isLoopback ?? false);
  if (adresse.scheme == 'https' || (adresse.scheme == 'http' && schleife)) {
    return adresse;
  }
  throw const KontextFehler(
    'The WebDAV address must use https; http is allowed only for 127.0.0.1 or localhost.',
  );
}
