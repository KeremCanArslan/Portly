import 'package:flutter_test/flutter_test.dart';
import 'package:portly/models/note.dart';

// Saf serileştirme testi (ağ/provider yok → FakeAsync/timeout riski yok).
// Backend NoteResponse sözleşmesini Note.fromJson tarafında kilitler.
void main() {
  group('Note.fromJson', () {
    test('tam JSON → tüm alanlar tipli', () {
      final n = Note.fromJson({
        'id': 7,
        'symbol': 'THYAO',
        'content': 'uzun vade tut',
        'created_at': '2026-06-16T10:00:00',
        'updated_at': '2026-06-16T11:30:00',
      });
      expect(n.id, 7);
      expect(n.symbol, 'THYAO');
      expect(n.content, 'uzun vade tut');
      expect(n.createdAt, isNotNull);
      expect(n.updatedAt, isNotNull);
      expect(n.isGeneral, isFalse);
    });

    test('symbol null = genel günlük, tarihler null tolere edilir', () {
      final n = Note.fromJson({
        'id': 1,
        'symbol': null,
        'content': 'genel not',
        'created_at': null,
        'updated_at': null,
      });
      expect(n.symbol, isNull);
      expect(n.isGeneral, isTrue);
      expect(n.createdAt, isNull);
      expect(n.updatedAt, isNull);
    });

    test('id int olmayan (num) gelse de int alınır', () {
      final n = Note.fromJson({
        'id': 42.0,
        'symbol': '',
        'content': 'x',
        'created_at': '2026-06-16T10:00:00',
        'updated_at': '2026-06-16T10:00:00',
      });
      expect(n.id, 42);
      expect(n.isGeneral, isTrue); // boş symbol = genel
    });
  });
}
