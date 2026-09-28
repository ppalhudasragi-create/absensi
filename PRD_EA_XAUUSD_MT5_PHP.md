# PROMPT PRD — Web PHP Control Center untuk EA **Auto Scalping** XAUUSD (MetaTrader 5)

> Salin seluruh isi di bawah garis ini dan berikan ke AI coding assistant / developer.
> Prompt ini sudah berisi arsitektur, logika scalping, manajemen risiko, kualitas eksekusi, skema database, API, dan kriteria penerimaan.

---

## 0. Peran & Instruksi untuk AI

Kamu adalah **senior full-stack engineer + quant developer** yang berpengalaman dengan **PHP 8.2+, MySQL 8, MQL5 (MetaTrader 5)**, dan sistem **high-frequency / scalping** otomatis.
Buatkan sistem lengkap sesuai PRD berikut. Tulis kode yang **production-ready, aman, terdokumentasi**, dan kerjakan **bertahap per milestone** (lihat Bagian 12).
**Larangan:** martingale, grid tanpa batas, averaging-down, posisi tanpa hard stop loss, dan eksploitasi latency/arbitrase broker.

---

## 1. Ringkasan Produk

**Nama:** GoldPilot Scalper — XAUUSD Auto Scalping Control Center
**Tujuan:** Sistem **auto scalping XAUUSD** di MT5 (holding time detik–menit, target kecil, frekuensi tinggi, risiko per trade kecil) yang terdiri dari:
1. **EA Scalper (MQL5)** — mengeksekusi strategi scalping langsung di terminal MT5 dengan latensi serendah mungkin.
2. **EA Bridge (MQL5)** — program terpisah di chart lain yang menangani **semua komunikasi HTTP ke web**, supaya EA Scalper **tidak pernah terblokir** oleh `WebRequest()` (yang bersifat sinkron/blocking).
3. **Web PHP** — pusat kontrol: konfigurasi, lisensi, monitoring real-time, remote command, **analitik kualitas eksekusi** (spread, slippage, latency, biaya), jurnal & notifikasi.

**Prinsip arsitektur utama:**
- **Semua logika entry/exit berjalan di EA Scalper.** Web tidak boleh berada di jalur eksekusi.
- EA Scalper **tidak pernah memanggil `WebRequest()`**. Pertukaran data Scalper ↔ Bridge melalui **file JSON di folder `Common\Files`** (atau `GlobalVariable` untuk flag cepat seperti PAUSE/CLOSE_ALL).
- Jika web / Bridge mati, Scalper tetap berjalan dengan **config cache terakhir** dan semua **hard guard risiko lokal**.
- Scalping sangat sensitif terhadap biaya: **setiap trade harus lolos "cost filter"** (spread + komisi + estimasi slippage) sebelum dieksekusi.

---

## 2. Target Pengguna & Prasyarat Trading

| Peran | Kebutuhan |
|---|---|
| **Admin** | Kelola user, lisensi, preset strategi global, pantau semua akun & kualitas broker |
| **Trader (User)** | Hubungkan akun MT5, atur parameter, pantau posisi, pause/close darurat, lihat laporan |
| **Viewer / Investor** | Hanya melihat performa (read-only) |

**Prasyarat akun (ditampilkan sebagai checklist onboarding di web, dan dicek otomatis oleh EA saat `OnInit`):**
- Akun **ECN / Raw Spread** dengan spread rata-rata XAUUSD ≤ 15–20 point dan komisi jelas.
- Broker **mengizinkan scalping & EA**, `SYMBOL_TRADE_STOPS_LEVEL` kecil (idealnya 0), eksekusi *market*.
- **VPS dekat server broker** (ping ke trade server < 20 ms; EA membaca `TerminalInfoInteger(TERMINAL_PING_LAST)`).
- Leverage cukup (≥ 1:100) agar margin tidak membatasi lot.

---

## 3. Arsitektur Sistem

