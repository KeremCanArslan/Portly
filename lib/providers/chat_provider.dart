import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  http.Client? _activeStream;

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
        flushTimer ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
          flushBuffer();
        });
      },
      onDone: () {
        flushTimer?.cancel();
        flushBuffer();
        if (assistantIndex < _messages.length) {
          _messages[assistantIndex] = _messages[assistantIndex].copyWith(
            isStreaming: false,
          );
        }
        _isStreaming = false;
        _activeStream = null;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
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
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
  }

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