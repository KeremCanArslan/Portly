import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:portly/services/api_service.dart';

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final bool isStreaming;

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
  ChatStreamHandle? _activeStream;

  /// Akış sırasında gelen token'ları 60 ms'de bir arayüze basan zamanlayıcı.
  /// SINIF seviyesinde tutulur: yerel değişken olduğunda `cancelStream()` ve
  /// `dispose()` ona ULAŞAMIYORDU — kullanıcı ekranı kapattığında ya da akışı
  /// iptal ettiğinde `onDone`/`onError` hiç tetiklenmediği için zamanlayıcı
  /// süresiz çalışmaya devam edip atılmış provider üzerinde `notifyListeners`
  /// çağırıyordu.
  Timer? _flushTimer;

  /// `sendMessage` akışın bitmesini bununla bekler. Aynı sebeple sınıf
  /// seviyesinde: iptal/dispose yolunda tamamlanmazsa `await` sonsuza kadar
  /// asılı kalır (çağıran ve kapanış closure'ı bellekte tutulur).
  Completer<void>? _streamCompleter;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isStreaming => _isStreaming;
  String? get error => _error;
  String? get pendingPrompt => _pendingPrompt;
  bool get hasMessages => _messages.isNotEmpty;
  int? get userId => _userId;

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

  Future<void> sendMessage(String text) async {
    if (_userId == null || text.trim().isEmpty || _isStreaming) return;

    _error = null;

    _messages.add(ChatMessage(
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
    ));

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
    _streamCompleter = completer;

    String tokenBuffer = '';
    _flushTimer?.cancel();  // önceki akıştan artık kalmasın
    _flushTimer = null;

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
        _flushTimer ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
          flushBuffer();
        });
      },
      onDone: () {
        _flushTimer?.cancel();
        _flushTimer = null;
        flushBuffer();
        if (assistantIndex < _messages.length) {
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            isStreaming: false,
          );
        }
        _isStreaming = false;
        _activeStream = null;
        notifyListeners();
        _completeStream();
      },
      onError: (err) {
        _flushTimer?.cancel();
        _flushTimer = null;
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
        _completeStream();
      },
    );

    await completer.future;
  }

  void cancelStream() {
    _activeStream?.cancel();
    _activeStream = null;
    // Akış iptal edilince onDone/onError TETİKLENMEZ → zamanlayıcı burada
    // durdurulmazsa arkada çalışmaya devam eder.
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_messages.isNotEmpty && _messages.last.isStreaming) {
      _messages[_messages.length - 1] = _messages.last.copyWith(
        isStreaming: false,
      );
    }
    _isStreaming = false;
    notifyListeners();
    _completeStream();
  }

  /// Bekleyen `sendMessage`'ı serbest bırakır (iki kez tamamlamaya karşı korumalı).
  void _completeStream() {
    final c = _streamCompleter;
    _streamCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
  }

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
    _activeStream?.cancel();
    _flushTimer?.cancel();
    _flushTimer = null;
    _completeStream();
    super.dispose();
  }
}
