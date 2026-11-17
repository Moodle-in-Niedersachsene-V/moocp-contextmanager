import 'package:contextmanager/src/einrichtung.dart';
import 'package:flutter/material.dart';

/// Das Thema wie in moocp: Material 3 mit moocps Grundfarbe (E8).
ThemeData kontextTheme() => ThemeData(
  colorSchemeSeed: const Color(0xFF0851A0),
  useMaterial3: true,
);

/// Das Einstellungsfenster: wo der Kontextbereich liegt, ein Ordner auf dem
/// Rechner oder ein WebDAV-Server mit Benutzer und verdecktem Passwort.
/// Prüfen, Speichern und Ordnerwahl sind von außen eingesetzt, damit das Fenster
/// allein geprüft werden kann (siehe `main.dart` für die echten Teile).
class EinstellungsSeite extends StatefulWidget {
  const EinstellungsSeite({
    super.key,
    required this.pruefen,
    required this.speichern,
    required this.ordnerWaehlen,
    this.anfangs,
  });

  /// Die Verbindung zur Eingabe prüfen (ohne zu schreiben).
  final Future<Verbindungsergebnis> Function(Einrichtung eingabe) pruefen;

  /// Speichern, wie es die Einrichtung vorsieht.
  final Future<Speicherergebnis> Function(Einrichtung eingabe) speichern;

  /// Ein Ordner im Dateidialog; null, wenn die Lehrkraft abbricht.
  final Future<String?> Function() ordnerWaehlen;

  /// Die bisherigen Einstellungen, falls es sie schon gibt (ohne Passwort).
  final Einrichtung? anfangs;

  @override
  State<EinstellungsSeite> createState() => _EinstellungsSeiteZustand();
}

class _EinstellungsSeiteZustand extends State<EinstellungsSeite> {
  late String _art;
  late String _pfad;
  late final TextEditingController _adresse;
  late final TextEditingController _benutzer;
  // Das Passwort kommt nie aus den Einstellungen: Es bleibt leer, bis die
  // Lehrkraft eines eintippt (A6).
  final TextEditingController _passwort = TextEditingController();

  /// Ein Feld mit einer Meldung; die Meldung steht dann unter dem Feld.
  String? _feld;
  String? _feldMeldung;

  /// Die Zeile unter den Knöpfen: Ergebnis der Prüfung oder des Speicherns.
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    final anfangs = widget.anfangs;
    _art = anfangs?.art ?? 'lokal';
    _pfad = anfangs?.pfad ?? '';
    _adresse = TextEditingController(text: anfangs?.adresse ?? '');
    _benutzer = TextEditingController(text: anfangs?.benutzer ?? '');
  }

  @override
  void dispose() {
    _adresse.dispose();
    _benutzer.dispose();
    _passwort.dispose();
    super.dispose();
  }

  Einrichtung _eingabe() => Einrichtung(
    art: _art,
    pfad: _pfad,
    adresse: _adresse.text,
    benutzer: _benutzer.text,
    passwort: _passwort.text.isEmpty ? null : _passwort.text,
  );

  Future<void> _pruefen() async {
    final ergebnis = await widget.pruefen(_eingabe());
    if (!mounted) return;
    setState(() {
      _feld = null;
      _feldMeldung = null;
      _status = ergebnis.meldung;
      _statusOk = ergebnis.gelungen;
    });
  }

  Future<void> _speichern() async {
    final ergebnis = await widget.speichern(_eingabe());
    if (!mounted) return;
    setState(() {
      if (ergebnis.gespeichert) {
        _feld = null;
        _feldMeldung = null;
        _status = ergebnis.meldung;
        _statusOk = true;
      } else if (ergebnis.feld != null) {
        _feld = ergebnis.feld;
        _feldMeldung = ergebnis.meldung;
        _status = null;
        _statusOk = false;
      } else {
        _feld = null;
        _feldMeldung = null;
        _status = ergebnis.meldung;
        _statusOk = false;
      }
    });
  }

  Future<void> _ordnerWaehlen() async {
    final gewaehlt = await widget.ordnerWaehlen();
    if (gewaehlt == null || !mounted) return;
    setState(() {
      _pfad = gewaehlt;
      if (_feld == 'pfad') {
        _feld = null;
        _feldMeldung = null;
      }
    });
  }

  String? _fehlerFuer(String feld) => _feld == feld ? _feldMeldung : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kontextbereich einrichten')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Wo liegt der Kontextbereich?',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Der Kontextbereich ist ein Ordner mit Konventionen, Stand und '
                  'Fachsprache. Er liegt auf diesem Rechner oder auf einem WebDAV-Server. '
                  'Das Passwort geht nie an die KI.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'lokal',
                      label: Text('Ordner auf diesem Rechner'),
                      icon: Icon(Icons.folder_outlined),
                    ),
                    ButtonSegment(
                      value: 'webdav',
                      label: Text('WebDAV-Server'),
                      icon: Icon(Icons.cloud_outlined),
                    ),
                  ],
                  selected: {_art},
                  onSelectionChanged: (auswahl) => setState(() {
                    _art = auswahl.first;
                    _feld = null;
                    _feldMeldung = null;
                  }),
                ),
                const SizedBox(height: 24),
                if (_art == 'lokal') _ordnerFeld(theme) else ..._webdavFelder(),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _pruefen,
                      child: const Text('Verbindung prüfen'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _speichern,
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _status!,
                    key: const Key('status'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _statusOk
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ordnerFeld(ThemeData theme) {
    final fehler = _fehlerFuer('pfad');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ordner', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _pfad.isEmpty ? 'Kein Ordner gewählt' : _pfad,
                key: const Key('pfad-feld'),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: _ordnerWaehlen,
              child: const Text('Ordner wählen'),
            ),
          ],
        ),
        if (fehler != null) ...[
          const SizedBox(height: 8),
          Text(
            fehler,
            key: const Key('pfad-fehler'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  List<Widget> _webdavFelder() => [
    TextField(
      key: const Key('adresse-feld'),
      controller: _adresse,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: 'Adresse',
        hintText: 'https://server.example.org/dav/kontext/',
        errorText: _fehlerFuer('adresse'),
      ),
    ),
    const SizedBox(height: 16),
    TextField(
      key: const Key('benutzer-feld'),
      controller: _benutzer,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'Benutzer',
        errorText: _fehlerFuer('benutzer'),
      ),
    ),
    const SizedBox(height: 16),
    TextField(
      key: const Key('passwort-feld'),
      controller: _passwort,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Passwort',
        helperText: 'Leer lassen, wenn das gespeicherte Passwort bleibt.',
      ),
    ),
  ];
}
