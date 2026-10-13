import 'package:flutter/foundation.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/note.dart';

/// Yatırımcı günlüğü (not alma) durum yönetimi. ChatProvider/PortfolioProvider
/// ile aynı desen: AuthProvider'dan `userId` alır (ChangeNotifierProxyProvider),
/// giriş olunca notları yükler, çıkışta temizler. Token'ı `ApiService` statik
/// olarak taşıdığından burada token yönetilmez.
///
/// Notlar tek listede tutulur (genel + hisse-bazlı birlikte); hisse detay
/// ekranı [notesFor] ile süzer, "Yatırımcı Günlüğü" ekranı tümünü gösterir.
/// Liste her zaman en-yeni-önce (backend sıralar; ekleme listenin başına gider).
class NotesProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  int? _userId;
  List<Note> _notes = [];
  bool _isLoading = false;
  String? _error;

  List<Note> get notes => List.unmodifiable(_notes);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasNotes => _notes.isNotEmpty;

  /// Belirli bir sembole ait notlar (hisse detay ekranı). Genel notları
  /// (symbol null) hariç tutar; liste zaten en-yeni-önce.
  List<Note> notesFor(String symbol) =>
      _notes.where((n) => n.symbol == symbol).toList();

  void updateAuth(int? newUserId) {
    if (_userId == newUserId) return;
    _userId = newUserId;
    if (newUserId != null) {
      loadNotes();
    } else {
      _notes = [];
      _error = null;
      notifyListeners();
    }
  }

  Future<void> loadNotes() async {
    if (_userId == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      final raw = await _api.getNotes();
      if (raw != null) {
        _notes =
            raw.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
        _error = null;
      } else {
        _error = 'Notlar yüklenemedi';
      }
    } catch (e) {
      _error = 'Notlar yüklenemedi: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Not ekler (symbol null/boş = genel günlük). Başarı → true ve liste
  /// başına eklenir (en-yeni-önce); hata → false (UI bozulmaz).
  Future<bool> addNote(String content, {String? symbol}) async {
    if (_userId == null) return false;
    final created = await _api.createNote(content, symbol: symbol);
    if (created != null) {
      _notes.insert(0, Note.fromJson(created));
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Notu günceller (yerinde değiştirir). Başarı → true.
  Future<bool> editNote(int id, String content) async {
    final updated = await _api.updateNote(id, content);
    if (updated != null) {
      final idx = _notes.indexWhere((n) => n.id == id);
      if (idx != -1) {
        _notes[idx] = Note.fromJson(updated);
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  /// Notu siler. Başarı → true ve listeden düşer.
  Future<bool> removeNote(int id) async {
    final ok = await _api.deleteNote(id);
    if (ok) {
      _notes.removeWhere((n) => n.id == id);
      notifyListeners();
    }
    return ok;
  }
}
