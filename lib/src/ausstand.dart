import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'app.dart';
import 'fehler.dart';
import 'schreibauftrag.dart';
import 'speicher.dart';

/// Ein Schreibvorgang im Ausstand: ein gültiger Auftrag, den der Kontextbereich
/// nicht annehmen konnte, weil der Ort nicht antwortete (E2).
class Ausstehend {
  const Ausstehend({
    required this.id,
    required this.zeit,
    required this.auftrag,
  });

  final String id;

  /// Der Zeitpunkt, zu dem der Vorgang zurückgestellt wurde (UTC).
  final DateTime zeit;

  final Schreibauftrag auftrag;
}

/// Der Ausstand im Datenordner des Plugins, außerhalb der Wurzel. Je Vorgang
/// eine Datei; sie wird erst gelöscht, wenn der Vorgang im Kontextbereich
/// geprüft steht oder die Lehrkraft ihn ablehnt.
class Ausstand {
  Ausstand(this.ordner);

  final Directory ordner;

  /// Hält den Auftrag zurück und liefert seine Kennung. Schlägt das Speichern
  /// fehl, wirft es, damit nichts als „zurückgestellt“ gemeldet wird.
  Future<Ausstehend> merke(Schreibauftrag auftrag) async {
    final zeit = DateTime.now().toUtc();
    final id = '${zeit.microsecondsSinceEpoch}-${_zufall()}';
    final ziel = File(p.join(ordner.path, '$id.json'));
    final tmp = File('${ziel.path}.tmp');
    try {
      await ordner.create(recursive: true);
      await tmp.writeAsString(
        jsonEncode({
          'id': id,
          'zeit': zeit.toIso8601String(),
          ...auftrag.alsJson(),
        }),
        flush: true,
      );
      await tmp.rename(ziel.path);
    } on FileSystemException {
      throw const KontextFehler(
        'The write could not be kept as pending: the data folder of the plugin '
        'cannot be written. Nothing was written.',
      );
    }
    return Ausstehend(id: id, zeit: zeit, auftrag: auftrag);
  }

  /// Alle offenen Vorgänge, der Reihe nach von ihrer Zeit. Ist eine Datei nicht
  /// lesbar, wirft es und nennt sie: Übergangen wird nichts.
  Future<List<Ausstehend>> liste() async {
    if (!await ordner.exists()) return const [];
    final eintraege = <Ausstehend>[];
    final List<FileSystemEntity> dateien;
    try {
      dateien = await ordner
          .list()
          .where((e) => e.path.endsWith('.json'))
          .toList();
    } on FileSystemException {
      throw const KontextFehler(
        'The pending writes cannot be read: the data folder of the plugin is not readable.',
      );
    }
    for (final datei in dateien) {
      final name = p.basename(datei.path);
      try {
        final json = jsonDecode(await File(datei.path).readAsString());
        if (json is! Map<String, Object?>) throw const FormatException();
        final zeit = DateTime.parse(json['zeit'] as String);
        eintraege.add(
          Ausstehend(
            id: json['id'] as String,
            zeit: zeit,
            auftrag: Schreibauftrag.ausJson(json),
          ),
        );
      } on Object {
        throw KontextFehler(
          "The pending write '$name' cannot be read. Nothing was replayed; "
          'the file must be removed by hand after it has been checked.',
        );
      }
    }
    eintraege.sort((a, b) {
      final nach = a.zeit.compareTo(b.zeit);
      return nach != 0 ? nach : a.id.compareTo(b.id);
    });
    return eintraege;
  }

  /// Entfernt einen Vorgang, nachdem er geschrieben oder abgelehnt wurde.
  Future<void> entferne(String id) async {
    try {
      await File(p.join(ordner.path, '$id.json')).delete();
    } on FileSystemException {
      throw KontextFehler(
        "The pending write $id is written, but its file cannot be removed; "
        'it would be replayed again. Remove it by hand.',
      );
    }
  }

