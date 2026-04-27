import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
          onRefresh: () => provider.loadNewsData(force: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('AI Haber Analizi',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: provider.isNewsLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.tealAccent,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.refresh, color: Colors.tealAccent),
                      onPressed: provider.isNewsLoading
                          ? null
                          : () => provider.loadNewsData(force: true),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    'Doğal Dil İşleme (NLP) modeli ile piyasa haberlerinin anlık duygu analizi.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                const SizedBox(height: 24),
                if (provider.isNewsLoading && provider.newsData.isEmpty)
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
                        'Haber bulunamadı. Yenile butonuna basın.',
                        style: TextStyle(color: Colors.white54),
                      ),
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
                      context,
                      news as Map<String, dynamic>,
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
    final match = RegExp(r'\b[A-Z]{3,5}\b').firstMatch(title);
    return match?.group(0) ?? 'NEWS';
  }

  String _formatDate(dynamic iso) {
    try {

      DateTime date;
      if (iso is String) {

        date = DateTime.parse(iso);

        if (!iso.endsWith('Z') &&
            !iso.contains('+') &&
            !iso.substring(iso.length - 6).contains('-')) {
          date = DateTime.utc(date.year, date.month, date.day, date.hour,
              date.minute, date.second);
        }
      } else {
        return '';
      }

      final now = DateTime.now();
      final diff = now.difference(date.toLocal());

      if (diff.isNegative) {

        return 'şimdi';
      }
      if (diff.inSeconds < 60) return 'az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
      if (diff.inHours < 24) return '${diff.inHours} saat önce';
      if (diff.inDays < 7) return '${diff.inDays} gün önce';


      final months = [
        'Oca',
        'Şub',
        'Mar',
        'Nis',
        'May',
        'Haz',
        'Tem',
        'Ağu',
        'Eyl',
        'Eki',
        'Kas',
        'Ara'
      ];
      final localDate = date.toLocal();
      return '${localDate.day} ${months[localDate.month - 1]}';
    } catch (e) {
      return '';
    }
  }

  Widget _buildNewsCard(
      BuildContext context,
      Map<String, dynamic> news,
      String symbol,
      String sentiment,
      Color sentimentColor,
      double score,
      String time) {
    final title = news['title'] as String? ?? 'Başlık Yok';
    final description = news['description'] as String? ?? '';
    final url = news['url'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (url.isEmpty) return;
            final uri = Uri.tryParse(url);
            if (uri == null) return;
            try {
              final ok =
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Haber açılamadı')),
                );
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Haber açılamadı')),
                );
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.grey[400], fontSize: 12, height: 1.5),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(time,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12)),
                    const Spacer(),
                    if (url.isNotEmpty)
                      Row(
                        children: [
                          Text('Habere git',
                              style: TextStyle(
                                  color:
                                      Colors.tealAccent.withValues(alpha: 0.8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new,
                              color: Colors.tealAccent.withValues(alpha: 0.8),
                              size: 12),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