```
                         MT5 Terminal (VPS)
┌───────────────────────────────────────────────────────────────┐
│  Chart XAUUSD M1                    Chart lain (mis. EURUSD)   │
│  ┌──────────────────────┐   file    ┌──────────────────────┐  │
│  │ GoldPilot_Scalper    │◀────────▶│ GoldPilot_Bridge      │  │
│  │ - sinyal & eksekusi  │ Common\   │ - WebRequest HTTPS   │  │
│  │ - risk guard lokal   │ Files +   │ - heartbeat, config  │  │
│  │ - TANPA WebRequest   │ GlobalVar │ - kirim trade/event  │  │
│  └──────────────────────┘           └──────────┬───────────┘  │
└────────────────────────────────────────────────┼──────────────┘
                                                 │ HTTPS JSON + HMAC
                                     ┌───────────▼────────────┐
                                     │  PHP API (/api/v1)     │
                                     │  Laravel 11 + MySQL 8  │
                                     │  Scheduler + Queue     │
                                     └───────────┬────────────┘
                                                 │ AJAX / SSE
                                     ┌───────────▼────────────┐
                                     │ Dashboard Web + Telegram│
                                     └────────────────────────┘
```

**Stack:**
- Backend: **PHP 8.2+, Laravel 11** (MVC), Composer.
- Database: **MySQL 8 / MariaDB 10.6+**; Redis opsional untuk cache heartbeat & rate limit.
- Frontend: Blade + **Tailwind CSS** + **Alpine.js**, grafik **Chart.js** / **Lightweight Charts (TradingView)**.
- Realtime: **Server-Sent Events** atau polling AJAX 3 detik.
- Notifikasi: **Telegram Bot API**, Email (SMTP).
- EA: **MQL5** (MT5 build terbaru).

---

## 4. LOGIKA SCALPING EA (inti sistem)

Strategi default: **"Momentum Scalping searah micro-trend + Volatility Squeeze Breakout"**, timeframe eksekusi **M1**, bias **M5/M15**.
Semua angka adalah **parameter default yang bisa diubah dari web**.

### 4.1 Filter Kondisi Pasar (semua harus lolos sebelum mencari entry)

| Filter | Logika default |
|---|---|
| **Sesi** | Hanya **London open (07:00–10:30 GMT)** dan **overlap London–NY (12:30–16:30 GMT)**: likuiditas tertinggi, spread tersempit. Sesi Asia default **OFF**. |
| **Spread absolut** | Skip jika spread saat ini > `MaxSpreadPoints` (default **20 point** = $0.20). |
| **Spread relatif** | Skip jika spread > **15% dari jarak SL** (scalping dengan SL kecil sangat terpengaruh spread). |
| **Spread spike** | Skip jika spread saat ini > **2× rata-rata spread 200 tick terakhir** (ring buffer di EA). |
| **Cost filter** | Skip jika `TP_distance < 3 × (spread + komisi_per_lot_dalam_harga + AvgSlippage)`. |
| **Volatilitas** | ATR(14) M1 di antara **$0.40 – $2.50**. Terlalu sepi → sinyal palsu; terlalu liar → slippage besar. |
| **Aktivitas tick** | Jumlah tick 60 detik terakhir ≥ `MinTicksPerMinute` (default 40) → pasar likuid. |
| **Berita** | Tidak buka posisi **15 menit sebelum s/d 30 menit sesudah** berita high-impact USD (NFP, CPI, FOMC, PCE, GDP, suku bunga, pidato Ketua Fed). Posisi terbuka ditutup **2 menit sebelum** berita (default ON). |
| **Rollover** | Tidak trading 23:30–01:30 waktu server; tidak buka posisi Jumat > 19:00 GMT. |
| **Latency** | Skip jika `TERMINAL_PING_LAST` > `MaxPingMs` (default 50 ms). |
| **Risk guard** | Daily loss, max DD, consecutive loss, max trade per hari/jam belum tercapai (Bagian 5). |

### 4.2 Bias Micro-Trend (M5 & M15)

