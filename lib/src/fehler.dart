/// Ein Fehler, dessen Meldung die KI bekommt. Sie nennt die Ursache, nie einen
/// absoluten Pfad des Rechners (der Pfad der Wurzel bleibt im Plugin).
class KontextFehler implements Exception {
  const KontextFehler(this.meldung);

  final String meldung;

  @override
  String toString() => meldung;
}
