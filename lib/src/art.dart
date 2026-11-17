/// Die Art einer Änderung im Kontextbereich, wie die KI sie angibt (E20). Sie
/// bestimmt, ab welcher Freigabestufe moocp die Lehrkraft fragt.
enum Art {
  journal('journal', 'Journaleintrag', Freigabestufe.alle),
  correction('correction', 'Nacharbeit', Freigabestufe.alle),
  planChange('plan_change', 'Planänderung', Freigabestufe.mittel),
  planAddition('plan_addition', 'Planergänzung', Freigabestufe.mittel),
  newFile('new_file', 'neue Datei', Freigabestufe.alle),
  rootFile('root_file', 'Datei im Wurzelordner', Freigabestufe.mittel);

  const Art(this.wert, this.bezeichnung, this.stufe);

  /// Der Wert, den die KI im Werkzeug angibt.
  final String wert;

  /// Die Bezeichnung im Dialog der Lehrkraft.
  final String bezeichnung;

  /// Die niedrigste Freigabestufe, auf der diese Art gefragt wird.
  final Freigabestufe stufe;

  /// Die Art zu einem Wert; null, wenn es keine gibt.
  static Art? aus(String wert) {
    for (final a in values) {
      if (a.wert == wert) return a;
    }
    return null;
  }
}

/// Die Stufe, ab der eine Freigabe gefragt wird, in der Reihenfolge von E20.
/// Die Lehrkraft stellt ihre Stufe ein; eine Frage wird gestellt, wenn ihre
/// Stufe mindestens so hoch ist wie die der Frage. „keine“ fragt auf jeder Stufe.
enum Freigabestufe { keine, mittel, alle }

/// Die Freigabestufe, ab der ein Schreibvorgang gefragt wird. Eine Datei direkt
/// am Wurzelordner wird schon auf Stufe mittel gefragt, auch wenn ihre Art es
/// nicht verlangt: Im Zweifel wird gefragt.
Freigabestufe freigabestufeFuer(Art art, {required bool imWurzelordner}) {
  if (!imWurzelordner) return art.stufe;
  return Freigabestufe.values[art.stufe.index < Freigabestufe.mittel.index
      ? art.stufe.index
      : Freigabestufe.mittel.index];
}
