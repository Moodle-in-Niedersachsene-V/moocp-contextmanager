import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'fehler.dart';
import 'pfad.dart';
import 'speicher.dart';

/// Der Kontextbereich auf einem WebDAV-Server (E3, E4). Die Wurzel ist eine
/// Adresse; alle Dateien liegen darunter. Die Version einer Datei ist ihr ETag,
/// ohne Anführungszeichen. Schreiben verlangt das ETag als `If-Match` oder
/// `If-None-Match: *`, so dass der Server selbst ablehnt, wenn sich die Datei
/// geändert hat.
///
/// Der Ort antwortet nicht (Netzfehler, Zeitablauf, 5xx): [KontextNichtErreichbar].
/// Anmeldung, Adresse und fehlende Dateien sind Ursachen, die sichtbar bleiben:
/// [KontextFehler].
class WebDavSpeicher extends Kontextspeicher {
  WebDavSpeicher._(
    this._wurzel,
    this._benutzer,
    this._geheimnis,
    this._zeitlimit,
  );

  /// Die Wurzel als Adresse mit abschließendem Schrägstrich.
  final Uri _wurzel;
  final String _benutzer;

  /// Das Passwort aus dem Schlüsselbund. Es geht nur in den Basic-Kopf und
  /// taucht in keiner Meldung auf.
  final String _geheimnis;
  final Duration _zeitlimit;

  /// Öffnet die Wurzel: Ein PROPFIND auf sie zeigt, ob der Server antwortet, ob
  /// die Anmeldung stimmt und ob die Wurzel ein Ordner ist.
  static Future<WebDavSpeicher> oeffnen({
    required Uri adresse,
    required String benutzer,
    required String geheimnis,
    required Duration zeitlimit,
  }) async {
    final wurzel = adresse.path.endsWith('/')
        ? adresse
        : adresse.replace(path: '${adresse.path}/');
    final speicher = WebDavSpeicher._(wurzel, benutzer, geheimnis, zeitlimit);
    final antwort = await speicher._anfrage(
      'PROPFIND',
      wurzel,
      kopf: {'Depth': '0', 'Content-Type': 'application/xml'},
      koerper: _propfindKoerper,
    );
    if (antwort.status == HttpStatus.notFound) {
      throw const KontextFehler(
        'The context root folder does not exist on the WebDAV server.',
      );
    }
    if (antwort.status != HttpStatus.multiStatus) {
      throw speicher._fehler(antwort.status, '');
    }
    final eigener = speicher._lese(antwort, wurzel, '');
    if (!eigener.istOrdner) {
      throw const KontextFehler(
        'The WebDAV address names a file, not a folder.',
      );
    }
    return speicher;
  }

