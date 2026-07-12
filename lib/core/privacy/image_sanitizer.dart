import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Decodes and re-encodes user images so EXIF/GPS metadata never leaves device.
class ImageSanitizer {
  ImageSanitizer._();

  static Future<File> toJpeg(
    String sourcePath, {
    required String prefix,
    int maxWidth = 1600,
    int quality = 85,
  }) async {
    final source = File(sourcePath);
    if (await source.length() > 20 * 1024 * 1024) {
      throw const FormatException('Image is too large');
    }
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image');
    }
    if (decoded.width * decoded.height > 40 * 1000 * 1000) {
      throw const FormatException('Image dimensions are too large');
    }

    var clean = img.bakeOrientation(decoded);
    if (clean.width > maxWidth) {
      clean = img.copyResize(clean, width: maxWidth);
    }

    final dir = await getApplicationSupportDirectory();
    final output = File(
      p.join(
          dir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg'),
    );
    await output.writeAsBytes(img.encodeJpg(clean, quality: quality),
        flush: true);
    return output;
  }
}
