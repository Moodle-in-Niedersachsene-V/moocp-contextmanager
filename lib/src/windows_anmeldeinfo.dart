import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'fehler.dart';

/// Der Schlüsselbund unter Windows: die Anmeldeinformationsverwaltung
/// (Credential Manager) des Benutzers, über `CredReadW` und `CredWriteW` aus
/// `advapi32.dll` (ADR 0004). Das Passwort geht nur im Speicher dieses Prozesses
/// an das System; es steht in keiner Kommandozeile, keiner Datei und keiner
/// Meldung. Es gibt keinen Ersatz über eine Datei.

/// Der Typ `CRED_TYPE_GENERIC`.
const _typAllgemein = 1;

/// `CRED_PERSIST_LOCAL_MACHINE`: bleibt über Abmeldungen, wandert nicht mit
/// dem Profil auf andere Rechner.
const _bleibtAufDemRechner = 2;

/// Die größte Größe eines Eintrags (`CRED_MAX_CREDENTIAL_BLOB_SIZE`).
const _hoechstGroesse = 2560;

/// `CREDENTIALW` aus wincred.h (64 Bit; die Ausrichtung ergibt sich aus den
/// Feldern). Windows gibt es für dieses Plugin nur als x64.
final class _Eintrag extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int typ;
  external Pointer<Utf16> zielname;
  external Pointer<Utf16> kommentar;
  @Uint32()
  external int zuletztGeschriebenNiedrig;
  @Uint32()
  external int zuletztGeschriebenHoch;
  @Uint32()
  external int blobGroesse;
  external Pointer<Uint8> blob;
  @Uint32()
  external int bleiben;
  @Uint32()
  external int attributeAnzahl;
  external Pointer<Void> attribute;
  external Pointer<Utf16> zielalias;
  external Pointer<Utf16> benutzername;
}

typedef _LiesNative = Int32 Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Pointer<_Eintrag>>,
);
typedef _Lies = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Pointer<_Eintrag>>,
);
typedef _SchreibeNative = Int32 Function(Pointer<_Eintrag>, Uint32);
typedef _Schreibe = int Function(Pointer<_Eintrag>, int);
typedef _FreiNative = Void Function(Pointer<Void>);
typedef _Frei = void Function(Pointer<Void>);

class _Advapi {
  _Advapi() : _lib = DynamicLibrary.open('advapi32.dll') {
    lies = _lib.lookupFunction<_LiesNative, _Lies>('CredReadW');
    schreibe = _lib.lookupFunction<_SchreibeNative, _Schreibe>('CredWriteW');
    frei = _lib.lookupFunction<_FreiNative, _Frei>('CredFree');
  }

  final DynamicLibrary _lib;
  late final _Lies lies;
  late final _Schreibe schreibe;
  late final _Frei frei;
}

_Advapi? _advapi;

/// Der Name des Eintrags: Dienst und Konto, wie bei den anderen Systemen.
String _zielname(String dienst, String konto) => '$dienst:$konto';

/// Windows kennt dieses Passwort nicht, oder die Verwaltung ist nicht erreichbar.
Future<String> windowsGeheimnis(String dienst, String konto) async {
  final api = _advapi ??= _Advapi();
  final ziel = _zielname(dienst, konto).toNativeUtf16();
  final ausgabe = calloc<Pointer<_Eintrag>>();
  try {
    if (api.lies(ziel, _typAllgemein, 0, ausgabe) == 0) {
      throw const KontextFehler(
        'No password for the WebDAV location in the Windows credential store. '
        'Enter it in the settings window; nothing was written.',
      );
    }
    final eintrag = ausgabe.value;
    try {
      final bytes = eintrag.ref.blob.asTypedList(eintrag.ref.blobGroesse);
      // Als UTF-16 abgelegt, wie Windows es tut; Kopie, bevor der Eintrag frei wird.
      final text = String.fromCharCodes([
        for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
      ]);
      if (text.isEmpty) {
        throw const KontextFehler(
          'No password for the WebDAV location in the Windows credential store. '
          'Enter it in the settings window; nothing was written.',
        );
      }
      return text;
    } finally {
      api.frei(eintrag.cast());
    }
  } finally {
    calloc.free(ziel);
    calloc.free(ausgabe);
  }
}

/// Trägt das Passwort ein oder ersetzt es. Scheitert das, bleibt der alte
/// Eintrag, wie er war.
Future<void> windowsSpeichere(String dienst, String konto, String geheimnis) async {
  final api = _advapi ??= _Advapi();
  final bytes = _alsUtf16(geheimnis);
  if (bytes.length > _hoechstGroesse) {
    throw const KontextFehler(
      'The password is too long for the Windows credential store; nothing was stored.',
    );
  }
  final ziel = _zielname(dienst, konto).toNativeUtf16();
  final benutzer = konto.toNativeUtf16();
  final blob = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  final eintrag = calloc<_Eintrag>();
  try {
    blob.asTypedList(bytes.length).setAll(0, bytes);
    eintrag.ref
      ..typ = _typAllgemein
      ..zielname = ziel
      ..blobGroesse = bytes.length
      ..blob = blob
      ..bleiben = _bleibtAufDemRechner
      ..benutzername = benutzer;
    if (api.schreibe(eintrag, 0) == 0) {
      throw const KontextFehler(
        'The password could not be stored in the Windows credential store. '
        'Nothing was written.',
      );
    }
  } finally {
    // Das Passwort liegt im Speicher des Blobs; vor dem Freigeben überschreiben.
    blob.asTypedList(bytes.isEmpty ? 1 : bytes.length).fillRange(0, bytes.isEmpty ? 1 : bytes.length, 0);
    calloc.free(blob);
    calloc.free(eintrag);
    calloc.free(benutzer);
    calloc.free(ziel);
  }
}

/// Entfernt den Eintrag; nur für Tests, die ihren eigenen Dienstnamen aufräumen.
Future<void> windowsLoesche(String dienst, String konto) async {
  final lib = DynamicLibrary.open('advapi32.dll');
  final loesche = lib.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32, Uint32),
    int Function(Pointer<Utf16>, int, int)
  >('CredDeleteW');
  final ziel = _zielname(dienst, konto).toNativeUtf16();
  try {
    loesche(ziel, _typAllgemein, 0);
  } finally {
    calloc.free(ziel);
  }
}

/// UTF-16 (little endian) ohne abschließende Null.
List<int> _alsUtf16(String text) {
  final ergebnis = <int>[];
  for (final c in text.codeUnits) {
    ergebnis
      ..add(c & 0xff)
      ..add(c >> 8);
  }
  return ergebnis;
}
