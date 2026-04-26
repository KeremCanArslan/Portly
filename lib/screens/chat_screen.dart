import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/providers/portfolio_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollToBottom(animate: false);
      // Pending prompt varsa otomatik gönder (Hisseye uzun bas → AI'a sor)
      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      final pending = chat.consumePendingPrompt();
      if (pending != null && pending.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        _inputController.text = pending;
        _sendMessage();
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(position);
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final chat = context.read<ChatProvider>();
    if (chat.isStreaming) return;

    _inputController.clear();
    await chat.sendMessage(text);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _sendSuggestion(String text) {
    _inputController.text = text;
    _sendMessage();
  }

  Future<void> _confirmClear() async {
    final chat = context.read<ChatProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Sohbeti Temizle',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tüm sohbet geçmişin silinecek. Bu işlem geri alınamaz.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await chat.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final portfolio = context.watch<PortfolioProvider>();

    // Streaming sırasında otomatik scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chat.isStreaming) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Portly AI Koç',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(
                  chat.isStreaming
                      ? 'yazıyor...'
                      : 'Llama 3.3 70B • RAG destekli',
                  style: TextStyle(
                      color: chat.isStreaming
                          ? Colors.greenAccent
                          : Colors.grey[500],
                      fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (chat.hasMessages)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: 'Sohbeti temizle',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: Column(
        children: [
          // Portföy özet rozeti
          if (portfolio.totalAssetValue > 0) _buildPortfolioBadge(portfolio),

          // Mesajlar
          Expanded(
            child: chat.isLoadingHistory
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.tealAccent))
                : chat.messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessagesList(chat),
          ),

          // Input bar
          _buildInputBar(chat),
        ],
      ),
    );
  }

  Widget _buildPortfolioBadge(PortfolioProvider portfolio) {
    final total = portfolio.totalAssetValue;
    final pnl = portfolio.totalPnl;
    final pnlPct = portfolio.totalPnlPercent;
    final isProfit = pnl >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet,
              color: Colors.tealAccent.withValues(alpha: 0.7), size: 16),
          const SizedBox(width: 8),
          Text(
            'Toplam: ₺${total.toStringAsFixed(0)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isProfit ? Colors.greenAccent : Colors.redAccent)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
              style: TextStyle(
                color: isProfit ? Colors.greenAccent : Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'AI BAĞLAMINDA',
              style: TextStyle(
                color: Colors.purpleAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final suggestions = [
      ('📊', 'Portföyüm dengeli mi?', 'Portföyümün risk dağılımını analiz et'),
      (
        '🧠',
        'Davranışsal önyargılarım neler?',
        'Yatırım davranışlarımdaki önyargıları açıkla'
      ),
      (
        '📰',
        'Bugünkü haberler beni nasıl etkiler?',
        'Güncel haberlerin portföyüme etkisini değerlendir'
      ),
      (
        '⚡',
        'En riskli pozisyonum hangisi?',
        'Portföyümdeki en yüksek riskli hisseyi bul ve nedenini açıkla'
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // AI avatar büyük
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.purpleAccent.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child:
                const Icon(Icons.auto_awesome, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Merhaba 👋',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Portföyünü ve davranışsal profilini biliyorum.\nİstediğini sor.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.grey[400], fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          // Önerilen sorular
          ...suggestions.map((s) => _buildSuggestionCard(s.$1, s.$2, s.$3)),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(String emoji, String title, String fullPrompt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _sendSuggestion(fullPrompt),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.3)),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(ChatProvider chat) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: chat.messages.length,
      itemBuilder: (_, i) {
        final msg = chat.messages[i];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    final isAssistant = msg.role == 'assistant';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAssistant) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                ),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isUser
                    ? const LinearGradient(
                        colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isUser ? null : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isAssistant
                    ? Border.all(color: Colors.white.withValues(alpha: 0.06))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    msg.content.isEmpty && msg.isStreaming
                        ? '...'
                        : msg.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (msg.isStreaming && msg.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildTypingDots(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDots() {
    return SizedBox(
      width: 24,
      height: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.3, end: 1.0),
              duration: Duration(milliseconds: 600 + i * 200),
              curve: Curves.easeInOut,
              builder: (_, value, __) {
                return Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: value),
                    shape: BoxShape.circle,
                  ),
                );
              },
              onEnd: () {
                if (mounted) setState(() {});
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInputBar(ChatProvider chat) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(2000),
                ],
                decoration: InputDecoration(
                  hintText: 'Bir şey sor...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: chat.isStreaming ? chat.cancelStream : _sendMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: chat.isStreaming
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                      ),
                color: chat.isStreaming ? Colors.redAccent : null,
                shape: BoxShape.circle,
              ),
              child: Icon(
                chat.isStreaming ? Icons.stop : Icons.arrow_upward,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