- **Bullish** jika: `EMA20(M5) > EMA50(M5)` **dan** slope `EMA20(M5)` naik (EMA20[1] > EMA20[3]) **dan** `Close(M15) > EMA50(M15)`.
- **Bearish** jika kebalikannya.
- **Netral** → hanya Setup B (squeeze breakout) dengan konfirmasi momentum lebih ketat, atau tidak trading (parameter).
- Tambahan: harga di atas **VWAP harian** untuk BUY, di bawah VWAP untuk SELL (VWAP dihitung dari tick volume sejak 00:00 GMT).

### 4.3 Setup A — Momentum Pullback (M1)

**BUY** (bias Bullish):
1. Harga pullback ke zona **EMA9–EMA21 M1** (low candle ≤ EMA9 dan close ≥ EMA21).
2. **RSI(7) M1** turun ke zona 35–50 lalu kembali naik (reset momentum, bukan pembalikan trend).
3. **Konfirmasi**: candle M1 terakhir yang close adalah bullish dengan body ≥ 50% range **dan** close di atas high candle sebelumnya.
4. **Tick volume** candle konfirmasi ≥ 1.2× rata-rata 20 candle.
5. Entry: **market order di tick pertama candle berikutnya**. Sinyal kedaluwarsa jika harga sudah bergerak > 0.3×ATR dari close konfirmasi (hindari mengejar harga).

**SELL**: cermin dari BUY.

### 4.4 Setup B — Volatility Squeeze Breakout (M1)

1. Deteksi **squeeze**: Bollinger Band(20,2) width M1 berada di **20% persentil terendah dari 120 candle terakhir** selama ≥ 5 candle.
2. Tentukan `RangeHigh` / `RangeLow` dari candle squeeze.
3. Entry **market** saat candle M1 **close** di luar range dengan:
   - body ≥ 60% range candle,
   - tick volume ≥ 1.5× rata-rata 20 candle,
   - arah searah bias M5 (jika bias netral → butuh volume ≥ 2×).
4. Batal jika breakout candle > 1.5×ATR (sudah terlalu jauh; risiko retrace).

### 4.5 Setup C — VWAP / Bollinger Mean Reversion (opsional, default **OFF**)

Hanya untuk kondisi range (ADX(14) M5 < 18): entry kontra saat harga menyentuh BB(20, 2.5) M1 + RSI(7) ekstrem (< 20 / > 80) + candle reversal, target ke middle band / VWAP. Risiko lebih tinggi → default nonaktif, harus diaktifkan manual.

### 4.6 Stop Loss & Take Profit (ATR-based, disesuaikan scalping)

- **Hard SL wajib dikirim ke server** bersama order (tidak boleh hanya "virtual/hidden SL").
- **SL** = `max(1.2 × ATR(14,M1), jarak ke swing low/high 5 candle terakhir + spread)`, dibatasi **MinSL $0.80** dan **MaxSL $3.50**.
- **TP** = **1.2R** (default). Opsi mode:
  - *Single TP*: tutup penuh di 1.2R.
  - *Partial*: tutup **60% di 0.8R**, SL sisa → breakeven + biaya, sisa trailing.
- **Breakeven** otomatis saat profit mencapai **0.6R** (SL → entry + spread + komisi).
- **Trailing**: setelah 1R, trailing **0.8×ATR(M1)** dari harga tertinggi/terendah, diupdate maksimal 1× per detik (hindari spam modify ke broker).
- **Stealth TP opsional**: TP bisa dikelola lokal (tidak dikirim ke broker) untuk menghindari hunting, tetapi **SL tetap harus hard**.

### 4.7 Manajemen Waktu (kunci scalping)

- **Max holding time**: 20 menit → tutup di harga pasar.
- **Stale trade exit**: jika setelah **5 menit** profit < 0.2R → tutup (momentum hilang).
- **Early exit momentum**: tutup jika candle M1 close berlawanan kuat (body ≥ 70% range melawan posisi) sebelum mencapai BE.
- **Cooldown**: 3 menit setelah trade ditutup; **10 menit** setelah loss.
- Sinyal baru hanya dihitung **saat candle M1 baru terbentuk**; manajemen posisi (BE, trailing, time exit) dijalankan **setiap tick**.