  @override
  Future<List<Eintrag>> liste(String relativ) async {
    final teile = pfadTeile(relativ);
    final url = _url(teile, ordner: true);
    final antwort = await _anfrage(
      'PROPFIND',
      url,
      kopf: {'Depth': '1', 'Content-Type': 'application/xml'},
      koerper: _propfindKoerper,
    );
    if (antwort.status == HttpStatus.notFound) {
      throw KontextFehler("'$relativ' does not exist in the context area.");
    }
    if (antwort.status != HttpStatus.multiStatus) {
      throw _fehler(antwort.status, relativ);
    }
    final liste = _lesenListe(antwort, url, relativ);
    if (!liste.eigener.istOrdner) {
      throw KontextFehler("'$relativ' is not a folder.");
    }
    return liste.kinder..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<Inhalt?> holeInhalt(String relativ) async {
    final teile = pfadTeile(relativ);
    if (teile.isEmpty) {
      throw KontextFehler(
        "'$relativ' is a folder; use context_list for folders.",
      );
    }
    final antwort = await _anfrage('GET', _url(teile));
    if (antwort.status == HttpStatus.notFound) return null;
    // Viele Server verweigern GET auf einen Ordner mit 405; dann fragen wir nach, was es ist.
    if (antwort.status == HttpStatus.methodNotAllowed &&
        await _istOrdner(teile, relativ)) {
      throw KontextFehler(
        "'$relativ' is a folder; use context_list for folders.",
      );
    }
    if (antwort.status != HttpStatus.ok) {
      throw _fehler(antwort.status, relativ);
    }
    return Inhalt(antwort.bytes, _version(antwort, relativ));
  }

  /// Ob der Pfad auf dem Server ein Ordner ist (PROPFIND auf den Pfad selbst).
  Future<bool> _istOrdner(List<String> teile, String relativ) async {
    final url = _url(teile, ordner: true);
    final antwort = await _anfrage(
      'PROPFIND',
      url,
      kopf: {'Depth': '0', 'Content-Type': 'application/xml'},
      koerper: _propfindKoerper,
    );
    if (antwort.status != HttpStatus.multiStatus) return false;
    return _lese(antwort, url, relativ).istOrdner;
  }

  @override
  Future<void> ablegen(
    String relativ,
    List<int> bytes, {
    required String? erwartet,
  }) async {
    final teile = schreibTeile(relativ);
    await _ordnerAnlegen(teile.sublist(0, teile.length - 1), relativ);
    final kopf = <String, String>{
      HttpHeaders.contentTypeHeader: 'text/markdown; charset=utf-8',
      // Die Bedingung des Servers: Die Datei darf sich seit dem Lesen nicht geändert haben.
      if (erwartet == null)
        HttpHeaders.ifNoneMatchHeader: '*'
      else
        HttpHeaders.ifMatchHeader: '"$erwartet"',
    };
    final antwort = await _anfrage(
      'PUT',
      _url(teile),
      kopf: kopf,
      koerper: bytes,
    );
    switch (antwort.status) {
      case HttpStatus.ok || HttpStatus.created || HttpStatus.noContent:
        return;
      case HttpStatus.preconditionFailed:
        throw KontextKonflikt(
          erwartet == null
              ? "'$relativ' already exists. Read it and pass its version to replace it, or choose another path."
              : "'$relativ' changed since it was read. Read it again and check the change before writing.",
        );
      case HttpStatus.conflict:
        throw KontextFehler(
          "The folder of '$relativ' does not exist on the WebDAV server.",
        );
      default:
        throw _fehler(antwort.status, relativ);
    }
  }

  /// Verschiebt per MOVE. `Overwrite: F` lässt ein vorhandenes Ziel stehen, und
  /// `If-Match` mit dem gelesenen ETag der Quelle lässt die Verschiebung scheitern,
  /// wenn sich die Quelle geändert hat. Beides prüft der Server in einem Schritt.
  @override
  Future<void> verschiebeDatei(
    String von,
    String nach, {
    required String erwartet,
  }) async {
    final ziel = pfadTeile(nach);
    await _ordnerAnlegen(ziel.sublist(0, ziel.length - 1), nach);
    final antwort = await _anfrage(
      'MOVE',
      _url(pfadTeile(von)),
      kopf: {
        'Destination': _url(ziel).toString(),
        // Ein vorhandenes Ziel wird nie überschrieben.
        'Overwrite': 'F',
        HttpHeaders.ifMatchHeader: '"$erwartet"',
      },
    );
    switch (antwort.status) {
      case HttpStatus.ok || HttpStatus.created || HttpStatus.noContent:
        return;
      case HttpStatus.preconditionFailed:
        throw KontextKonflikt(
          "'$von' changed since it was read, or '$nach' already exists; nothing was moved. "
          'Read it again and choose another path.',
        );
      case HttpStatus.notFound:
        throw KontextFehler("'$von' does not exist in the context area.");
      default:
        throw _fehler(antwort.status, von);
    }
  }

  /// Legt die Ordner des Pfads an, die es noch nicht gibt. MKCOL auf einen
  /// vorhandenen Ordner antwortet mit 405; das ist kein Fehler.
  Future<void> _ordnerAnlegen(List<String> ordner, String relativ) async {
    for (var n = 1; n <= ordner.length; n++) {
      final antwort = await _anfrage(
        'MKCOL',
        _url(ordner.sublist(0, n), ordner: true),
      );
      if (antwort.status == HttpStatus.created ||
          antwort.status == HttpStatus.methodNotAllowed) {
        continue;
      }
      if (antwort.status == HttpStatus.conflict) {
        throw KontextFehler(
          "The folder of '$relativ' cannot be created: its parent is missing on the WebDAV server.",
        );
      }
      throw _fehler(antwort.status, relativ);
    }
  }

  /// Das ETag als Version. Ein schwaches ETag oder keines reicht nicht: Ohne
  /// starkes ETag gibt es keine Stand-Prüfung, die der Server erzwingt.
  String _version(_Antwort antwort, String relativ) {
    final etag = antwort.kopf[HttpHeaders.etagHeader];
    if (etag == null) {
      throw KontextFehler(
        "The WebDAV server sends no ETag for '$relativ'; without it changes cannot be checked. Nothing was written.",
      );
    }
    if (etag.startsWith('W/')) {
      throw KontextFehler(
        "The WebDAV server sends only weak ETags for '$relativ'; changes cannot be checked. Nothing was written.",
      );
    }
    if (etag.length >= 2 && etag.startsWith('"') && etag.endsWith('"')) {
      return etag.substring(1, etag.length - 1);
    }
    return etag;
  }

  /// Die Antwort eines Servers in eine Meldung, die die KI und die Lehrkraft
  /// verstehen. Ohne Passwort, ohne Adresse.
  KontextFehler _fehler(int status, String relativ) {
    if (status == HttpStatus.unauthorized) {
      return const KontextFehler(
        'The WebDAV server refused the user or the password (HTTP 401). '
        'Check them in the settings window; nothing was written.',
      );
    }
    if (status == HttpStatus.forbidden) {
      return KontextFehler(
        "The WebDAV server denies access to '$relativ' (HTTP 403): this user "
        'has no permission for it. Check the permissions on the server; nothing was written.',
      );
    }
    if (status >= 300 && status < 400) {
      return KontextFehler(
        'The WebDAV server redirects the request (HTTP $status). '
        'Enter the final address in the settings window; nothing was written.',
      );
    }
    if (status >= 500) {
      return KontextNichtErreichbar(
        'The WebDAV server answered with an error (HTTP $status); nothing was written.',
      );
    }
    return KontextFehler(
      "The WebDAV server answered HTTP $status for '$relativ'; nothing was written.",
    );
  }

  /// Die Adresse einer Datei oder eines Ordners unter der Wurzel.
  Uri _url(List<String> teile, {bool ordner = false}) {
    return _wurzel.resolveUri(
      Uri(pathSegments: ordner ? [...teile, ''] : teile),
    );
  }

  /// Ein Ergebnis eines Ordners: der eigene Eintrag und die Kinder.
  ({Eintrag eigener, List<Eintrag> kinder}) _lesenListe(
    _Antwort antwort,
    Uri url,
    String relativ,
  ) {
    final eigener = _lese(antwort, url, relativ);
    final kinder = <Eintrag>[];
    final urlTeile = _segmente(url);
    for (final antwortEintrag in _eintraege(antwort, relativ)) {
      final teile = _segmente(antwortEintrag.url);
      if (teile.length == urlTeile.length) continue; // der Ordner selbst
      if (teile.length != urlTeile.length + 1) continue;
      if (!_gleich(teile.sublist(0, urlTeile.length), urlTeile)) continue;
      final name = teile.last;
      _pruefeName(name, relativ);
      kinder.add(Eintrag(name, istOrdner: antwortEintrag.istOrdner));
    }
    return (eigener: eigener, kinder: kinder);
  }

  /// Ein Name aus einer Auflistung muss ein einzelner Pfadteil sein: ohne `/`
  /// (auch das kodierte `%2F`), ohne `.` und `..` und ohne Steuerzeichen. Sonst
  /// wird die ganze Auflistung abgewiesen, statt einen Namen zu übergehen.
  static void _pruefeName(String name, String relativ) {
    final ungueltig =
        name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.codeUnits.any((c) => c < 0x20 || c == 0x7f);
    if (ungueltig) {
      throw KontextFehler(
        "The WebDAV server sent a name that is not allowed in the listing of '$relativ'; the listing is refused.",
      );
    }
  }

  /// Der Eintrag des Ordners selbst (das erste Element der Antwort).
  Eintrag _lese(_Antwort antwort, Uri url, String relativ) {
    final soll = _segmente(url);
    for (final e in _eintraege(antwort, relativ)) {
      if (_gleich(_segmente(e.url), soll)) {
        return Eintrag(soll.isEmpty ? '' : soll.last, istOrdner: e.istOrdner);
      }
    }
    throw KontextFehler(
      "The WebDAV server sent an unreadable listing for '$relativ'.",
    );
  }

  /// Alle `response`-Elemente eines Multistatus, mit Adresse und Ordner-Kennung.
  List<({Uri url, bool istOrdner})> _eintraege(
    _Antwort antwort,
    String relativ,
  ) {
    final XmlDocument dokument;
    try {
      dokument = XmlDocument.parse(antwort.text);
    } on XmlException {
      throw KontextFehler(
        "The WebDAV server sent an unreadable listing for '$relativ'.",
      );
    }
    final eintraege = <({Uri url, bool istOrdner})>[];
    for (final antworten in dokument.findAllElements(
      'response',
      namespaceUri: _dav,
    )) {
      final href = antworten
          .findElements('href', namespaceUri: _dav)
          .map((h) => h.innerText.trim())
          .firstOrNull;
      if (href == null) continue;
      final Uri url;
      try {
        url = Uri.parse(href);
      } on FormatException {
        throw KontextFehler(
          "The WebDAV server sent an unreadable listing for '$relativ'.",
        );
      }
      final istOrdner = antworten
          .findAllElements('collection', namespaceUri: _dav)
          .isNotEmpty;
      eintraege.add((url: url, istOrdner: istOrdner));
    }
    return eintraege;
  }

  /// Die Pfadteile einer Adresse, ohne leeren Rest des Schrägstrichs.
  static List<String> _segmente(Uri url) =>
      url.pathSegments.where((s) => s.isNotEmpty).toList();

  static bool _gleich(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var n = 0; n < a.length; n++) {
      if (a[n] != b[n]) return false;
    }
    return true;
  }

