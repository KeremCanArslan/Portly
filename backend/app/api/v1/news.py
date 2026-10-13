from fastapi import APIRouter, Depends, Query, Request
from typing import List
from pydantic import BaseModel, Field
from app.core.limiter import limiter
from app.models.user import User
from app.schemas.news_schema import NewsResponse
from app.services import auth_service, news_analysis_service, nlp_sentiment_service

router = APIRouter()

# Haber uçları GİRİŞ İSTER. Üçü de LLM/RSS zincirini tetikliyor ve LLM
# kotaları ücretsiz katmanda sınırlı (canlıda Gemini 429 → Groq zinciri
# tükendiğinde sohbet · haber analizi · makro takvim AYNI ANDA düşüyor).
# Kimliksiz erişimde bu kotayı herkes yakabilirdi; uygulamanın kendisi zaten
# giriş kapısının ardında çalışıyor, istemci her istekte Bearer token yolluyor.


class NewsAnalyzeRequest(BaseModel):
    title: str = Field(..., min_length=3, max_length=500)
    description: str = Field(default="", max_length=2000)


@router.post("/analyze")
@limiter.limit("20/minute")
def analyze_news(
    request: Request,
    payload: NewsAnalyzeRequest,
    current_user: User = Depends(auth_service.get_current_user),
):
    """Bir haber için derin LLM analizi: etkilenen varlıklar, sektörler, vade yorumları."""
    return news_analysis_service.analyze(payload.title, payload.description)


@router.get("/latest", response_model=List[NewsResponse])
@limiter.limit("30/minute")
def get_latest_news(
    request: Request,
    query: str = "stock market",
    force: bool = False,
    current_user: User = Depends(auth_service.get_current_user),
):
    """
    En güncel finansal haberleri VADER sentiment analizi ile birlikte döndürür.
    force=true verilirse cache'i bypass eder.
    """
    return nlp_sentiment_service.get_financial_news(query=query, force_refresh=force)


@router.get("/for-symbols", response_model=List[NewsResponse])
@limiter.limit("30/minute")
def news_for_symbols(
    request: Request,
    q: List[str] = Query(default=[]),
    force: bool = False,
    current_user: User = Depends(auth_service.get_current_user),
):
    """Portföyüm/İzleme: çok-sembollü haber tek istekte. Sunucu, sembol
    sorgularını (`?q=...&q=...`) paralel çeker + TEK batch LLM enrich yapar —
    istemci sembol-başına N ayrı çağrı atmasın (ilk açılış gecikmesi)."""
    return nlp_sentiment_service.get_news_for_symbols(q, force_refresh=force)