  static String _zufall() {
    final r = Random.secure();
    return List.generate(
      4,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// Der Ausgang der Wiederholung eines Vorgangs im Ausstand.
enum WiederholungAusgang {
  /// Geschrieben und zurückgelesen; der Vorgang ist aus dem Ausstand entfernt.
  geschrieben,

  /// Die Datei hat sich seit dem Zurückstellen geändert oder ist da: nichts geschrieben.
  konflikt,

  /// Die Lehrkraft hat abgelehnt; der Vorgang ist aus dem Ausstand entfernt.
  abgelehnt,

  /// Die Freigabe wurde abgebrochen oder lief in die Zeit; der Vorgang bleibt.
  abgebrochen,

  /// Geschrieben, aber nicht im Rücklesen bestätigt; der Vorgang bleibt.
  nichtGeprueft,

  /// Der Ort antwortet nicht mehr; die Wiederholung hält an, der Rest bleibt.
  nichtErreichbar,

  /// Eine andere Ursache (etwa moocp antwortet nicht); der Vorgang bleibt.
  fehler,
}

/// Das Ergebnis je Vorgang im Ausstand.
class Wiederholung {
  const Wiederholung(this.ausstehend, this.ausgang, this.meldung);

  final Ausstehend ausstehend;
  final WiederholungAusgang ausgang;

  /// Was die Antwort dazu sagt, ohne den Inhalt des Vorgangs.
  final String meldung;
}

/// Wiederholt die Vorgänge im Ausstand der Reihe nach (E2). Jeder
/// Vorgang geht durch dieselbe Stand-Prüfung wie ein neues Schreiben und wird
/// vor dem Schreiben erneut freigegeben. Ein Konflikt hält nur den einen Vorgang
/// an; ein nicht erreichbarer Ort hält die Wiederholung an.
Future<List<Wiederholung>> wiederholeAusstand({
  required Ausstand ausstand,
  required Future<LokalerSpeicher> Function() oeffnen,
  required AppAnschluss app,
  required String? aufruf,
  required List<Ausstehend> vorgaenge,
}) async {
  final ergebnisse = <Wiederholung>[];
  for (final vorgang in vorgaenge) {
    final a = vorgang.auftrag;
    final LokalerSpeicher speicher;
    try {
      speicher = await oeffnen();
    } on KontextNichtErreichbar catch (f) {
      ergebnisse.add(
        Wiederholung(vorgang, WiederholungAusgang.nichtErreichbar, f.meldung),
      );
      break;
    }
    try {
      await speicher.pruefeStand(a.pfad, erwartet: a.version);
    } on KontextKonflikt catch (f) {
      ergebnisse.add(
        Wiederholung(
          vorgang,
          WiederholungAusgang.konflikt,
          '${f.meldung} Kept as pending; nothing was overwritten.',
        ),
      );
      continue;
    } on KontextFehler catch (f) {
      ergebnisse.add(
        Wiederholung(vorgang, WiederholungAusgang.fehler, f.meldung),
      );
      continue;
    }

    final Freigabeausgang ausgang;
    try {
      ausgang = await frageFreigabe(
        app,
        aufruf,
        a,
        titel: 'Gespeicherte Änderung im Kontextbereich speichern?',
        vermerk: 'Aus dem Ausstand vom ${vorgang.zeit.toIso8601String()}',
      );
    } on KontextFehler catch (f) {
      ergebnisse.add(
        Wiederholung(vorgang, WiederholungAusgang.fehler, f.meldung),
      );
      break;
    }
    switch (ausgang) {
      case Freigabeausgang.abgelehnt:
        await ausstand.entferne(vorgang.id);
        ergebnisse.add(
          Wiederholung(
            vorgang,
            WiederholungAusgang.abgelehnt,
            'The teacher declined it; removed from the pending writes.',
          ),
        );
        continue;
      case Freigabeausgang.abgebrochen:
        ergebnisse.add(
          Wiederholung(
            vorgang,
            WiederholungAusgang.abgebrochen,
            'The approval was cancelled or timed out; kept as pending.',
          ),
        );
        continue;
      case Freigabeausgang.freigegeben:
        break;
    }

    try {
      final geschrieben = await schreibeAuftrag(await oeffnen(), a);
      if (!geschrieben.verifiziert) {
        ergebnisse.add(
          Wiederholung(
            vorgang,
            WiederholungAusgang.nichtGeprueft,
            'not verified: it does not read back with the written content; kept as pending.',
          ),
        );
        continue;
      }
      await ausstand.entferne(vorgang.id);
      ergebnisse.add(
        Wiederholung(
          vorgang,
          WiederholungAusgang.geschrieben,
          'written and verified (version: ${geschrieben.version}).',
        ),
      );
    } on KontextNichtErreichbar catch (f) {
      ergebnisse.add(
        Wiederholung(vorgang, WiederholungAusgang.nichtErreichbar, f.meldung),
      );
      break;
    } on KontextKonflikt catch (f) {
      ergebnisse.add(
        Wiederholung(
          vorgang,
          WiederholungAusgang.konflikt,
          '${f.meldung} Kept as pending; nothing was overwritten.',
        ),
      );
    } on KontextFehler catch (f) {
      ergebnisse.add(
        Wiederholung(vorgang, WiederholungAusgang.fehler, f.meldung),
      );
    }
  }
  return ergebnisse;
}
