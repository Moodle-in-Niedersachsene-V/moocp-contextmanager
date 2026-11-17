// Das Einstellungsfenster des Plugins „context“ (E8). Das Plugin startet es mit
// `--einstellungen <Datei>`, wenn die Einstellungen fehlen, wenn der Ort nicht
// antwortet oder auf Wunsch der KI. Das Fenster liest die Datei nur, um die
// Felder vorzubelegen; geschrieben wird über die Einrichtung des Plugins.
import 'dart:io';

import 'package:contextmanager/src/einrichtung.dart';
import 'package:contextmanager/src/einstellungen.dart';
import 'package:contextmanager/src/fehler.dart';
import 'package:contextmanager/src/schluesselbund.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'src/einstellungs_seite.dart';

Future<void> main(List<String> argumente) async {
  WidgetsFlutterBinding.ensureInitialized();
  final datei = File(
    _wert(argumente, '--einstellungen') ?? standardEinstellungenPfad(),
  );
  final anfangs = await _lieseAnfangs(datei);

  runApp(EinstellungsApp(datei: datei, anfangs: anfangs));
}

class EinstellungsApp extends StatelessWidget {
  const EinstellungsApp({super.key, required this.datei, this.anfangs});

  final File datei;
  final Einrichtung? anfangs;

  @override
  Widget build(BuildContext context) {
    final schluesselbund = SystemSchluesselbund();
    // Das Fenster gibt es erst nach dem ersten Bild; dann richtet es sich ein.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fensterEinrichten());
    return MaterialApp(
      title: 'Kontextbereich einrichten',
      debugShowCheckedModeBanner: false,
      theme: kontextTheme(),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: EinstellungsSeite(
        anfangs: anfangs,
        pruefen: (eingabe) =>
            pruefeVerbindung(eingabe, schluesselbund: schluesselbund),
        speichern: (eingabe) => speichereEinrichtung(
          eingabe,
          datei: datei,
          schluesselbund: schluesselbund,
        ),
        ordnerWaehlen: () => getDirectoryPath(
          confirmButtonText: 'Ordner wählen',
        ),
      ),
    );
  }
}

/// Titel, Größe und Lage des Fensters, wie moocp sie setzt (window_manager über
/// nativeapi). Scheitert der Zugriff, bleibt das Fenster, wie das System es
/// öffnet; die Einstellungen funktionieren trotzdem.
void _fensterEinrichten() {
  try {
    final fenster = WindowManager.instance.getCurrent();
    if (fenster == null) return;
    fenster.title = 'Kontextbereich einrichten';
    fenster.minimumSize = const Size(480, 560).toNative();
    fenster.setSize(const Size(560, 680).toNative(), false);
    fenster.center();
    fenster.show();
    fenster.focus();
  } catch (_) {
    // siehe oben: ohne Fenster-Anpassung geht es weiter
  }
}

/// Die bisherigen Einstellungen, ohne Passwort. Fehlt die Datei oder ist sie
/// nicht lesbar, beginnt das Fenster leer.
Future<Einrichtung?> _lieseAnfangs(File datei) async {
  try {
    final e = await leseEinstellungen(datei);
    return e.art == 'webdav'
        ? Einrichtung(
            art: 'webdav',
            adresse: e.adresse.toString(),
            benutzer: e.benutzer ?? '',
          )
        : Einrichtung(art: 'lokal', pfad: e.pfad ?? '');
  } on KontextFehler {
    return null;
  }
}

String? _wert(List<String> argumente, String name) {
  final i = argumente.indexOf(name);
  if (i < 0 || i + 1 >= argumente.length) return null;
  return argumente[i + 1];
}
