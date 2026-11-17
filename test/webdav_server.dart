// Ein kleiner WebDAV-Server für die Tests, im Testprozess gestartet. Er bedient
// einen Ordner auf der Platte (den Ordner des Tests), so dass die Tests den
// Inhalt direkt prüfen können. Er spricht nur, was der Kontextbereich braucht:
// PROPFIND, GET, PUT (mit If-Match und If-None-Match), MKCOL und MOVE, dazu die
// Anmeldung per Basic. Bedingungen und Antworten folgen RFC 4918 und RFC 9110.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Der Pfad, unter dem der Server den Ordner anbietet.
const webdavPfad = '/kontext';

class WebDavTestServer {
  WebDavTestServer({
    required this.ordner,
    required this.benutzer,
    required this.passwort,
  });

  /// Der Ordner auf der Platte, den der Server bedient.
  final Directory ordner;
  final String benutzer;
  final String passwort;

  HttpServer? _server;
  int? _port;

  /// Antwortet jede Anfrage mit diesem Status (etwa 401 oder 403), ohne den Inhalt
  /// anzusehen. Null: der Server antwortet normal.
  int? erzwungenerStatus;

  /// Zusätzliche Namen, die jede Auflistung der Wurzel meldet, roh und ungeprüft
  /// (etwa mit `/` oder Steuerzeichen), um die Prüfung der Namen zu testen.
  final List<String> zusaetzlicheNamen = [];

  /// Antwortet jede Leseanfrage (GET) mit diesem Status, Auflistungen bleiben
  /// unberührt. Null: Lesen wie sonst.
  int? statusFuerLesen;

  /// Die Adresse der Wurzel, mit abschließendem Schrägstrich.
  Uri get adresse => Uri.parse('http://127.0.0.1:$_port$webdavPfad/');

