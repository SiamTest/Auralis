import 'dart:isolate';
import 'dart:typed_data';

typedef CoverRange = Future<Uint8List?> Function(int offset, int count);
const maxCoverBytes = 4 * 1024 * 1024;

/// Read metadata ranges, never the audio payload, and parse away from the UI.
/// shortcut: ID3/FLAC/MP4 only, add other containers when needed.
Future<Uint8List?> readEmbeddedCover(CoverRange source, int size) async {
  var budget = maxCoverBytes;
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count <= 0 || offset + count > size || count > budget) {
      throw const FormatException('Artwork range exceeds limits');
    }
    budget -= count;
    final bytes = await source(offset, count);
    if (bytes == null || bytes.length != count) {
      throw const FormatException('Artwork not buffered');
    }
    return bytes;
  }

  try {
    if (size < 10) return null;
    final head = await read(0, 10);
    if (_text(head, 0, 3) == 'ID3') {
      final version = head[3];
      if (version < 2 || version > 4 || (version == 2 && head[5] & 64 != 0)) {
        return null;
      }
      final length = _number(head, 6, 4, sync: true);
      final body = await read(10, length);
      return await _parse((0, body, version, head[5]));
    }
    if (_text(head, 0, 4) == 'fLaC') {
      var offset = 4;
      Uint8List? fallback;
      for (var blocks = 0; blocks < 128; blocks++) {
        final header = await read(offset, 4);
        final length = _number(header, 1, 3);
        offset += 4;
        if (header[0] & 127 == 6) {
          final data = await read(offset, length);
          final picture = await _parse((1, data, 0, 0));
          if (picture != null) {
            if (_number(data, 0, 4) == 3) return picture;
            fallback ??= picture;
          }
        }
        offset += length;
        if (header[0] & 128 != 0) return fallback;
      }
      return fallback;
    }
    // Skip mdat by its declared size, so a tail moov needs no full-file download.
    var offset = 0;
    for (var boxes = 0; boxes < 128 && offset + 8 <= size; boxes++) {
      final header = await read(offset, 8);
      var length = _number(header, 0, 4);
      var headerSize = 8;
      if (length == 1) {
        length = _number(await read(offset + 8, 8), 0, 8);
        headerSize = 16;
      } else if (length == 0) {
        length = size - offset;
      }
      if (length < headerSize || offset + length > size) return null;
      if (_text(header, 4, 4) == 'moov') {
        final body = await read(offset + headerSize, length - headerSize);
        return await _parse((2, body, 0, 0));
      }
      if (offset == 0 && _text(header, 4, 4) != 'ftyp') return null;
      offset += length;
    }
  } catch (_) {
    // Absent, incomplete, oversized and malformed metadata use the placeholder.
  }
  return null;
}

// Keep the worker closure separate from the TDLib/source callback context.
Future<Uint8List?> _parse((int, Uint8List, int, int) job) => Isolate.run(
  () => switch (job.$1) {
    0 => _id3(job.$2, job.$3, job.$4),
    1 => _flacPicture(job.$2),
    _ => _mp4(job.$2, 0, job.$2.length, 0),
  },
);

int _number(Uint8List data, int offset, int count, {bool sync = false}) {
  if (offset < 0 || offset + count > data.length) {
    throw const FormatException('Truncated field');
  }
  var value = 0;
  for (var i = offset; i < offset + count; i++) {
    if (sync && data[i] >= 128) {
      throw const FormatException('Invalid syncsafe field');
    }
    value = (value << (sync ? 7 : 8)) | data[i];
  }
  return value;
}

String _text(Uint8List data, int offset, int count) =>
    String.fromCharCodes(data.sublist(offset, offset + count));

Uint8List _unsync(Uint8List bytes) => Uint8List.fromList([
  for (var i = 0; i < bytes.length; i++)
    if (!(i > 0 && bytes[i] == 0 && bytes[i - 1] == 255)) bytes[i],
]);

