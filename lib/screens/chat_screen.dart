import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  static const double _kContentMaxWidth = 760;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollToBottom(animate: false);
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
      _scrollController.animateTo(position,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _sendSuggestion(String text) {
    _inputController.text = text;
    _sendMessage();
  }

  Future<void> _confirmClear() async {
    final chat = context.read<ChatProvider>();
    showIOSBottomSheet(
      context: context,
      title: 'Sohbeti Temizle',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (ctx) {
              final c = AppColorsExt.of(ctx);
              return Text(
                'Tüm sohbet geçmişin silinecek. Bu işlem geri alınamaz.',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 14,
                  height: 1.5,
                  letterSpacing: -0.1,
                ),
              );
            }),
            const SizedBox(height: 20),
            IOSPillButton(
              label: 'Sohbeti Sil',
              width: double.infinity,
              onPressed: () async {
                Navigator.pop(context);
                await chat.clearHistory();
              },
            ),
            const SizedBox(height: 10),
            IOSPillButton(
              label: 'Vazgeç',
              secondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final portfolio = context.watch<PortfolioProvider>();
    final c = AppColorsExt.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chat.isStreaming) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: AppColorsExt.of(context)
            .bg, // opak: şeffaf AppBar açık temada ghost bırakıyor
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'AI Koç',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              // Sabit model adı yazmıyoruz: backend Gemini → Groq sırasıyla
              // düşüyor ve Groq'ta hangi modele erişildiği hesaba göre
              // değişiyor (3 Eyl: llama-3.3-70b 404 verdi). Ekranda yanlış
              // model adı görünmesin.
              chat.isStreaming ? 'yazıyor…' : 'Portföyüne göre yanıtlar',
              style: TextStyle(
                color: chat.isStreaming ? c.positive : c.textSubtle,
                fontSize: 11,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (chat.hasMessages)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: c.textMuted, size: 22),
              tooltip: 'Sohbeti temizle',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: Column(
        children: [
          if (portfolio.totalAssetValue > 0) ...[
            _buildPortfolioBadge(portfolio),
            const EliteHairline(),
          ],
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
                child: chat.isLoadingHistory
                    ? Center(
                        child: CircularProgressIndicator(color: c.textPrimary))
                    : chat.messages.isEmpty
                        ? _buildEmptyState()
                        : _buildMessagesList(chat),
              ),
            ),
          ),
          _buildInputBar(chat),
        ],
      ),
    );
  }

  Widget _buildPortfolioBadge(PortfolioProvider portfolio) {
    final c = AppColorsExt.of(context);
    final total = portfolio.totalAssetValue;
    final pnlPct = portfolio.totalPnlPercent;
    final isProfit = portfolio.totalPnl >= 0;
    final dataColor = isProfit ? c.positive : c.negative;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: c.bg,
      child: Row(
        children: [
          Text(
            'Toplam ₺${formatMoney(total, decimals: 0)}',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: dataColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${formatPctSigned(pnlPct, decimals: 2)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'AI BAĞLAMINDA',
            style: TextStyle(
              color: c.warmAccent,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = AppColorsExt.of(context);
    final suggestions = [
      ('Portföyüm dengeli mi?', 'Portföyümün risk dağılımını analiz et'),
      (
        'Davranışsal önyargılarım neler?',
        'Yatırım davranışlarımdaki önyargıları açıkla'
      ),
      (
        'Bugünkü haberler beni nasıl etkiler?',
        'Güncel haberlerin portföyüme etkisini değerlendir'
      ),
      (
        'En riskli pozisyonum hangisi?',
        'Portföyümdeki en yüksek riskli hisseyi bul ve nedenini açıkla'
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IOSLogoMark(size: 56),
          const SizedBox(height: 22),
          Text(
            'Merhaba.',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.2,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Portföyünü ve davranışsal profilini biliyorum. İstediğini sor.',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 15,
              height: 1.5,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 28),
          EliteSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < suggestions.length; i++) ...[
                  _suggestionRow(c, suggestions[i].$1, suggestions[i].$2),
                  if (i != suggestions.length - 1)
                    const EliteHairline(indent: 52),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow(AppColorsExt c, String title, String prompt) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _sendSuggestion(prompt),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, color: c.warmAccent, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(Icons.arrow_outward_rounded, color: c.textSubtle, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(ChatProvider chat) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: chat.messages.length,
      itemBuilder: (_, i) => _buildMessageBubble(chat.messages[i]),
    );
  }

  double _bubbleMaxWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final effective =
        screenWidth < _kContentMaxWidth ? screenWidth : _kContentMaxWidth;
    return effective * 0.86;
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final c = AppColorsExt.of(context);
    final isUser = msg.role == 'user';

    // ── Kullanıcı: ayrı ama minimal — sağda, sade ton baloncuğu ──
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: _bubbleMaxWidth(context)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: SelectableText(
                  msg.content,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Asistan: lüks EliteSurface kartı + AI işareti ──
    final thinking = msg.content.isEmpty && msg.isStreaming;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, right: 12),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: c.warmAccentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.auto_awesome, color: c.warmAccent, size: 15),
          ),
          Expanded(
            child: EliteSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: thinking
                  ? _buildThinking()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: msg.content,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                height: 1.6),
                            strong: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w700),
                            em: TextStyle(
                                color: c.textPrimary,
                                fontStyle: FontStyle.italic),
                            h1: TextStyle(
                                color: c.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                            h2: TextStyle(
                                color: c.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                            h3: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                            listBullet:
                                TextStyle(color: c.warmAccent, fontSize: 14),
                            code: TextStyle(
                                color: c.textPrimary,
                                backgroundColor: c.surfaceAlt,
                                fontFamily: 'monospace',
                                fontSize: 13),
                            codeblockDecoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            blockquoteDecoration: BoxDecoration(
                              color: c.surfaceAlt,
                              border: Border(
                                left: BorderSide(color: c.warmAccent, width: 3),
                              ),
                            ),
                            tableBorder: TableBorder.all(color: c.divider),
                            tableCellsPadding: const EdgeInsets.all(6),
                          ),
                        ),
                        if (msg.isStreaming && msg.content.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                _buildTypingDots(),
                                const SizedBox(width: 8),
                                // Noktalar tek başına belirsizdi: cevabın
                                // DEVAM ettiğini kelimeyle söyle.
                                Text(
                                  'yazıyor',
                                  style: TextStyle(
                                    color: c.textSubtle,
                                    fontSize: 11.5,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // "Düşünüyor" durumu — dots değil, zarif EliteSkeleton satırları.
  Widget _buildThinking() {
    final c = AppColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Yalnız skeleton çubuklar "cevap gelmiyor" gibi okunuyordu (Kerem,
        // 4 Eyl) — ne beklendiğini AÇIKÇA yaz. İlk token gelene kadar model
        // düşündüğü için burada birkaç saniye geçebiliyor.
        Text(
          'Yanıt hazırlanıyor…',
          style: TextStyle(
            color: c.textSubtle,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 12),
        const EliteSkeleton(height: 11, width: 210),
        const SizedBox(height: 9),
        const EliteSkeleton(height: 11),
        const SizedBox(height: 9),
        const EliteSkeleton(height: 11, width: 150),
      ],
    );
  }

  Widget _buildTypingDots() {
    final c = AppColorsExt.of(context);
    return SizedBox(
      width: 32,
      height: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.3, end: 1.0),
              duration: Duration(milliseconds: 600 + i * 200),
              curve: Curves.easeInOut,
              builder: (_, value, __) {
                return Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.textSubtle.withValues(alpha: value),
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
    final c = AppColorsExt.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const EliteHairline(),
        Container(
          color: c.bg,
          padding: EdgeInsets.only(
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: EliteRadii.lg,
                        ),
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocus,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14,
                              letterSpacing: -0.1),
                          cursorColor: c.textPrimary,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(2000),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Bir şey sor…',
                            hintStyle:
                                TextStyle(color: c.textSubtle, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap:
                          chat.isStreaming ? chat.cancelStream : _sendMessage,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: chat.isStreaming ? c.negative : c.textPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          chat.isStreaming
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          color: chat.isStreaming ? Colors.white : c.bg,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
