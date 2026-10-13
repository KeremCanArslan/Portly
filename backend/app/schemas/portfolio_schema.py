from pydantic import BaseModel

class PortfolioItemResponse(BaseModel):
    symbol: str
    quantity: float
    average_cost: float
    current_price: float
    total_value: float
    pnl: float
    pnl_percent: float
    # Pozisyonun BUGÜNKÜ % değişimi (dün kapanış → şimdi). Ana sayfa "Bugün"
    # K/Z'sini besler (frontend dailyPnl). ŞEMADA OLMAZSA response_model SİLER
    # → servis üretse bile "Bugün = ₺0" görünür (40. tur regresyonu).
    change_percent: float = 0.0
    currency: str = "USD"
    # ₺ karşılıkları — USD pozisyonlar canlı USDTRY ile çevrilir. Bu alanlar
    # ŞEMADA OLMAZSA FastAPI response_model bunları cevaptan SİLER → frontend
    # native total_value'a düşüp USD+₺'yi ham toplar (Apple $200 ≈ ₺200).
    # Tek-birim toplam/ağırlık/sektör/donut bu *_try alanlarını okur.
    total_value_try: float
    total_cost_try: float
    pnl_try: float
    # ₺ K/Z'nin KUR kaynaklı kısmı (native_maliyet × [canlı kur − alış kuru]).
    # Maliyet artık alış günündeki kurla değerlendiği için kur kazancı K/Z'ye
    # giriyor; bu alan onu ayırıp arayüzün açıklamasına izin verir. Alış kuru
    # bilinmeyen (kolon öncesi) pozisyonlarda 0.
    fx_gain_try: float = 0.0
    # Fiyat CANLI mı geldi, yoksa alınamayıp maliyete mi düşüldü?
    # ŞEMADA OLMAZSA response_model SİLER → ekran "veri yok"u ayırt edemez ve
    # maliyeti fiyat sanıp "+%0,00" basar (canlıda BIST'te görüldü).
    # Varsayılan True: eski istemci/yanıt yolları davranış değiştirmesin.
    price_available: bool = True
    # Günlük % değişim GERÇEK mi? (altın/gümüş spot kaynağı fiyatı verir ama
    # dünkü kapanışı vermez → change_percent 0.0 kalır). ŞEMADA OLMAZSA
    # response_model SİLER → ekran uydurma "Bugün +%0,00" basar.
    change_available: bool = True
