/// Ein Fehler, dessen Meldung die KI bekommt. Sie nennt die Ursache, nie einen
/// absoluten Pfad des Rechners (der Pfad der Wurzel bleibt im Plugin).
class KontextFehler implements Exception {
  const KontextFehler(this.meldung);

  final String meldung;

  @override
  String toString() => meldung;
}

/// Ein Schreibvorgang passt nicht mehr zum Stand, den die KI gelesen hat: Die
/// Datei hat sich geändert, fehlt, oder sie existiert beim Anlegen schon. Nichts
/// wurde geschrieben.
class KontextKonflikt extends KontextFehler {
  const KontextKonflikt(super.meldung);
}
