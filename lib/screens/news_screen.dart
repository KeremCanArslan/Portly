import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: RefreshIndicator(
          color: Colors.tealAccent,
          onRefresh: () => provider.loadNewsData(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Haber Analizi',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    'Doğal Dil İşleme (NLP) modeli ile piyasa haberlerinin anlık duygu analizi.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                const SizedBox(height: 24),
                if (provider.isNewsLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child:
                          CircularProgressIndicator(color: Colors.tealAccent),
                    ),
                  )
                else if (provider.newsData.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                          'Haber bulunamadı. Aşağı çekerek tekrar deneyin.',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  )
                else
                  ...provider.newsData.map((news) {
                    final title = news['title'] ?? 'Başlık Yok';
                    final sentimentLabel = news['sentiment_label'] ?? 'Nötr';
                    final score =
                        (news['sentiment_score'] as num?)?.toDouble() ?? 0.0;
                    final publishedAt = news['published_at'] ?? '';

                    final Color sentimentColor = switch (sentimentLabel) {
                      'Pozitif' => Colors.greenAccent,
                      'Negatif' => Colors.redAccent,
                      _ => Colors.grey,
                    };

                    return _buildNewsCard(
                      title,
                      _extractSymbolFromTitle(title),
                      sentimentLabel,
                      sentimentColor,
                      score,
                      _formatDate(publishedAt),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _extractSymbolFromTitle(String title) {
    // Basit sembol çıkarıcı — başlıkta AAPL, TSLA gibi büyük harfli 3-5 karakter
    final match = RegExp(r'\b[A-Z]{3,5}\b').firstMatch(title);
    return match?.group(0) ?? 'NEWS';
  }

  String _formatDate(String iso) {
    try {
      final date = DateTime.parse(iso);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
      if (diff.inHours < 24) return '${diff.inHours} saat önce';
      return '${diff.inDays} gün önce';
    } catch (_) {
      return '';
    }
  }

  Widget _buildNewsCard(String title, String symbol, String sentiment,
      Color sentimentColor, double score, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(symbol,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sentimentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      sentiment == 'Pozitif'
                          ? Icons.trending_up
                          : sentiment == 'Negatif'
                              ? Icons.trending_down
                              : Icons.horizontal_rule,
                      color: sentimentColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text('AI: $sentiment (${score.toStringAsFixed(2)})',
                        style: TextStyle(
                            color: sentimentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }
}
