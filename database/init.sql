//tablo oluştur

psql postgres

CREATE DATABASE finans_db;
\c finans_db;

CREATE TABLE musteri_islemleri (
    islem_id SERIAL PRIMARY KEY,
    musteri_no INT NOT NULL,
    islem_tarihi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tutar DECIMAL(15,2) NOT NULL,
    islem_tipi VARCHAR(50),
    kredi_karti_no VARCHAR(20), 
    durum VARCHAR(20) DEFAULT 'Basarili'
);

//

INSERT INTO musteri_islemleri (musteri_no, islem_tarihi, tutar, islem_tipi, kredi_karti_no, durum)
SELECT
    (random() * 10000 + 1)::int,
    NOW() - (random() * (interval '365 days')),
    (random() * 50000)::decimal(15,2),
    CASE WHEN random() < 0.5 THEN 'EFT' ELSE 'Kredi Karti' END,
    '4532' || LPAD((random() * 1000000000000)::bigint::text, 12, '0'),
    CASE WHEN random() < 0.05 THEN 'Basarisiz' ELSE 'Basarili' END
FROM generate_series(1, 1000000);


EXPLAIN ANALYZE
SELECT musteri_no, islem_tarihi, tutar,
       AVG(tutar) OVER(PARTITION BY musteri_no ORDER BY islem_tarihi ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) as onceki_5_islem_ortalamasi
FROM musteri_islemleri
WHERE tutar > 40000;


SELECT relname as tablo_adi, seq_scan as tam_tarama_sayisi, seq_tup_read as okunan_satir, idx_scan as indeks_kullanimi 
FROM pg_stat_user_tables 
WHERE relname = 'musteri_islemleri';

CREATE INDEX idx_basarisiz_loglar ON musteri_islemleri(islem_tarihi) WHERE durum = 'Basarisiz';
CREATE INDEX idx_musteri_tutar ON musteri_islemleri(musteri_no, tutar);
SHOW work_mem;
SET work_mem = '256MB';

DELETE FROM musteri_islemleri WHERE islem_id IN (SELECT islem_id FROM musteri_islemleri ORDER BY random() LIMIT 5000);
VACUUM FULL VERBOSE musteri_islemleri;

EXPLAIN ANALYZE
SELECT musteri_no, islem_tarihi, tutar,
       AVG(tutar) OVER(PARTITION BY musteri_no ORDER BY islem_tarihi ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING) as onceki_5_islem_ortalamasi
FROM musteri_islemleri
WHERE tutar > 40000;
