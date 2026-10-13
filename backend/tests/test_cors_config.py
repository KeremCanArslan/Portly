"""CORS kilidi (4 Eylül 2026, 8. tur).

Canlıda ölçüldü: `curl -H "Origin: https://kotu-site.example" .../health` →
`access-control-allow-origin: *`. Yani herhangi bir site Portly API'sini kendi
sayfasından çağırabiliyordu; ücretsiz katman kotasını da o tüketirdi.
Kod zaten env okuyordu, değer `*` kalmıştı. Buradaki testler ayarın env'den
doğru çözüldüğünü ve prod'da `*` kalırsa bunun SESSİZ geçmediğini tutar.
"""

from app.main import resolve_cors_settings


def test_wildcard_kimlik_bilgisini_kapatir():
    # CORS spec: allow_origins=* ile credentials birlikte kullanılamaz.
    cfg = resolve_cors_settings(origins_env="*", regex_env="", is_production=False)
    assert cfg["allow_origins"] == ["*"]
    assert cfg["allow_credentials"] is False


def test_prod_wildcard_uyari_bayragi_kaldirir():
    cfg = resolve_cors_settings(origins_env="*", regex_env="", is_production=True)
    assert cfg["insecure_in_production"] is True


def test_kilitli_origin_prod_uyarisi_vermez():
    cfg = resolve_cors_settings(
        origins_env="https://portly-frontend.onrender.com",
        regex_env="",
        is_production=True,
    )
    assert cfg["allow_origins"] == ["https://portly-frontend.onrender.com"]
    assert cfg["allow_credentials"] is True
    assert cfg["insecure_in_production"] is False


def test_virgullu_liste_bosluklardan_temizlenir():
    cfg = resolve_cors_settings(
        origins_env=" https://a.example , https://b.example ,, ",
        regex_env="",
        is_production=True,
    )
    assert cfg["allow_origins"] == ["https://a.example", "https://b.example"]


def test_listede_yildiz_varsa_tek_basina_yildiza_iner():
    # "https://a.example,*" gibi bir değer kısmi kilit sanılmasın.
    cfg = resolve_cors_settings(
        origins_env="https://a.example,*", regex_env="", is_production=True
    )
    assert cfg["allow_origins"] == ["*"]
    assert cfg["insecure_in_production"] is True


def test_regex_bos_string_none_olur():
    # Starlette boş string'i "hiçbir şeye uymayan kalıp" saymaz; None olmalı.
    cfg = resolve_cors_settings(
        origins_env="https://a.example", regex_env="   ", is_production=True
    )
    assert cfg["allow_origin_regex"] is None


def test_regex_verilirse_tasinir():
    cfg = resolve_cors_settings(
        origins_env="https://a.example",
        regex_env=r"^http://(localhost|127\.0\.0\.1)(:\d+)?$",
        is_production=False,
    )
    assert cfg["allow_origin_regex"] == r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"
