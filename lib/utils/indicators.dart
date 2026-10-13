import 'dart:math' as math;

/// Saf teknik gösterge matematiği — TradingView-tarzı backtest araçları.
/// Tümü `closes` (veya OHLCV) üzerinden, hizalı `List<double?>` döner
/// (warmup periyodunda `null`). UI'dan bağımsız, test edilebilir.
class Indicators {
  /// Basit Hareketli Ortalama.
  static List<double?> sma(List<double> src, int period) {
    final out = List<double?>.filled(src.length, null);
    double sum = 0;
    for (int i = 0; i < src.length; i++) {
      sum += src[i];
      if (i >= period) sum -= src[i - period];
      if (i + 1 >= period) out[i] = sum / period;
    }
    return out;
  }

  /// Üssel Hareketli Ortalama (SMA tohumlu).
  static List<double?> ema(List<double> src, int period) {
    final out = List<double?>.filled(src.length, null);
    if (src.length < period) return out;
    final k = 2 / (period + 1);
    double seed = 0;
    for (int i = 0; i < period; i++) {
      seed += src[i];
    }
    double prev = seed / period;
    out[period - 1] = prev;
    for (int i = period; i < src.length; i++) {
      prev = (src[i] - prev) * k + prev;
      out[i] = prev;
    }
    return out;
  }

  /// Bollinger Bantları — orta (SMA), üst/alt = mid ± mult·stdev.
  static ({List<double?> mid, List<double?> upper, List<double?> lower})
      bollinger(List<double> src, int period, double mult) {
    final mid = sma(src, period);
    final upper = List<double?>.filled(src.length, null);
    final lower = List<double?>.filled(src.length, null);
    for (int i = period - 1; i < src.length; i++) {
      final m = mid[i];
      if (m == null) continue;
      double sq = 0;
      for (int j = i - period + 1; j <= i; j++) {
        final d = src[j] - m;
        sq += d * d;
      }
      final sd = math.sqrt(sq / period);
      upper[i] = m + mult * sd;
      lower[i] = m - mult * sd;
    }
    return (mid: mid, upper: upper, lower: lower);
  }

  /// Wilder yumuşatmalı RSI (0-100).
  static List<double?> rsi(List<double> src, int period) {
    final out = List<double?>.filled(src.length, null);
    if (src.length <= period) return out;
    double gain = 0, loss = 0;
    for (int i = 1; i <= period; i++) {
      final ch = src[i] - src[i - 1];
      if (ch >= 0) {
        gain += ch;
      } else {
        loss -= ch;
      }
    }
    double avgGain = gain / period;
    double avgLoss = loss / period;
    out[period] = _rsiFrom(avgGain, avgLoss);
    for (int i = period + 1; i < src.length; i++) {
      final ch = src[i] - src[i - 1];
      final g = ch >= 0 ? ch : 0.0;
      final l = ch < 0 ? -ch : 0.0;
      avgGain = (avgGain * (period - 1) + g) / period;
      avgLoss = (avgLoss * (period - 1) + l) / period;
      out[i] = _rsiFrom(avgGain, avgLoss);
    }
    return out;
  }

  static double _rsiFrom(double avgGain, double avgLoss) {
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  /// MACD — (macd = emaFast − emaSlow), signal = ema(macd), hist = macd − signal.
  static ({List<double?> macd, List<double?> signal, List<double?> hist}) macd(
      List<double> src,
      {int fast = 12,
      int slow = 26,
      int signalPeriod = 9}) {
    final emaFast = ema(src, fast);
    final emaSlow = ema(src, slow);
    final macdLine = List<double?>.filled(src.length, null);
    final compact = <double>[];
    final compactIdx = <int>[];
    for (int i = 0; i < src.length; i++) {
      final f = emaFast[i];
      final s = emaSlow[i];
      if (f == null || s == null) continue;
      final v = f - s;
      macdLine[i] = v;
      compact.add(v);
      compactIdx.add(i);
    }
    final signal = List<double?>.filled(src.length, null);
    final hist = List<double?>.filled(src.length, null);
    final sig = ema(compact, signalPeriod);
    for (int j = 0; j < compactIdx.length; j++) {
      final s = sig[j];
      if (s == null) continue;
      final idx = compactIdx[j];
      signal[idx] = s;
      final m = macdLine[idx];
      if (m != null) hist[idx] = m - s;
    }
    return (macd: macdLine, signal: signal, hist: hist);
  }

  /// Kümülatif VWAP — Σ(tipikFiyat·hacim) / Σ(hacim).
  static List<double?> vwap(List<double> highs, List<double> lows,
      List<double> closes, List<double> volumes) {
    final n = closes.length;
    final out = List<double?>.filled(n, null);
    double pv = 0, vol = 0;
    for (int i = 0; i < n; i++) {
      final tp = (highs[i] + lows[i] + closes[i]) / 3;
      final v = volumes[i];
      pv += tp * v;
      vol += v;
      if (vol > 0) out[i] = pv / vol;
    }
    return out;
  }
}
