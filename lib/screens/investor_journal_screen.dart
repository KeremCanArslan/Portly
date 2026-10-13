import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/notes_provider.dart';
import 'package:portly/widgets/load_error_card.dart';
import 'package:portly/models/note.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/widgets/note_editor.dart';
import 'package:portly/utils/symbol_display.dart';

/// Yatırımcı Günlüğü — kullanıcının tüm notları (genel + hisse-bazlı).
/// Profil > Araçlar girişi. Hisse detaydaki "Notlarım" ile aynı [NotesProvider]'ı
/// ve [showNoteEditor] editörünü paylaşır (tek kaynak). data-ink: monokrom,
/// `Border.all` yok, glow yok.
class InvestorJournalScreen extends StatefulWidget {
  const InvestorJournalScreen({super.key});

  @override
  State<InvestorJournalScreen> createState() => _InvestorJournalScreenState();
}

class _InvestorJournalScreenState extends State<InvestorJournalScreen> {
  @override
  void initState() {
    super.initState();
    // Taze çek (başka cihazda eklenmiş olabilir); provider cache'i korur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotesProvider>().loadNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final prov = context.watch<NotesProvider>();
    final notes = prov.notes;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg, // opak: şeffaf AppBar açık temada ghost bırakır
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Yatırımcı Günlüğü',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: c.textPrimary, size: 24),
            tooltip: 'Yeni not',
            onPressed: () => showNoteEditor(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: prov.isLoading && notes.isEmpty
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : notes.isEmpty
                    ? (prov.error != null
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: LoadErrorCard(
                              title: 'Notlar yüklenemedi',
                              onRetry: () =>
                                  context.read<NotesProvider>().loadNotes(),
                            ),
                          )
                        : _empty())
                    : RefreshIndicator(
                        color: c.textPrimary,
                        backgroundColor: c.surface,
                        onRefresh: () =>
                            context.read<NotesProvider>().loadNotes(),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          itemCount: notes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _noteCard(notes[i]),
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final c = AppColorsExt.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text('Günlüğün boş',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2)),
            const SizedBox(height: 4),
            Text(
              'Kararlarını ve gözlemlerini not al; zamanla nasıl düşündüğünü gör.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textMuted, fontSize: 13, letterSpacing: -0.1),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 200,
              child: IOSPillButton(
                label: 'İlk Notu Yaz',
                onPressed: () => showNoteEditor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteCard(Note note) {
    final c = AppColorsExt.of(context);
    return GestureDetector(
      onTap: () => showNoteEditor(context, existing: note),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!note.isGeneral) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(SymbolDisplay.compact(note.symbol!),
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(formatNoteDate(note.updatedAt ?? note.createdAt),
                      style: TextStyle(color: c.textSubtle, fontSize: 11)),
                ),
                Icon(Icons.chevron_right, color: c.textSubtle, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(note.content,
                style: TextStyle(
                    color: c.textPrimary, fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