  /// Startet den Server; nach einem Anhalten auf demselben Port.
  Future<void> starten() async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _port ?? 0,
    );
    _port = server.port;
    _server = server;
    server.listen(_bearbeite);
  }

  /// Hält den Server an: Verbindungen werden abgelehnt, als sei der Ort aus.
  Future<void> anhalten() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> beenden() => anhalten();

  Future<void> _bearbeite(HttpRequest anfrage) async {
    final antwort = anfrage.response;
    try {
      if (erzwungenerStatus != null) {
        antwort.statusCode = erzwungenerStatus!;
        return;
      }
      if (anfrage.headers.value(HttpHeaders.authorizationHeader) !=
          'Basic ${base64.encode(utf8.encode('$benutzer:$passwort'))}') {
        antwort
          ..statusCode = HttpStatus.unauthorized
          ..headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            'Basic realm="test"',
          );
        return;
      }
      final teile = anfrage.uri.pathSegments;
      if (teile.isEmpty || '/${teile.first}' != webdavPfad) {
        antwort.statusCode = HttpStatus.notFound;
        return;
      }
      final rest = teile.sublist(1).where((t) => t.isNotEmpty).toList();
      if (rest.contains('..')) {
        antwort.statusCode = HttpStatus.forbidden;
        return;
      }
      final ziel = p.joinAll([ordner.path, ...rest]);
      switch (anfrage.method) {
        case 'PROPFIND':
          await _propfind(anfrage, rest, ziel);
        case 'GET':
          await _lese(anfrage, ziel);
        case 'PUT':
          await _schreibe(anfrage, ziel);
        case 'MKCOL':
          await _mkcol(anfrage, ziel);
        case 'MOVE':
          await _verschiebe(anfrage, rest, ziel);
        default:
          antwort.statusCode = HttpStatus.methodNotAllowed;
      }
    } finally {
      await antwort.close();
    }
  }

  Future<void> _propfind(
    HttpRequest anfrage,
    List<String> rest,
    String ziel,
  ) async {
    final typ = await FileSystemEntity.type(ziel);
    if (typ == FileSystemEntityType.notFound) {
      anfrage.response.statusCode = HttpStatus.notFound;
      return;
    }
    final tiefe = anfrage.headers.value('Depth') ?? 'infinity';
    final eintraege = <String>[await _eintrag(ziel, rest)];
    if (typ == FileSystemEntityType.directory && tiefe != '0') {
      final kinder = await Directory(ziel).list().toList();
      kinder.sort((a, b) => a.path.compareTo(b.path));
      for (final kind in kinder) {
        final name = p.basename(kind.path);
        eintraege.add(await _eintrag(kind.path, [...rest, name]));
      }
      if (rest.isEmpty) {
        for (final name in zusaetzlicheNamen) {
          eintraege.add(
            '<d:response><d:href>$webdavPfad/${Uri.encodeComponent(name)}</d:href>'
            '<d:propstat><d:prop><d:resourcetype/></d:prop>'
            '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
          );
        }
      }
    }
    anfrage.response
      ..statusCode = HttpStatus.multiStatus
      ..headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      )
      ..write(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<d:multistatus xmlns:d="DAV:">${eintraege.join()}</d:multistatus>',
      );
  }

  /// Ein Eintrag der Antwort: Adresse, Ordner-Kennung und ETag einer Datei.
  Future<String> _eintrag(String pfad, List<String> teile) async {
    final ordner = await FileSystemEntity.isDirectory(pfad);
    final href =
        '$webdavPfad/${teile.map(Uri.encodeComponent).join('/')}${ordner && teile.isNotEmpty ? '/' : ''}';
    final eigenschaften = ordner
        ? '<d:resourcetype><d:collection/></d:resourcetype>'
        : '<d:resourcetype/><d:getetag>"${await _etag(pfad)}"</d:getetag>';
    return '<d:response><d:href>$href</d:href><d:propstat><d:prop>$eigenschaften'
        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
  }

  Future<void> _lese(HttpRequest anfrage, String ziel) async {
    final antwort = anfrage.response;
    if (statusFuerLesen != null) {
      antwort.statusCode = statusFuerLesen!;
      return;
    }
    final typ = await FileSystemEntity.type(ziel);
    if (typ == FileSystemEntityType.notFound) {
      antwort.statusCode = HttpStatus.notFound;
      return;
    }
    if (typ == FileSystemEntityType.directory) {
      antwort.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final bytes = await File(ziel).readAsBytes();
    antwort
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.etagHeader, '"${_hash(bytes)}"')
      ..add(bytes);
  }

  Future<void> _schreibe(HttpRequest anfrage, String ziel) async {
    final antwort = anfrage.response;
    final bytes = await anfrage.fold<List<int>>(
      <int>[],
      (alt, teil) => alt..addAll(teil),
    );
    final vorhanden = await FileSystemEntity.type(ziel);
    if (vorhanden == FileSystemEntityType.directory) {
      antwort.statusCode = HttpStatus.conflict;
      return;
    }
    if (!await Directory(p.dirname(ziel)).exists()) {
      antwort.statusCode = HttpStatus.conflict;
      return;
    }
    final ifNoneMatch = anfrage.headers.value(HttpHeaders.ifNoneMatchHeader);
    final ifMatch = anfrage.headers.value(HttpHeaders.ifMatchHeader);
    final existiert = vorhanden == FileSystemEntityType.file;
    if (ifNoneMatch == '*' && existiert) {
      antwort.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    if (ifMatch != null) {
      final stand = existiert
          ? '"${_hash(await File(ziel).readAsBytes())}"'
          : null;
      if (stand != ifMatch) {
        antwort.statusCode = HttpStatus.preconditionFailed;
        return;
      }
    }
    await File(ziel).writeAsBytes(bytes, flush: true);
    antwort
      ..statusCode = existiert ? HttpStatus.noContent : HttpStatus.created
      ..headers.set(HttpHeaders.etagHeader, '"${_hash(bytes)}"');
  }

  Future<void> _mkcol(HttpRequest anfrage, String ziel) async {
    final antwort = anfrage.response;
    if (await FileSystemEntity.type(ziel) != FileSystemEntityType.notFound) {
      antwort.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    if (!await Directory(p.dirname(ziel)).exists()) {
      antwort.statusCode = HttpStatus.conflict;
      return;
    }
    await Directory(ziel).create();
    antwort.statusCode = HttpStatus.created;
  }

  Future<void> _verschiebe(
    HttpRequest anfrage,
    List<String> rest,
    String ziel,
  ) async {
    final antwort = anfrage.response;
    if (await FileSystemEntity.type(ziel) == FileSystemEntityType.notFound) {
      antwort.statusCode = HttpStatus.notFound;
      return;
    }
    // Wie ein Server: If-Match verlangt den Stand der Quelle, sonst 412.
    final ifMatch = anfrage.headers.value(HttpHeaders.ifMatchHeader);
    if (ifMatch != null &&
        ifMatch != '"${_hash(await File(ziel).readAsBytes())}"') {
      antwort.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    final ziele = Uri.parse(anfrage.headers.value('Destination') ?? '');
    final zielTeile = ziele.pathSegments
        .sublist(1)
        .where((t) => t.isNotEmpty)
        .toList();
    final zielPfad = p.joinAll([ordner.path, ...zielTeile]);
    final ueberschreiben = anfrage.headers.value('Overwrite') != 'F';
    final vorhanden =
        await FileSystemEntity.type(zielPfad) != FileSystemEntityType.notFound;
    if (vorhanden && !ueberschreiben) {
      antwort.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    if (!await Directory(p.dirname(zielPfad)).exists()) {
      antwort.statusCode = HttpStatus.conflict;
      return;
    }
    await File(ziel).rename(zielPfad);
    antwort.statusCode = vorhanden ? HttpStatus.noContent : HttpStatus.created;
  }

  Future<String> _etag(String pfad) async =>
      _hash(await File(pfad).readAsBytes());

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
}