bool isCoverImage(Uint8List data) =>
    (data.length >= 8 && _text(data, 0, 8) == '\x89PNG\r\n\x1a\n') ||
    (data.length >= 3 && data[0] == 255 && data[1] == 216 && data[2] == 255) ||
    (data.length >= 12 &&
        _text(data, 0, 4) == 'RIFF' &&
        _text(data, 8, 4) == 'WEBP') ||
    (data.length >= 6 &&
        (_text(data, 0, 6) == 'GIF87a' || _text(data, 0, 6) == 'GIF89a'));

Uint8List? _picture(Uint8List bytes) => isCoverImage(bytes) ? bytes : null;

Uint8List? _id3(Uint8List input, int version, int flags) {
  final body = version < 4 && flags & 128 != 0 ? _unsync(input) : input;
  var offset = 0;
  if (version >= 3 && flags & 64 != 0) {
    offset = _number(body, 0, 4, sync: version == 4) + (version == 3 ? 4 : 0);
    if (offset < 4) return null;
  }
  Uint8List? fallback;
  final headerSize = version == 2 ? 6 : 10;
  for (
    var frames = 0;
    frames < 4096 && offset + headerSize <= body.length;
    frames++
  ) {
    final id = _text(body, offset, version == 2 ? 3 : 4);
    if (body[offset] == 0) break;
    final length = _number(
      body,
      offset + (version == 2 ? 3 : 4),
      version == 2 ? 3 : 4,
      sync: version == 4,
    );
    final format = version == 2 ? 0 : body[offset + 9];
    offset += headerSize;
    if (length <= 0 || offset + length > body.length) break;
    if ((id == 'APIC' || id == 'PIC') &&
        format & (version == 4 ? 12 : 192) == 0) {
      var frame = Uint8List.sublistView(body, offset, offset + length);
      if (version == 4 && (format & 2 != 0 || flags & 128 != 0)) {
        frame = _unsync(frame);
      }
      var p =
          (format & (version == 4 ? 64 : 32) != 0 ? 1 : 0) +
          (version == 4 && format & 1 != 0 ? 4 : 0);
      if (p >= frame.length) return fallback;
      final encoding = frame[p++];
      if (id == 'PIC') {
        p += 3;
      } else {
        while (p < frame.length && frame[p] != 0) {
          p++;
        }
        p++;
      }
      if (p >= frame.length) return fallback;
      final type = frame[p++];
      final step = encoding == 1 || encoding == 2 ? 2 : 1;
      while (p + step <= frame.length) {
        final end = frame[p] == 0 && (step == 1 || frame[p + 1] == 0);
        p += step;
        if (end) {
          final picture = _picture(Uint8List.sublistView(frame, p));
          if (picture != null && type == 3) return picture;
          fallback ??= picture;
          break;
        }
      }
    }
    offset += length;
  }
  return fallback;
}

Uint8List? _flacPicture(Uint8List data) {
  var p = 8 + _number(data, 4, 4);
  p += 4 + _number(data, p, 4) + 16;
  final length = _number(data, p, 4);
  p += 4;
  if (length <= 0 || p + length > data.length) return null;
  return _picture(Uint8List.sublistView(data, p, p + length));
}

Uint8List? _mp4(Uint8List data, int offset, int end, int depth) {
  if (depth > 8) return null;
  while (offset + 8 <= end) {
    var length = _number(data, offset, 4);
    final type = _text(data, offset + 4, 4);
    var header = 8;
    if (length == 1) {
      length = _number(data, offset + 8, 8);
      header = 16;
    }
    if (length == 0) length = end - offset;
    if (length < header || offset + length > end) return null;
    var start = offset + header;
    if (type == 'covr') {
      if (start + 16 <= offset + length &&
          _text(data, start + 4, 4) == 'data') {
        final count = _number(data, start, 4);
        if (count >= 16 && start + count <= offset + length) {
          return _picture(
            Uint8List.sublistView(data, start + 16, start + count),
          );
        }
      }
    } else if (['moov', 'udta', 'meta', 'ilst'].contains(type)) {
      if (type == 'meta' && _number(data, start, 4) == 0) start += 4;
      final picture = _mp4(data, start, offset + length, depth + 1);
      if (picture != null) return picture;
    }
    offset += length;
  }
  return null;
}