### 4.8 Position Sizing

```
RiskAmount   = Equity × RiskPercent / 100            (default 0.5%, maksimum 1.5%)
SL_Distance  = |Entry − SL| + Spread                  (dalam harga)
TickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS)
TickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)
CommissionPerLot (dari config, dalam mata uang akun)
Lot          = RiskAmount / (SL_Distance / TickSize × TickValue + CommissionPerLot)
Lot          = NormalizeLot(Lot, VOLUME_MIN, VOLUME_MAX, VOLUME_STEP)
```
- Jika lot < `VOLUME_MIN` → **skip trade**, jangan paksa lot minimum.
- `MaxLotCap` absolut (default 5 lot) sebagai pengaman.
- Cek `OrderCalcMargin()` dan pastikan margin level setelah entry > 500%.

### 4.9 Aturan Posisi

- **Maksimal 1 posisi terbuka** (default) — scalping fokus satu trade berkualitas.
- Tidak boleh posisi berlawanan arah (no hedging).
- **Max trade per jam: 6**, **max trade per hari: 25**.
- Magic Number unik per akun/preset, komentar order `GPS|setup|signal_id`.

### 4.10 Eksekusi Cepat & Aman

- Gunakan `CTrade` dengan `SetAsyncMode(false)` (default) dan `SetDeviationInPoints(MaxSlippagePoints)` (default 10).
- Hitung semua indikator dengan **handle yang dibuat sekali di `OnInit`** (bukan dibuat ulang per tick); gunakan `CopyBuffer` minimal.
- Catat untuk setiap order: **harga request vs harga fill (slippage)**, **waktu eksekusi (ms)** via `GetMicrosecondCount()`, spread saat entry.
- Retry maksimal **2×** untuk requote/price changed/off quotes; jika gagal, batalkan sinyal (jangan kejar harga).
- Validasi `STOPS_LEVEL` & `FREEZE_LEVEL` sebelum set/modify SL/TP.
- Deteksi filling mode (`FOK`/`IOC`/`RETURN`) & nama simbol otomatis (`XAUUSD`, `XAUUSDm`, `XAUUSD.r`, `GOLD`, ...).
- **Execution quality guard**: jika rata-rata slippage 20 trade terakhir > `MaxAvgSlippage` (default 5 point) atau eksekusi rata-rata > 500 ms → **auto-pause** + notifikasi (tanda broker/VPS bermasalah).

---

## 5. Manajemen Risiko Global (Hard Guard di EA)

| Guard | Default | Aksi saat tercapai |
|---|---|---|
| **Daily Loss Limit** | 2% dari equity awal hari | Tutup semua, stop trading sampai hari berikutnya |
| **Daily Profit Target** (opsional) | 3% | Stop buka posisi baru |
| **Profit Giveback Protection** | Jika profit harian turun 50% dari puncak harian | Stop trading hari itu |
| **Max Drawdown Equity** | 8% dari peak equity | Tutup semua + **kunci EA** (unlock manual dari web + 2FA) |
| **Consecutive Loss** | 3 loss beruntun | Pause 60 menit; 5 loss → stop hari itu |
| **Max Trade** | 6 per jam, 25 per hari | Stop buka posisi baru |
| **Execution Quality** | Slippage/latency di atas batas | Auto-pause |
| **Bridge / Web Offline** | > 5 menit | Tetap kelola posisi; **tidak buka posisi baru** jika > 30 menit (opsional) |

Semua event guard ditulis ke file outbox → dikirim Bridge ke web → notifikasi Telegram.

---

## 6. Protokol Komunikasi

