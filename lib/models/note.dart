/// Yatırımcı günlüğü notu — bir hisseye bağlı (`symbol`) ya da serbest
/// (`symbol == null` → genel günlük) olabilir. Backend `NoteResponse` ile
/// birebir: `{id, symbol?, content, created_at?, updated_at?}`. Liste backend'de
/// en-yeni-önce sıralı gelir; tarih alanları sunucu ISO-8601 string'idir.
class Note {
  final int id;
  final String? symbol;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Note({
    required this.id,
    required this.symbol,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isGeneral => symbol == null || symbol!.isEmpty;

  factory Note.fromJson(Map<String, dynamic> j) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return Note(
      id: (j['id'] as num).toInt(),
      symbol: j['symbol'] as String?,
      content: j['content'] as String? ?? '',
      createdAt: dt(j['created_at']),
      updatedAt: dt(j['updated_at']),
    );
  }
}
