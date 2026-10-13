from pydantic import BaseModel
from datetime import datetime


class AffectedAsset(BaseModel):
    symbol: str
    name: str


class NewsResponse(BaseModel):
    title: str
    description: str | None = None
    url: str
    published_at: datetime
    sentiment_label: str
    sentiment_score: float
    affected_assets: list[AffectedAsset] = []
    # Haberi getiren sembol sorgusu ("LMT", "ASELS OR Aselsan"). İstemci
    # portföy/izleme haberini bununla eşliyor: başlıkta şirketin ADI geçip
    # sembolü geçmediğinde metin eşlemesi doğru haberi eliyordu.
    matched_query: str | None = None