### 6.1 Scalper ↔ Bridge (lokal, di terminal yang sama)
- Folder `Common\Files\GoldPilot\<account>\`:
  - `config.json` (ditulis Bridge, dibaca Scalper tiap 5 detik via cek `config_version`).
  - `outbox/*.json` (ditulis Scalper: trade, event, snapshot; dibaca & dihapus Bridge setelah sukses terkirim).
  - `commands.json` (ditulis Bridge; Scalper menulis `acks.json`).
- Flag darurat via `GlobalVariableSet("GPS_<acc>_PAUSE")`, `GPS_<acc>_CLOSEALL` → dicek Scalper **setiap tick** (respon < 1 detik).
- Penulisan file atomik: tulis ke `.tmp` lalu rename.

### 6.2 Bridge ↔ Web (REST API)
**Base URL:** `https://domain.com/api/v1` — **wajib HTTPS**, URL didaftarkan di *Tools → Options → Expert Advisors → Allow WebRequest*.

**Autentikasi:** header `X-License-Key`, `X-Account-Number`, `X-Timestamp`, `X-Signature = HMAC-SHA256(secret, timestamp + body)`. Tolak jika selisih waktu > 60 detik. Lisensi terikat ke **nomor akun + server broker**.

| Endpoint | Method | Interval | Fungsi |
|---|---|---|---|
| `/ea/handshake` | POST | Saat Bridge start | Validasi lisensi, info akun/broker/versi, spec simbol (stops level, komisi), config awal |
| `/ea/heartbeat` | POST | 5 detik | Balance, equity, floating, posisi, spread, ping, status; **terima command & config_version** |
| `/ea/config` | GET | Saat `config_version` berubah | Parameter strategi terbaru |
| `/ea/trades/batch` | POST | Saat ada outbox (maks 50/batch) | Detail trade: ticket, setup, lot, harga request & fill, slippage, exec_ms, spread entry, SL, TP, MAE, MFE, profit, komisi, alasan exit |
| `/ea/events/batch` | POST | Saat ada outbox | Guard triggered, error order, news block, auto-pause |
| `/ea/ticks-stats` | POST | 1 menit | Statistik spread (min/avg/max), jumlah tick, ping → untuk analitik kualitas broker |
| `/ea/commands/{id}/ack` | POST | Setelah command dieksekusi | Konfirmasi hasil |
| `/ea/news` | GET | 30 menit | Kalender berita high-impact 7 hari ke depan (UTC) |

**Remote Commands:** `PAUSE`, `RESUME`, `CLOSE_ALL`, `CLOSE_TICKET`, `MOVE_TO_BE`, `DISABLE_SETUP`, `UNLOCK_DD_LOCK`, `RELOAD_CONFIG`.
Setiap command punya `id`, `expires_at` (default 60 detik), dan **idempoten**.

**Contoh response heartbeat:**
```json
{
  "status": "ok",
  "server_time": 1759046400,
  "config_version": 12,
  "trading_enabled": true,
  "commands": [
    {"id": 881, "type": "CLOSE_ALL", "payload": {}, "expires_at": 1759046460}
  ]
}
```
Rate limit: 60 request/menit per lisensi.

---

## 7. Fitur Web (PHP)

### 7.1 Autentikasi & Keamanan
- Register/Login, **2FA TOTP**, reset password, verifikasi email, role Admin/Trader/Viewer.
- Password `argon2id`, CSRF, escaping XSS, ORM/prepared statement, rate limit login, **audit log** semua aksi penting.

### 7.2 Dashboard Real-time
- Kartu: Balance, Equity, Floating, Profit hari ini / minggu / bulan, DD saat ini vs limit, **jumlah trade hari ini vs limit**, win rate hari ini, status EA (Online / Offline / Paused / Locked / Auto-paused), last heartbeat, **spread live**, **ping**.
- Posisi terbuka: ticket, arah, lot, entry, SL, TP, R saat ini, **durasi (detik)**, P/L + tombol **Close / BE**.
- Feed trade terakhir (live, auto-update) dengan setup & alasan exit.
- Grafik equity intraday, P/L per jam.
- Countdown berita berikutnya & status filter aktif (sesi, spread, news).
- Tombol darurat: **PAUSE** & **CLOSE ALL**.

### 7.3 Manajemen Akun MT5
- Banyak akun MT5 per user (nomor akun, server, real/demo, broker, komisi per lot).
- **Checklist onboarding scalping** (ECN, ping VPS, spread rata-rata, stops level) diisi otomatis dari handshake.

### 7.4 Konfigurasi Strategi (Preset)
- Form terkelompok: Sesi, Filter Spread/Cost, Volatilitas, Setup A/B/C, SL/TP, Time Exit, Risk, Guard, Notifikasi.
- Validasi server-side batas aman (RiskPercent 0.1–1.5, MaxSL ≤ $5, MaxSpread ≤ 40, dll.).
- Preset bawaan: **Safe Scalp (0.25%)**, **Standard (0.5%)**, **Active (1%)**.
- **Versioning config** + rollback + siapa mengubah.
- **Export `.set`** untuk backtest di Strategy Tester.

### 7.5 Analitik Kualitas Eksekusi (khusus scalping)
- Rata-rata / distribusi **slippage** (positif & negatif), **waktu eksekusi (ms)**, **spread saat entry**.
- **Total biaya** (spread + komisi + swap) vs gross profit → "cost ratio". Peringatan jika biaya > 40% gross profit.
- Spread per jam (heatmap) → rekomendasi jam trading terbaik.
- Perbandingan kualitas **antar broker/akun**.

### 7.6 Jurnal & Analitik Performa
- Riwayat trade: filter tanggal, setup, arah, sesi, alasan exit, durasi.
- Statistik: Net profit, Profit Factor, Win rate, Avg R, **Expectancy per trade (setelah biaya)**, Max DD, Sharpe, Recovery Factor, **avg holding time**, trade/hari, consecutive W/L.
- **MAE / MFE** analysis → bantu tuning SL/TP.
- Breakdown per setup, sesi, jam, hari → heatmap. Kalender P/L. Export CSV / PDF.
- Import laporan backtest MT5 untuk perbandingan **backtest vs live**.

### 7.7 News Calendar
- Cron 1 jam ambil kalender ekonomi (sumber dapat dikonfigurasi, mis. feed Forex Factory), konversi ke UTC, simpan.
- Admin bisa tambah / nonaktifkan event manual.

### 7.8 Notifikasi
- **Telegram** per user: guard triggered, auto-pause, EA offline > 2 menit, ringkasan per sesi & harian. Notifikasi per-trade **opsional** (default ringkasan saja karena frekuensi tinggi).
- Email untuk event kritis (DD lock, lisensi kedaluwarsa).

### 7.9 Lisensi & Admin
- Generate license key, masa berlaku, maks akun, status; bind ke akun + server; download EA Scalper & Bridge (.ex5) per versi.
- Monitoring semua EA: online/offline, versi, error rate, latency heartbeat, kualitas eksekusi.

---

## 8. Skema Database (MySQL)

```sql
users(id, name, email, password, role ENUM('admin','trader','viewer'), totp_secret, telegram_chat_id, timezone, created_at, updated_at)
licenses(id, user_id, license_key UNIQUE, secret_hmac, max_accounts, expires_at, status, created_at)
mt5_accounts(id, user_id, license_id, account_number, broker_server, account_type ENUM('real','demo'),
             currency, leverage, commission_per_lot, stops_level, ea_version,
             status ENUM('online','offline','paused','locked','auto_paused'),
             last_heartbeat_at, last_ping_ms, preset_id, created_at)
presets(id, user_id NULL, name, is_system BOOL, params JSON, version INT, created_at, updated_at)
preset_versions(id, preset_id, version, params JSON, changed_by, created_at)
account_snapshots(id, mt5_account_id, balance, equity, margin, free_margin, floating_pl,
                  open_positions, spread, ping_ms, created_at)
trades(id, mt5_account_id, signal_id, ticket, position_id, symbol, type ENUM('buy','sell'),
       setup ENUM('A','B','C','manual'), lots, request_price, open_price, close_price,
       slippage_points, exec_ms, spread_at_entry, sl, tp, open_time, close_time, duration_sec,
       mae, mfe, profit, commission, swap, r_multiple,
       exit_reason ENUM('tp','partial','trail','sl','be','time','stale','early','guard','news','manual','friday'),
       status ENUM('open','closed'), UNIQUE(mt5_account_id, position_id))
trade_events(id, trade_id, event ENUM('open','partial','modify','close'), payload JSON, created_at)
spread_stats(id, mt5_account_id, minute_at, spread_min, spread_avg, spread_max, ticks, ping_ms)
commands(id, mt5_account_id, type, payload JSON, status ENUM('pending','sent','done','failed','expired'),
         created_by, expires_at, acked_at, result JSON, created_at)
ea_events(id, mt5_account_id, level ENUM('info','warning','critical'), code, message, payload JSON, created_at)
news_events(id, event_time_utc, currency, impact ENUM('low','medium','high'), title, is_active, source)
daily_stats(id, mt5_account_id, date, start_equity, end_equity, profit, gross_profit, total_cost,
            trades, wins, losses, max_dd, avg_slippage, avg_exec_ms)
audit_logs(id, user_id, action, target_type, target_id, before JSON, after JSON, ip, created_at)
```
Index: `(mt5_account_id, created_at)` pada snapshot/event/spread_stats, `(mt5_account_id, close_time)` pada trades.
Retensi: snapshot & spread_stats detail 14 hari, lalu agregasi per 15 menit.

---

## 9. Struktur Kode EA (MQL5)

```
GoldPilot_Scalper.mq5         // OnInit, OnTick, OnTimer(1s), OnTradeTransaction, OnDeinit — TANPA WebRequest
GoldPilot_Bridge.mq5          // OnTimer: heartbeat, config, kirim outbox, commands, news
Include/GoldPilot/
  Config.mqh                  // struct parameter, load config.json + validasi batas
  FileBus.mqh                 // tulis/baca JSON atomik, outbox queue, GlobalVariable flags
  Api.mqh                     // (Bridge) WebRequest, HMAC-SHA256, retry, timeout 3s
  Json.mqh                    // parser/serializer JSON ringan
  Session.mqh                 // konversi server time ↔ GMT (termasuk DST), filter sesi/rollover
  NewsFilter.mqh
  MarketState.mqh             // ring buffer spread, tick rate, ATR, VWAP, BB width percentile
  Signals.mqh                 // bias M5/M15, Setup A, B, C
  CostFilter.mqh              // spread/komisi/slippage vs TP
  RiskManager.mqh             // lot sizing, daily/DD/consecutive/trade-count guard
  TradeManager.mqh            // eksekusi, BE, partial, trailing (throttled), time/stale/early exit
  ExecQuality.mqh             // ukur slippage, exec ms, auto-pause
  Commands.mqh                // eksekusi command idempoten
  Panel.mqh                   // panel info di chart
```
- `WebRequest` **tidak bisa dipakai di Strategy Tester** → Scalper harus bisa jalan penuh dengan **input parameter lokal** untuk backtest.
- Panel chart menampilkan: status, bias, sesi, spread (live/avg), ping, trade hari ini, P/L hari ini, guard aktif, alasan sinyal terakhir ditolak.

---

## 10. Kebutuhan Non-Fungsional

- **Latensi:** proses `OnTick` Scalper < 5 ms rata-rata (ukur & tampilkan); tidak ada operasi blocking di Scalper.
- **Keamanan:** HTTPS, HMAC, 2FA, secret di `.env`, tidak menyimpan password MT5 di web.
- **Performa web:** heartbeat < 100 ms; kapasitas 500 akun × heartbeat 5 detik (≈100 req/s) di VPS 4 vCPU / 8 GB (gunakan Redis untuk status live).
- **Keandalan:** ingest trade & command idempoten; outbox tidak hilang saat terminal restart.
- **Zona waktu:** simpan UTC, tampilkan sesuai timezone user (default Asia/Jakarta); EA menangani DST broker.
- **Deployment:** Docker Compose (nginx + php-fpm + mysql + redis + scheduler/queue) + panduan VPS.
- **Bahasa UI:** Bahasa Indonesia (siap i18n English).

---

## 11. Validasi Strategi (wajib sebelum live)

1. **Backtest** mode *"Every tick based on real ticks"* dengan **spread variabel asli** dan komisi broker, data minimal **2 tahun**. Mode OHLC/"1 minute OHLC" **tidak valid** untuk scalping.
2. Uji ulang dengan **spread +50%** dan **delay eksekusi** (Tester: *Random delay*) → strategi harus tetap profit.
3. **Walk-forward**: optimasi 70% data, uji 30% out-of-sample; parameter harus stabil (bukan puncak tunggal).
4. **Monte Carlo** urutan trade & slippage acak → estimasi DD terburuk.
5. Target minimum: Profit Factor > 1.25 **setelah biaya**, expectancy > 0.1R, Max DD < 15%, ≥ 1.000 trade.
6. **Forward test demo ECN minimal 1 bulan** di VPS yang sama dengan yang akan dipakai live, lalu akun real kecil / cent.
7. Web membandingkan **backtest vs live**: win rate, avg R, slippage, biaya per trade.

---

## 12. Milestone Pengerjaan

| # | Milestone | Output |
|---|---|---|
| M1 | Setup Laravel, auth, role, 2FA, lisensi, akun MT5 | Web bisa login & generate lisensi |
| M2 | API EA (handshake, heartbeat, config, batch trades/events, ticks-stats, commands) + HMAC + test | OpenAPI + unit/feature test |
| M3 | EA Bridge + FileBus + Scalper skeleton (panel, config, flag darurat) | EA online di web, PAUSE/CLOSE ALL berjalan |
| M4 | Scalper: MarketState, filter, cost filter, Setup A/B/C, sizing, SL/TP, time exit, risk guard, exec quality | EA bisa di-backtest real ticks dengan input lokal |
| M5 | Dashboard real-time, posisi, tombol darurat, preset + versioning + export .set | Kontrol penuh dari web |
| M6 | Analitik kualitas eksekusi, jurnal, MAE/MFE, heatmap, news calendar, export | Laporan lengkap |
| M7 | Telegram & email, admin monitoring, audit log | Notifikasi berjalan |
| M8 | Hardening, Docker, dokumentasi deploy & user guide | Siap produksi |

---

## 13. Kriteria Penerimaan (Acceptance Criteria)

- [ ] Scalper tidak pernah memanggil `WebRequest`; web mati tidak memperlambat `OnTick`.
- [ ] PAUSE / CLOSE ALL dari web dieksekusi ≤ 10 detik; flag GlobalVariable direspons ≤ 1 detik.
- [ ] Tidak ada order tanpa hard SL.
- [ ] Trade ditolak jika spread / cost filter / ping / news / sesi tidak lolos, dan alasannya tercatat.
- [ ] Lot tidak pernah membuat risiko (termasuk spread + komisi) > RiskPercent (toleransi pembulatan lot step).
- [ ] Daily loss, profit giveback, max DD, consecutive loss, dan max trade per jam/hari bekerja sesuai aturan + notifikasi Telegram.
- [ ] Time exit (20 menit) & stale exit (5 menit) berjalan tepat waktu.
- [ ] Slippage & waktu eksekusi setiap trade tercatat; auto-pause aktif saat melewati batas.
- [ ] Trade tidak tercatat ganda; outbox yang tertunda terkirim setelah web pulih.
- [ ] Hasil backtest dapat direproduksi (sinyal hanya pada candle M1 close).
- [ ] Endpoint: signature salah → 401, timestamp kedaluwarsa → 401, rate limit → 429.

---

## 14. Disclaimer (tampilkan di web)

Scalping XAUUSD dengan leverage berisiko sangat tinggi dan sangat bergantung pada kualitas broker, spread, dan latensi. Hasil backtest tidak menjamin hasil live. Sistem ini adalah alat bantu; pengguna bertanggung jawab penuh atas penggunaan dan dana mereka.
