# Portly — Claude Kılavuzu

**İLK İŞ (her session): `SESSION_HANDOFF.md`'nin en üstündeki ⚡ AÇILIŞ bloğunu oku
(~30 satır) ve işe oradan başla.** Sıradaki iş, kimde olduğu ve ilk sorulacak soru
orada. **Dosyanın tamamını baştan sona OKUMA** — token israfı; yalnız yaptığın iş
için gerekiyorsa ilgili bölüme atla (kod yazmadan önce 🛡 KALICI KURALLAR).
Detaylı backlog: `GELISTIRME_ONERILERI.md`. Geçmiş turlar: `docs/HANDOFF_ARSIV.md`.

**Turun sonunda:** ⚡ AÇILIŞ bloğunu baştan yaz (eklemeyle şişirme), turun
anlatısını altına koy, üçten eski turu `docs/HANDOFF_ARSIV.md`'ye taşı.

## Çalışma kuralları
- **Türkçe konuş** (kullanıcı: Kerem). Bitirme projesi; demo YAPILDI, **pivot
  BİTTİ**: sanal borsa değil → **portföy takip + haber + AL/TUT/SAT sinyal
  asistanı** (uygulama emir vermez; işlem geçmişi kullanıcının kendi kayıt
  defteri). Öncelik: **cila + dayanıklılık > yeni özellik**.
- **Ölçmeden düzeltme yazma.** Performans/veri iddialarını önce canlıda ya da
  testle ölç; ilk hipotez sık sık çürüyor (7. tur: kök sebep beklenen yerde
  değildi). Başka bir modelin listesi geldiğinde de aynısı: koddan doğrula,
  reddettiğini gerekçesiyle handoff'a yaz.
- **Commit/push SORMADAN yap** (Kerem 2026-09-04'te kalıcı izin verdi: "commit
  push etsin zaten sormadan gerektiğinde"). Koşul: iş BİTMİŞ ve testler yeşil
  olsun — yarım işi push etme. Push = Render prod deploy; deploy sonrası
  `/health` + değişen ucu curl ile doğrula. Konu başına ayrı commit.
- **Cihazda doğrulanmadan "çalışıyor/düzeldi" deme.** Frontend değişiklikleri telefon ister.
- Kalıcı kurallar (para gösterimi/data-ink/FX tek kaynak/AI kota vb.): handoff "KALICI KURALLAR".
- **Session başında** `git fetch` + `git log HEAD..origin/main` — lokal kopya Umut'un push'larının gerisinde olabilir.
- Commit mesajını heredoc ile ver (`git commit -F - <<'EOF'`); `-m "..."` içindeki ters tırnak zsh'te komut çalıştırır.

## Token tasarrufu
- **Bash'te `grep -r` KULLANMA** → `git grep` ya da Grep aracı. Kökteki kod dökümleri
  (`full_code.txt` ~150 MB, `flutter_*.txt`/`python_*.txt` ~1 MB) gitignore'da ama
  düz `grep -r` onları tarar ve çıktıyı kopya kodla doldurur.
- Dosyayı baştan sona okuma; `grep -n` ile satırı bul, `sed -n 'a,bp'` ile o aralığı oku.
- Test/log çıktısında yalnız özet ve hatalar: `pytest -q`; uzun log'u dosyaya yaz, `grep`'le.

## Testleri çalıştırma
- Backend: `cd backend && venv/bin/python -m pytest` (venv shebang bozuk → `python -m` şart).
- Flutter: `flutter test` (**proje kökünden**). Çıktıyı `| tail`/`| grep`'leme — exit kodu maskelenir.
- Uygulama: Flutter Web + FastAPI · Postgres (Neon) + Alembic · test kullanıcı `umut@mail.com / 123456`.
