import 'dart:js_interop';

import 'package:web/web.dart';

void downloadAdminJson({required String fileName, required String contents}) {
  final blob = Blob(
    <BlobPart>[contents.toJS].toJS,
    BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..download = fileName
    ..href = url;
  document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}
