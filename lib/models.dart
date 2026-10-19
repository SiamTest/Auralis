import 'package:path/path.dart' as p;

const audioExtensions = [
  'mp3',
  'flac',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wav',
  'wma',
];

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    this.fileId,
    this.coverFileId,
    this.size = 0,
    this.duration = Duration.zero,
    this.mime = 'application/octet-stream',
  });
  final String id, title, artist, source, mime;
  final int? fileId, coverFileId;
  final int size;
  final Duration duration;

  static Track? fromMessage(Map<String, dynamic> message, String chatTitle) {
    final content = message['content'] as Map<String, dynamic>?;
    if (content == null) return null;
    final isAudio = content['@type'] == 'messageAudio';
    if (!isAudio && content['@type'] != 'messageDocument') return null;
    final data =
        content[isAudio ? 'audio' : 'document'] as Map<String, dynamic>;
    final name = data['file_name'] as String? ?? '';
    if (!isAudio &&
        !audioExtensions.contains(
          p.extension(name).replaceFirst('.', '').toLowerCase(),
        )) {
      return null;
    }
    final file = data[isAudio ? 'audio' : 'document'] as Map<String, dynamic>;
    final covers =
        <Map<String, dynamic>>[
          if (isAudio && data['album_cover_thumbnail'] is Map<String, dynamic>)
            data['album_cover_thumbnail'],
          if (isAudio)
            ...(data['external_album_covers'] as List? ?? [])
                .whereType<Map<String, dynamic>>(),
          if (!isAudio && data['thumbnail'] is Map<String, dynamic>)
            data['thumbnail'],
        ]..sort(
          (a, b) => ((b['width'] as int? ?? 0) * (b['height'] as int? ?? 0))
              .compareTo(
                (a['width'] as int? ?? 0) * (a['height'] as int? ?? 0),
              ),
        );
    return Track(
      id: '${message['chat_id']}:${message['id']}',
      title: (data['title'] as String? ?? '').isNotEmpty
          ? data['title']
          : p.basenameWithoutExtension(name),
      artist: (data['performer'] as String? ?? '').isNotEmpty
          ? data['performer']
          : chatTitle,
      source: chatTitle,
      fileId: file['id'] as int,
      coverFileId: covers.isEmpty ? null : covers.first['file']?['id'] as int?,
      size: file['size'] as int? ?? 0,
      duration: Duration(seconds: data['duration'] as int? ?? 0),
      mime: data['mime_type'] as String? ?? 'application/octet-stream',
    );
  }
}

class MusicChat {
  const MusicChat(this.id, this.title, {this.photoFileId});
  final int id;
  final String title;
  final int? photoFileId;

  static MusicChat? fromChat(Map<String, dynamic> chat) {
    final type = chat['type'] as Map<String, dynamic>?;
    return type?['@type'] == 'chatTypeSupergroup' && type?['is_channel'] == true
        ? MusicChat(
            chat['id'] as int,
            chat['title'] as String,
            photoFileId: chat['photo']?['small']?['id'] as int?,
          )
        : null;
  }
}

String clockText(Duration value) {
  final seconds = value.inSeconds.clamp(0, 359999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
