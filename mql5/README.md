# GoldPilot Scalper — EA Auto Scalping XAUUSD (MT5)

EA scalping XAUUSD. Eksekusi di M1, arah trend dari M5/M15. Dibuat berdasarkan `PRD_EA_XAUUSD_MT5_PHP.md` (milestone M4).

> **Status:** kode ini belum di-compile atau di-backtest. Compile di MetaEditor, lalu backtest dan forward test di akun demo sebelum dipakai di akun real.

## Struktur file

```
mql5/
├── Experts/GoldPilot/GoldPilot_Scalper.mq5   ← file EA utama (input, event handler, panel)
├── Include/GoldPilot/
│   ├── Defines.mqh      enum & struct sinyal
│   ├── Utils.mqh        waktu server↔GMT (+DST), sesi, GlobalVariable, JSON
│   ├── Bus.mqh          outbox/status JSON untuk EA Bridge (tanpa WebRequest)
│   ├── MarketState.mqh  buffer spread & tick, handle indikator, VWAP, bias M5/M15
│   ├── News.mqh         filter berita (kalender MT5 + CSV)
│   ├── Risk.mqh         lot sizing, daily loss, max DD, giveback, loss beruntun
│   ├── Signals.mqh      Setup A / B / C
│   └── Trader.mqh       eksekusi + retry, BE, partial, trailing, time exit, kualitas eksekusi
└── Files/GoldPilot/news.csv   contoh file berita
```

## Instalasi

1. Di MT5 buka **File → Open Data Folder**.
2. Salin `Experts/GoldPilot/` ke `MQL5/Experts/`, lalu `Include/GoldPilot/` ke `MQL5/Include/`.
3. Salin `Files/GoldPilot/news.csv` ke folder **Common**: `%APPDATA%\MetaQuotes\Terminal\Common\Files\GoldPilot\news.csv`.
4. Buka `GoldPilot_Scalper.mq5` di MetaEditor dan tekan **F7 (Compile)**.
5. Pasang EA di chart **XAUUSD M1** dan aktifkan **Algo Trading**.
6. Atur **Zona Waktu Broker**. Mode `Otomatis` hanya berlaku saat live. Untuk backtest isi offset musim dingin broker (umumnya `2`) dan DST (`US`).

Syarat akun: ECN/raw spread, broker mengizinkan scalping, dan VPS dekat server broker (ping < 20–50 ms).

## Ringkasan logika

| Bagian | Aturan default |
|---|---|
| Sesi (GMT) | London 07:00–10:30, overlap NY 12:30–16:30; blok rollover 23:30–01:30 (jam server); Jumat tidak ada entry baru ≥ 19:00, semua posisi ditutup 20:30 |
| Filter | spread ≤ $0.20; spread ≤ 15% SL; tidak ada spike (> 2× rata-rata 200 tick); ATR M1 $0.40–2.50; ≥ 40 tick/menit; ping ≤ 50 ms; TP ≥ 3× (spread + komisi + slippage) |
| Berita | tidak ada entry 15 menit sebelum s/d 30 menit sesudah berita high-impact USD; posisi ditutup 2 menit sebelum rilis |
| Bias | EMA20 > EMA50 di M5 + slope naik + close M15 di atas EMA50 + harga di atas VWAP (kebalikannya untuk sell) |
| Setup A | pullback ke EMA9/21 M1, RSI(7) turun ke 30–50 lalu naik lagi, candle konfirmasi (body ≥ 50%, close menembus high/low sebelumnya), tick volume ≥ 1.2× rata-rata |
| Setup B | squeeze Bollinger (lebar band di persentil 20% terbawah, ≥ 5 bar), breakout close dengan body ≥ 60% dan volume ≥ 1.5× (2× jika bias netral) |
| Setup C | mean reversion saat ADX M5 < 18 (default **OFF**) |
| SL | max(1.2×ATR, swing 5 bar + spread), SL harus $0.80–3.50 (lebih lebar = trade dilewati); **selalu hard SL di server** |
| TP | 1.2R (atau partial 60% di 0.8R + runner 2R), BE di 0.6R, trailing 0.8×ATR mulai 1R |
| Waktu | maksimal 20 menit per posisi; ditutup jika setelah 5 menit profit < 0.2R; keluar lebih awal jika ada candle kuat berlawanan; cooldown 3 menit (10 menit setelah loss) |
| Lot | 0.5% equity per trade (dibatasi maks 1.5%), sudah memperhitungkan spread + komisi; trade dilewati jika lot < minimum broker |
| Guard | daily loss 2% (tutup semua); giveback 50% dari puncak profit harian; max DD 8% dari puncak equity → EA **terkunci**; 3 loss beruntun → pause 60 menit, 5 → stop hari itu; maks 6 trade/jam dan 25 trade/hari |
| Kualitas eksekusi | EA auto-pause jika rata-rata slippage > $0.05 atau eksekusi > 500 ms |

## Integrasi dengan web (lewat EA Bridge, milestone berikutnya)

EA Scalper **tidak memanggil `WebRequest`**. Komunikasi berjalan lewat folder `Common\Files\GoldPilot\<login>\`:

- `status.json` ditulis setiap 5 detik (equity, spread, ping, status, guard, alasan entry terakhir ditolak).
- `outbox/*.json` berisi `trade_open`, `trade_partial`, `trade_close` (termasuk slippage, waktu eksekusi, R, MAE/MFE, alasan exit) dan `event`.
- Perintah dari web dikirim sebagai GlobalVariable dengan nilai `1`:
  - `GPS_<login>_PAUSE` (nilai 0 = lanjut)
  - `GPS_<login>_CLOSEALL`
  - `GPS_<login>_RESUME` (membersihkan auto-pause)
  - `GPS_<login>_UNLOCK` (membuka kunci max DD)

  Sebelum EA Bridge jadi, variabel ini bisa diset manual lewat **Tools → Global Variables (F3)**.

## Backtest yang benar

1. Mode **Every tick based on real ticks**. Mode OHLC tidak valid untuk scalping.
2. Gunakan komisi dan spread asli broker. Uji ulang dengan **Delay** eksekusi acak, dan dengan `InpMaxSpread` dan `InpCostMultiple` yang lebih ketat.
3. Isi `news.csv` dengan histori berita pada periode backtest. Kalender MT5 tidak tersedia di tester, dan file Common hanya terbaca oleh agen lokal.
4. Setelah max DD tercapai, EA terkunci sampai akhir backtest. Ini disengaja.
5. Optimasi memakai kriteria **Custom max** (`OnTester` = PF × √trade, dengan penalti DD > 15%). Lakukan walk-forward: optimasi di 70% data, validasi di 30% sisanya.
6. Target minimum sebelum live: PF > 1.25 setelah biaya, expectancy > 0.1R, max DD < 15%, ≥ 1.000 trade, lalu forward test di akun demo ECN minimal 1 bulan.
