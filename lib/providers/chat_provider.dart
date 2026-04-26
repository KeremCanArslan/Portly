import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:portly/services/api_service.dart';

/// Chat mesajı modeli
class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final bool isStreaming; // assistant streaming durumunda true

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
  });

  ChatMessage copyWith({String? content, bool? isStreaming}) {
    return ChatMessage(
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  int? _userId;
  final List<ChatMessage> _messages = [];
  bool _isLoadingHistory = false;
  bool _isStreaming = false;
  String? _error;
  String? _pendingPrompt;
  http.Client? _activeStream;

  // Getters
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isStreaming => _isStreaming;
  String? get error => _error;
  String? get pendingPrompt => _pendingPrompt;
  bool get hasMessages => _messages.isNotEmpty;
  int? get userId => _userId;

  /// AuthProvider'dan çağrılır
  void updateAuth(int? newUserId) {
    if (_userId == newUserId) return;
    _userId = newUserId;
    if (newUserId != null) {
      loadHistory();
    } else {
      _messages.clear();
      _error = null;
      notifyListeners();
    }
  }

  /// Sohbet geçmişini yükle
  Future<void> loadHistory() async {
    if (_userId == null) return;
    _isLoadingHistory = true;
    notifyListeners();

    try {
      final history = await _api.fetchChatHistory(_userId!);
      _messages.clear();
      for (final m in history) {
        _messages.add(ChatMessage.fromJson(m as Map<String, dynamic>));
      }
    } catch (e) {
      _error = 'Geçmiş yüklenemedi: $e';
    }
    _isLoadingHistory = false;
    notifyListeners();
  }

  /// Mesaj gönder ve streaming cevabı al
  /// Mesaj gönder ve streaming cevabı al
  Future<void> sendMessage(String text) async {
    if (_userId == null || text.trim().isEmpty || _isStreaming) return;

    _error = null;

    // Kullanıcı mesajını hemen ekle
    _messages.add(ChatMessage(
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
    ));

    // Asistan placeholder
    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    _messages.add(assistantMessage);
    final assistantIndex = _messages.length - 1;

    _isStreaming = true;
    notifyListeners();

    final completer = Completer<void>();

    // Token buffering: gelen token'ları biriktir, 50ms'de bir flush et
    String tokenBuffer = '';
    Timer? flushTimer;

    void flushBuffer() {
      if (tokenBuffer.isEmpty) return;
      if (assistantIndex < _messages.length) {
        _messages[assistantIndex] = _messages[assistantIndex].copyWith(
          content: _messages[assistantIndex].content + tokenBuffer,
        );
        notifyListeners();
      }
      tokenBuffer = '';
    }

    _activeStream = _api.streamChatMessage(
      userId: _userId!,
      message: text.trim(),
      onToken: (token) {
        tokenBuffer += token;
        // Periyodik flush — 60ms'de bir UI'a gönder
        flushTimer ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
          flushBuffer();
        });
      },
      onDone: () {
        flushTimer?.cancel();
        flushBuffer(); // Kalan buffer'ı boşalt
        if (assistantIndex < _messages.length) {
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            isStreaming: false,
          );
        }
        _isStreaming = false;
        _activeStream = null;
        notifyListeners();
        completer.complete();
      },
      onError: (err) {
        flushTimer?.cancel();
        flushBuffer();
        if (assistantIndex < _messages.length) {
          final current = _messages[assistantIndex].content;
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            content: current.isEmpty ? '⚠️ $err' : current,
            isStreaming: false,
          );
        }
        _error = err;
        _isStreaming = false;
        _activeStream = null;
        notifyListeners();
        completer.complete();
      },
    );

    await completer.future;
  }

  /// Aktif streaming'i iptal et
  void cancelStream() {
    _activeStream?.close();
    _activeStream = null;
    if (_messages.isNotEmpty && _messages.last.isStreaming) {
      _messages[_messages.length - 1] = _messages.last.copyWith(
        isStreaming: false,
      );
    }
    _isStreaming = false;
    notifyListeners();
  }

  /// Chat ekranı açılırken otomatik gönderilecek soruyu set et
  void setPendingPrompt(String? prompt) {
    _pendingPrompt = prompt;
  }

  String? consumePendingPrompt() {
    final p = _pendingPrompt;
    _pendingPrompt = null;
    return p;
  }

  Future<bool> clearHistory() async {
    if (_userId == null) return false;
    final success = await _api.clearChatHistory(_userId!);
    if (success) {
      _messages.clear();
      notifyListeners();
    }
    return success;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeStream?.close();
    super.dispose();
  }
}

/// Stream tamamlanmasını bekleyen yardımcı
class _StreamCompleter {
  bool _completed = false;
  final List<void Function()> _listeners = [];

  void complete() {
    if (_completed) return;
    _completed = true;
    for (final l in _listeners) {
      l();
    }
  }

  Future<void> get future {
    if (_completed) return Future.value();
    return Future(() async {
      while (!_completed) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
  }
}
