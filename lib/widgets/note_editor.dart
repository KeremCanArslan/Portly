import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/models/note.dart';
import 'package:portly/providers/notes_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/utils/symbol_display.dart';

const _aylar = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
];

/// Not tarihini kısa Türkçe biçimde verir — "16 Haz 2026  20:53" (yerel saat).
String formatNoteDate(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${l.day} ${_aylar[l.month - 1]} ${l.year}  $hh:$mm';
}

/// Not ekleme/düzenleme alt-sayfasını açar. [NotesProvider] üstünden CRUD yapar,
/// sonucu snackbar ile bildirir. Yatırımcı Günlüğü ve hisse detay "Notlarım"
/// buraya delege eder (tek kaynak).
/// - [existing] verilirse düzenleme (symbol değişmez; backend yalnız content günceller).
/// - [lockedSymbol] eklemede sabit hisse (hisse detay); null → genel ekran,
///   kullanıcı opsiyonel sembol girebilir.
void showNoteEditor(BuildContext context, {Note? existing, String? lockedSymbol}) {
  final c = AppColorsExt.of(context);
  final contentCtrl = TextEditingController(text: existing?.content ?? '');
  final symbolCtrl = TextEditingController(text: existing?.symbol ?? '');
  final editing = existing != null;
  final boundSymbol = existing?.symbol ?? lockedSymbol; // gösterim için sabit hisse
  // await sonrası context kullanmamak için provider + messenger önceden yakalanır.
  final provider = context.read<NotesProvider>();
  final messenger = ScaffoldMessenger.of(context);

  showIOSBottomSheet(
    context: context,
    title: editing
        ? 'Notu Düzenle'
        : (lockedSymbol != null
            ? '${SymbolDisplay.compact(lockedSymbol)} — Yeni Not'
            : 'Yeni Not'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: contentCtrl,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            style: TextStyle(color: c.textPrimary, fontSize: 15, height: 1.35),
            decoration: InputDecoration(
              hintText: 'Bugün ne gözlemledin? Kararın ve gerekçen...',
              hintStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.surface,
              counterText: '',
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (boundSymbol != null && boundSymbol.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text('Hisse: ${SymbolDisplay.compact(boundSymbol)}',
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
            )
          else if (!editing)
            IOSField(
              controller: symbolCtrl,
              label: 'Hisseye bağla (opsiyonel) — THYAO',
              icon: Icons.tag_rounded,
              textCapitalization: TextCapitalization.characters,
            ),
          const SizedBox(height: 16),
          IOSPillButton(
            label: editing ? 'Kaydet' : 'Ekle',
            width: double.infinity,
            onPressed: () async {
              final content = contentCtrl.text.trim();
              if (content.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Not boş olamaz')),
                );
                return;
              }
              Navigator.pop(context);
              final bool ok;
              if (editing) {
                ok = await provider.editNote(existing.id, content);
              } else {
                final sym = (lockedSymbol ?? symbolCtrl.text.trim()).toUpperCase();
                ok = await provider.addNote(content,
                    symbol: sym.isEmpty ? null : sym);
              }
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? (editing ? 'Not güncellendi' : 'Not eklendi')
                      : 'İşlem başarısız'),
                ),
              );
            },
          ),
          if (editing) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final ok = await provider.removeNote(existing.id);
                messenger.showSnackBar(
                  SnackBar(content: Text(ok ? 'Not silindi' : 'Silinemedi')),
                );
              },
              child: Text('Notu Sil',
                  style: TextStyle(
                      color: c.negative, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    ),
  );
}
