// Widget-Tests des Einstellungsfensters (E8). Die Logik (Prüfung, Speichern,
// Schlüsselbund) liegt im Plugin und ist dort getestet; hier ersetzen Fakes sie,
// damit das Fenster allein geprüft wird: Eingabe, Anzeige, Meldungen und das
// verdeckte Passwort.
import 'package:contextmanager/src/einrichtung.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontext_einstellungen/src/einstellungs_seite.dart';

void main() {
  late List<Einrichtung> geprueft;
  late List<Einrichtung> gespeichert;
  late Verbindungsergebnis pruefErgebnis;
  late Speicherergebnis speicherErgebnis;
  String? gewaehlterOrdner;

  setUp(() {
    geprueft = [];
    gespeichert = [];
    pruefErgebnis = const Verbindungsergebnis(
      gelungen: true,
      meldung: 'Verbindung in Ordnung: Der Kontextbereich antwortet.',
    );
    speicherErgebnis = const Speicherergebnis(
      gespeichert: true,
      meldung: 'Gespeichert. Die nächste Anfrage an den Kontextbereich nutzt die neuen Einstellungen.',
    );
    gewaehlterOrdner = null;
  });

  Future<void> oeffnen(WidgetTester tester, {Einrichtung? anfangs}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: kontextTheme(),
        home: EinstellungsSeite(
          anfangs: anfangs,
          pruefen: (e) async {
            geprueft.add(e);
            return pruefErgebnis;
          },
          speichern: (e) async {
            gespeichert.add(e);
            return speicherErgebnis;
          },
          ordnerWaehlen: () async => gewaehlterOrdner,
        ),
      ),
    );
  }

  /// Tippt auf einen Knopf, nachdem er ins Bild gescrollt ist.
  Future<void> tippen(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> aufWebdavWechseln(WidgetTester tester) async {
    await tester.tap(find.text('WebDAV-Server'));
    await tester.pumpAndSettle();
  }

  testWidgets('zeigt den Ordner als Vorgabe, WebDAV-Felder erst nach dem Wechsel', (tester) async {
    await oeffnen(tester);

    expect(find.byKey(const Key('pfad-feld')), findsOneWidget);
    expect(find.byKey(const Key('adresse-feld')), findsNothing);

    await aufWebdavWechseln(tester);

    expect(find.byKey(const Key('pfad-feld')), findsNothing);
    expect(find.byKey(const Key('adresse-feld')), findsOneWidget);
    expect(find.byKey(const Key('benutzer-feld')), findsOneWidget);
    expect(find.byKey(const Key('passwort-feld')), findsOneWidget);
  });

  testWidgets('das Passwort ist verdeckt und die Tastatur schlägt nichts vor', (tester) async {
    await oeffnen(tester);
    await aufWebdavWechseln(tester);

    final feld = tester.widget<TextField>(find.byKey(const Key('passwort-feld')));

    expect(feld.obscureText, isTrue);
    expect(feld.enableSuggestions, isFalse);
    expect(feld.autocorrect, isFalse);
  });

  testWidgets('„Verbindung prüfen“ gibt die Eingabe samt Passwort an die Prüfung und zeigt das Ergebnis', (tester) async {
    await oeffnen(tester);
    await aufWebdavWechseln(tester);
    await tester.enterText(find.byKey(const Key('adresse-feld')), 'https://cloud.example.org/dav/kontext/');
    await tester.enterText(find.byKey(const Key('benutzer-feld')), 'name');
    await tester.enterText(find.byKey(const Key('passwort-feld')), 'geheim');

    await tippen(tester, find.text('Verbindung prüfen'));

    expect(geprueft, hasLength(1));
    expect(geprueft.single.art, 'webdav');
    expect(geprueft.single.adresse, 'https://cloud.example.org/dav/kontext/');
    expect(geprueft.single.benutzer, 'name');
    expect(geprueft.single.passwort, 'geheim');
    expect(find.text('Verbindung in Ordnung: Der Kontextbereich antwortet.'), findsOneWidget);
  });

  testWidgets('eine fehlgeschlagene Prüfung zeigt die deutsche Ursache', (tester) async {
    pruefErgebnis = const Verbindungsergebnis(
      gelungen: false,
      meldung: 'Der Server lehnt Benutzer oder Passwort ab. Bitte beides prüfen.',
    );
    await oeffnen(tester);
    await aufWebdavWechseln(tester);

    await tippen(tester, find.text('Verbindung prüfen'));

    expect(
      find.text('Der Server lehnt Benutzer oder Passwort ab. Bitte beides prüfen.'),
      findsOneWidget,
    );
  });

  testWidgets('„Speichern“ mit einem ungültigen Feld zeigt die Meldung am Feld', (tester) async {
    speicherErgebnis = const Speicherergebnis(
      gespeichert: false,
      feld: 'adresse',
      meldung: 'Die Adresse muss mit https:// beginnen. Nur 127.0.0.1 und localhost dürfen http:// verwenden.',
    );
    await oeffnen(tester);
    await aufWebdavWechseln(tester);
    await tester.enterText(find.byKey(const Key('adresse-feld')), 'http://cloud.example.org/');

    await tippen(tester, find.text('Speichern'));

    final feld = tester.widget<TextField>(find.byKey(const Key('adresse-feld')));
    expect(feld.decoration?.errorText, speicherErgebnis.meldung);
  });

  testWidgets('„Speichern“ gibt die Eingabe weiter und bestätigt', (tester) async {
    await oeffnen(tester);
    await aufWebdavWechseln(tester);
    await tester.enterText(find.byKey(const Key('adresse-feld')), 'https://cloud.example.org/dav/');
    await tester.enterText(find.byKey(const Key('benutzer-feld')), 'name');

    await tippen(tester, find.text('Speichern'));

    expect(gespeichert, hasLength(1));
    expect(gespeichert.single.passwort, anyOf(isNull, isEmpty),
        reason: 'ein leeres Passwort lässt das bisherige im Schlüsselbund');
    expect(find.textContaining('Gespeichert.'), findsOneWidget);
  });

  testWidgets('„Ordner wählen“ übernimmt den gewählten Pfad', (tester) async {
    gewaehlterOrdner = '/abs/kontext';
    await oeffnen(tester);

    await tippen(tester, find.text('Ordner wählen'));

    expect(find.text('/abs/kontext'), findsOneWidget);
  });

  testWidgets('ein Ordner aus den Einstellungen steht schon im Feld', (tester) async {
    await oeffnen(tester, anfangs: const Einrichtung(art: 'lokal', pfad: '/abs/kontext'));

    expect(find.text('/abs/kontext'), findsOneWidget);
  });
}