  /// Eine Anfrage an den Server mit Anmeldung, Zeitlimit und ohne Weiterleitung:
  /// Die Zugangsdaten gehen nur an die eingetragene Adresse.
  Future<_Antwort> _anfrage(
    String methode,
    Uri ziel, {
    Map<String, String> kopf = const {},
    List<int>? koerper,
  }) async {
    final client = HttpClient()..connectionTimeout = _zeitlimit;
    try {
      return await _ausfuehren(
        client,
        methode,
        ziel,
        kopf,
        koerper,
      ).timeout(_zeitlimit);
    } on TimeoutException {
      throw const KontextNichtErreichbar(
        'The WebDAV server did not answer in time.',
      );
    } on SocketException {
      throw const KontextNichtErreichbar(
        'The WebDAV server cannot be reached.',
      );
    } on HttpException {
      throw const KontextNichtErreichbar(
        'The WebDAV server closed the connection.',
      );
    } on HandshakeException {
      throw const KontextFehler(
        'The secure connection to the WebDAV server failed (certificate not trusted). Nothing was written.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_Antwort> _ausfuehren(
    HttpClient client,
    String methode,
    Uri ziel,
    Map<String, String> kopf,
    List<int>? koerper,
  ) async {
    final anfrage = await client.openUrl(methode, ziel);
    anfrage.followRedirects = false;
    anfrage.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64.encode(utf8.encode('$_benutzer:$_geheimnis'))}',
    );
    kopf.forEach(anfrage.headers.set);
    if (koerper != null) {
      anfrage.headers.contentLength = koerper.length;
      anfrage.add(koerper);
    }
    final antwort = await anfrage.close();
    // Eine Antwort über der Grenze wird nicht vollständig gelesen: Ein Server, der
    // endlos sendet, darf das Plugin nicht in den Speicher treiben.
    final bytes = <int>[];
    await for (final teil in antwort) {
      bytes.addAll(teil);
      if (bytes.length > hoechstgroesseAntwort) {
        throw const KontextFehler(
          'The WebDAV server sent more data than the plugin reads; nothing was written.',
        );
      }
    }
    final kopfwerte = <String, String>{};
    antwort.headers.forEach((name, werte) {
      kopfwerte[name.toLowerCase()] = werte.join(', ');
    });
    return _Antwort(antwort.statusCode, kopfwerte, bytes);
  }

  static const _dav = 'DAV:';

  static final _propfindKoerper = utf8.encode(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getetag/></d:prop></d:propfind>',
  );
}

/// Die größte Antwort, die das Plugin von einem WebDAV-Server annimmt (8 MiB).
/// Eine Plandatei ist weit kleiner; die Grenze schützt vor einem Server, der
/// ohne Ende sendet, und vor einer Datei, die das Plugin nicht im Speicher halten soll.
const hoechstgroesseAntwort = 8 * 1024 * 1024;

/// Die Antwort eines Servers: Status, Kopf (Namen klein) und Körper.
class _Antwort {
  const _Antwort(this.status, this.kopf, this.bytes);

  final int status;
  final Map<String, String> kopf;
  final List<int> bytes;

  String get text => utf8.decode(bytes, allowMalformed: true);
}
