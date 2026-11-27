import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Dispara la descarga de un archivo en el navegador (Flutter web).
///
/// Crea un `Blob` con los bytes, genera un object URL y simula el click de
/// un ancla con el atributo `download` — el equivalente nativo de una
/// descarga web. No depende de `dart:html`: usa `package:web` + interop.
void downloadFile({
  required String filename,
  required List<int> bytes,
  required String mime,
}) {
  final blob = web.Blob(
    <web.BlobPart>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
