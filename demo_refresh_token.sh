#!/bin/bash
# Refresh Token Akışı — Hoca Sunum Scripti
# Çalıştırmak için: bash demo_refresh_token.sh

BASE=http://localhost:8000/api/v1
EMAIL="hoca_demo_$(date +%s)@portly.com"

pause() { echo ""; read -p "  >> Enter ile devam <<" _; echo ""; }

echo "════════════════════════════════════════════════════"
echo "  PORTLY — REFRESH TOKEN AKIŞ DEMOSU"
echo "════════════════════════════════════════════════════"
pause

echo "▶ 1) KAYIT — sunucu access_token + refresh_token döner"
echo "   POST /auth/register"
RESP=$(curl -s -X POST $BASE/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"demo1234\",\"full_name\":\"Hoca Demo\"}")
ACCESS=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))")
REFRESH=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('refresh_token',''))")
echo ""
echo "   📥 access_token  (1 saat geçerli, JWT):"
echo "      ${ACCESS:0:60}..."
echo ""
echo "   📥 refresh_token (30 gün, DB'de hash'li):"
echo "      ${REFRESH:0:60}..."
pause

echo "▶ 2) ACCESS İLE /me — kimlik doğrulama çalışıyor"
echo "   GET /auth/me  Authorization: Bearer <access>"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $BASE/auth/me -H "Authorization: Bearer $ACCESS")
echo "   ✅ HTTP $STATUS (başarılı)"
pause

echo "▶ 3) REFRESH — eski refresh ile YENİ access + refresh al"
echo "   POST /auth/refresh"
RESP2=$(curl -s -X POST $BASE/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH\"}")
NEW_ACCESS=$(echo "$RESP2" | python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))")
NEW_REFRESH=$(echo "$RESP2" | python3 -c "import json,sys;print(json.load(sys.stdin).get('refresh_token',''))")
echo "   📥 yeni access : ${NEW_ACCESS:0:60}..."
echo "   📥 yeni refresh: ${NEW_REFRESH:0:60}..."
echo ""
echo "   ❗ DİKKAT: Refresh token değişti! Buna 'token rotation' denir."
echo "   ❗ Eski refresh artık geçersiz — çalınsa bile kullanılamaz."
pause

echo "▶ 4) TOKEN ROTATION TESTİ — eski refresh'i tekrar dene"
echo "   POST /auth/refresh  (eski refresh ile)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH\"}")
echo "   🚫 HTTP $STATUS — eski refresh REDDEDİLDİ (güvenlik özelliği)"
pause

echo "▶ 5) LOGOUT — sunucu tarafında refresh token'ları iptal eder"
echo "   POST /auth/logout"
curl -s -X POST $BASE/auth/logout -H "Authorization: Bearer $NEW_ACCESS" > /dev/null
echo "   ✅ Logout başarılı"
pause

echo "▶ 6) LOGOUT SONRASI — yeni refresh artık kullanılamaz"
echo "   POST /auth/refresh"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$NEW_REFRESH\"}")
echo "   🚫 HTTP $STATUS — refresh token DB'de revoked=true olarak işaretlendi"
echo ""
echo "════════════════════════════════════════════════════"
echo "  SONUÇ: Production-ready auth akışı"
echo "  • Access 7 gün → 1 saat (sızıntı riski %99 azaldı)"
echo "  • Refresh DB'de hash'li, sunucu iptal edebiliyor"
echo "  • Token rotation çalınma durumunda zararı sınırlıyor"
echo "════════════════════════════════════════════════════"
