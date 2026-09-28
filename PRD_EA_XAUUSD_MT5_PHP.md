# PROMPT PRD — Web PHP Control Center untuk EA Trading XAUUSD (MetaTrader 5)

> Salin seluruh isi di bawah garis ini dan berikan ke AI coding assistant / developer.
> Prompt ini sudah berisi arsitektur, logika strategi, manajemen risiko, skema database, API, dan kriteria penerimaan.

---

## 0. Peran & Instruksi untuk AI

Kamu adalah **senior full-stack engineer + quant developer** yang berpengalaman dengan **PHP 8.2+, MySQL 8, MQL5 (MetaTrader 5)**, dan sistem trading otomatis.
Buatkan sistem lengkap sesuai PRD berikut. Tulis kode yang **production-ready, aman, terdokumentasi**, dan kerjakan **bertahap per milestone** (lihat Bagian 12). Jangan gunakan strategi martingale, grid tanpa batas, atau averaging-down tanpa stop loss.

---

## 1. Ringkasan Produk

**Nama:** GoldPilot — XAUUSD EA Control Center
**Tujuan:** Sistem trading otomatis XAUUSD di MT5 yang terdiri dari:
1. **EA (Expert Advisor) MQL5** — mengeksekusi strategi langsung di terminal MT5 (latensi rendah, tetap jalan walau web down).
2. **Web PHP** — pusat kontrol: konfigurasi parameter, lisensi, monitoring real-time, remote command, jurnal & analitik performa, notifikasi.

**Prinsip arsitektur utama:**
- **Logika entry/exit berjalan di EA**, bukan di web. Web tidak boleh menjadi single point of failure untuk eksekusi.
- Web adalah **"otak konfigurasi & pengawasan"**; EA adalah **"tangan eksekusi"**.
- Komunikasi **EA → Web** memakai `WebRequest()` MQL5 via HTTPS (polling), karena MT5 tidak bisa menerima koneksi masuk.
- Jika web tidak bisa dihubungi, EA memakai **konfigurasi terakhir yang di-cache** dan tetap menjalankan proteksi risiko lokal.

---

## 2. Target Pengguna

| Peran | Kebutuhan |
|---|---|
| **Admin** | Kelola user, lisensi, preset strategi global, lihat semua akun |
| **Trader (User)** | Hubungkan akun MT5, atur parameter, pantau posisi, pause/close darurat, lihat laporan |
| **Viewer / Investor** | Hanya melihat performa (read-only) |

---

## 3. Arsitektur Sistem

```
┌──────────────────┐   HTTPS (WebRequest, JSON, HMAC)   ┌────────────────────────┐
│  MT5 Terminal    │ ─────────────────────────────────▶ │  PHP API (/api/v1)     │
│  EA GoldPilot    │ ◀───────────────────────────────── │  - auth lisensi        │
│  (MQL5)          │   config, commands, news events    │  - config / command    │
└──────────────────┘                                    │  - ingest trade/equity │
        │ cache lokal (file JSON di MQL5/Files)         └──────────┬─────────────┘
        ▼                                                          │
  Eksekusi & proteksi risiko lokal                        ┌────────▼─────────┐
                                                          │  MySQL 8          │
┌──────────────────┐                                      └────────┬─────────┘
│ Dashboard Web    │ ◀── AJAX/SSE ── PHP (MVC) ◀───────────────────┘
│ (Browser)        │                    │
└──────────────────┘                    ├─ Cron: news calendar, laporan harian, cleanup
                                        └─ Notifikasi: Telegram Bot / Email
```

**Stack:**
- Backend: **PHP 8.2+**, arsitektur MVC (boleh Laravel 11 **atau** native PHP dengan struktur MVC + Composer). Default: **Laravel 11**.
- Database: **MySQL 8 / MariaDB 10.6+**
- Frontend: Blade + **Tailwind CSS** + **Alpine.js**, grafik dengan **Chart.js** / **Lightweight Charts (TradingView)**
- Realtime: polling AJAX 3–5 detik atau **Server-Sent Events**
- Queue/Cron: Laravel Scheduler + Queue (database driver)
- Notifikasi: **Telegram Bot API**, Email (SMTP)
- EA: **MQL5** (MT5 build terbaru)

---

## 4. LOGIKA STRATEGI EA (inti sistem)

Strategi default: **"Trend-Pullback + Session Breakout, ATR-based, Multi-Timeframe"**.
Semua angka di bawah adalah **parameter default yang bisa diubah dari web**.

### 4.1 Filter Kondisi Pasar (semua harus lolos sebelum mencari entry)

| Filter | Logika default |
|---|---|
| **Sesi** | Hanya trading saat **London (08:00–11:00 GMT)** dan **New York (13:00–17:00 GMT)**. Hindari sesi Asia (range sempit, spread lebar). Waktu dihitung dari offset server broker → GMT. |
| **Spread** | Skip jika spread > `MaxSpreadPoints` (default **35 point** = $0.35). |
| **Volatilitas** | ATR(14) M15 harus di antara `MinATR` dan `MaxATR` (default $1.5 – $8.0). Terlalu sepi = choppy; terlalu liar = slippage. |
| **Berita (News Filter)** | Tidak buka posisi baru **30 menit sebelum s/d 30 menit sesudah** berita high-impact USD (NFP, CPI, FOMC, suku bunga, PCE, GDP). Opsional: tutup/kencangkan SL posisi terbuka sebelum berita. Data berita disediakan web (Bagian 7.6). |
| **Hari** | Tidak buka posisi baru Jumat setelah 18:00 GMT; opsional tidak trading Senin sebelum 07:00 GMT (gap). |
| **Rollover** | Tidak buka posisi 23:45–01:15 waktu server (spread melebar). |
| **Batas Risiko** | Daily loss limit, max drawdown, max trade per hari belum tercapai (Bagian 5). |

### 4.2 Penentuan Bias Trend (Higher Timeframe — H1 & H4)

- **Bullish** jika: `EMA50(H1) > EMA200(H1)` **dan** `Close(H1) > EMA50(H1)` **dan** `EMA50(H4)` slope naik (EMA50[1] > EMA50[4]).
- **Bearish** jika kebalikannya.
- **Netral** → tidak ada setup Trend-Pullback (setup Breakout masih boleh bila diaktifkan).
- Filter kekuatan trend: **ADX(14) H1 ≥ 20**.

### 4.3 Setup A — Trend Pullback (timeframe eksekusi M15)

**BUY** (bias Bullish):
1. Harga pullback menyentuh zona **EMA21–EMA50 M15** (low candle ≤ EMA21 + 0.2×ATR).
2. **RSI(14) M15** sempat turun ke 40–50 lalu naik kembali (tidak oversold ekstrem < 30 = trend mungkin patah).
3. **Konfirmasi candle**: candle M15 terakhir yang sudah close adalah bullish engulfing / pin bar bullish / close di atas high candle sebelumnya.
4. Entry: **market order di open candle berikutnya** (bukan di tengah candle → hindari repaint).
**SELL**: cermin dari BUY.

### 4.4 Setup B — Session Breakout (opsional, default ON)

1. Hitung **range Asia** (00:00–07:00 GMT): `AsiaHigh`, `AsiaLow`.
2. Valid hanya jika lebar range antara **0.8×ATR(14,H1)** dan **2.5×ATR(14,H1)**.
3. Pasang **Buy Stop** di `AsiaHigh + buffer` dan **Sell Stop** di `AsiaLow − buffer` (buffer = 0.1×ATR M15 + spread).
4. Hanya arah yang **searah bias H1** yang dipasang (jika bias netral, pasang dua-duanya → OCO: satu tereksekusi, yang lain dihapus).
5. Pending order kedaluwarsa pukul 11:00 GMT.

### 4.5 Stop Loss & Take Profit (ATR-based, bukan fixed pip)

- **SL** = `max(1.5 × ATR(14,M15), jarak ke swing low/high terakhir + buffer)`, dibatasi `MinSL` $3 dan `MaxSL` $15.
- **TP1** = 1.0R → **tutup 50%** posisi, pindahkan SL ke **breakeven + komisi/spread**.
- **TP2** = 2.0R → tutup 30% lagi.
- **Sisa 20%** → dikelola **trailing stop ATR (Chandelier: 2×ATR dari high/low tertinggi sejak entry)**.
- Jika partial close tidak memungkinkan (lot terlalu kecil), pakai TP tunggal 2R + trailing setelah 1R.

### 4.6 Position Sizing

```
RiskAmount   = Equity × RiskPercent / 100           (default 1%, maksimum yang diizinkan 3%)
SL_Distance  = |Entry − SL|                          (dalam harga)
TickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)
TickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)
Lot          = RiskAmount / (SL_Distance / TickSize × TickValue)
Lot          = NormalizeLot(Lot, VOLUME_MIN, VOLUME_MAX, VOLUME_STEP)
```
- Wajib dinormalisasi ke `SYMBOL_VOLUME_STEP`; jika < `VOLUME_MIN` → **skip trade** (jangan paksa lot minimum yang melebihi risiko).
- Cek `OrderCalcMargin()` → pastikan free margin cukup (sisakan ≥ 50% margin level buffer).
- Mode alternatif: **Fixed Lot** (untuk testing).

### 4.7 Manajemen Posisi

- Maksimal **1 posisi per arah** dan **maksimal 2 posisi terbuka** total (default).
- **Cooldown** 30 menit setelah posisi ditutup loss.
- **Time exit**: tutup posisi yang belum mencapai 0.5R setelah 8 jam (trade "mati").
- Tutup semua posisi Jumat 20:30 GMT (opsional, default ON) → hindari gap weekend.
- Setiap order memakai **Magic Number** unik per akun/preset dan **komentar** `GP|setup|id`.

### 4.8 Eksekusi yang Aman

- Pakai `CTrade` dengan `SetDeviationInPoints(MaxSlippage)` dan cek `ResultRetcode()`.
- **Retry maksimal 3×** untuk retcode requote/price changed/off quotes, dengan `RefreshRates`.
- Validasi `SYMBOL_TRADE_STOPS_LEVEL` & `SYMBOL_TRADE_FREEZE_LEVEL` sebelum set/modify SL/TP.
- Deteksi filling mode otomatis (`FOK`/`IOC`/`RETURN`) sesuai broker.
- Deteksi nama simbol otomatis: `XAUUSD`, `XAUUSD.m`, `XAUUSDm`, `GOLD`, dll. (parameter `SymbolOverride`).
- Semua logika sinyal dihitung **hanya saat candle baru terbentuk** (`iTime` berubah) → hemat CPU, hasil backtest = live. Manajemen posisi (trailing/BE) dijalankan tiap tick.

---

## 5. Manajemen Risiko Global (Hard Guard di EA — tidak bisa dimatikan user biasa)

| Guard | Default | Aksi saat tercapai |
|---|---|---|
| **Daily Loss Limit** | 3% dari equity awal hari | Tutup semua posisi, stop trading sampai hari berikutnya |
| **Daily Profit Target** (opsional) | 4% | Stop buka posisi baru hari itu |
| **Max Drawdown Equity** | 10% dari peak equity | Tutup semua + **kunci EA** (harus di-unlock manual dari web) |
| **Max Consecutive Loss** | 3 | Pause 4 jam |
| **Max Trade per Hari** | 4 | Stop buka posisi baru |
| **Equity Stop Mengambang** | Floating loss > 2% | Tutup posisi dengan loss terbesar |
| **Koneksi Web Hilang** | > 15 menit | Tetap jalan dengan config cache; **tidak buka posisi baru** jika > 60 menit (opsional) |

Semua event guard **dikirim ke web** dan memicu notifikasi Telegram.

---

## 6. Protokol Komunikasi EA ↔ Web (REST API)

**Base URL:** `https://domain.com/api/v1` — **wajib HTTPS**. URL harus ditambahkan user ke *Tools → Options → Expert Advisors → Allow WebRequest*.

**Autentikasi:**
- Header `X-License-Key`, `X-Account-Number`, `X-Timestamp`, `X-Signature`.
- `X-Signature = HMAC-SHA256(secret, timestamp + body)`. Tolak request jika selisih timestamp > 60 detik (anti-replay).
- Lisensi terikat ke **nomor akun MT5 + server broker**.

| Endpoint | Method | Interval | Fungsi |
|---|---|---|---|
| `/ea/handshake` | POST | Saat `OnInit` | Validasi lisensi, kirim info akun/broker/versi EA, terima config awal |
| `/ea/heartbeat` | POST | 10 detik | Kirim balance, equity, margin, floating, jumlah posisi, spread, status EA; **terima command pending & versi config** |
| `/ea/config` | GET | Jika `config_version` berubah | Ambil parameter strategi terbaru |
| `/ea/trades` | POST | Saat order open/modify/close (`OnTradeTransaction`) | Kirim detail trade (ticket, tipe, lot, harga, SL, TP, profit, komisi, swap, setup, alasan exit) |
| `/ea/commands/{id}/ack` | POST | Setelah command dieksekusi | Konfirmasi hasil command |
| `/ea/events` | POST | Saat terjadi | Log event: guard triggered, error order, news block, dll. |
| `/ea/news` | GET | 1 jam | Ambil kalender berita high-impact 7 hari ke depan (GMT) |

**Remote Commands** (dari web → EA via heartbeat):
`PAUSE`, `RESUME`, `CLOSE_ALL`, `CLOSE_TICKET`, `CLOSE_PROFIT_ONLY`, `MOVE_ALL_TO_BE`, `UNLOCK_DD_LOCK`, `RELOAD_CONFIG`.
Setiap command memiliki `id`, `expires_at` (default 2 menit) dan **idempoten** (EA menyimpan ID command yang sudah dijalankan).

**Contoh response heartbeat:**
```json
{
  "status": "ok",
  "server_time": 1759046400,
  "config_version": 12,
  "trading_enabled": true,
  "commands": [
    {"id": 881, "type": "MOVE_ALL_TO_BE", "payload": {}, "expires_at": 1759046520}
  ]
}
```

Rate limit: 30 request/menit per lisensi. Semua response JSON dengan HTTP status yang benar.

---

## 7. Fitur Web (PHP)

### 7.1 Autentikasi & Keamanan
- Register/Login, **2FA (TOTP Google Authenticator)**, reset password, email verification.
- Role: Admin, Trader, Viewer. Password `bcrypt/argon2id`.
- CSRF, XSS escaping, prepared statements/ORM, rate limiting login, audit log semua aksi penting (ubah config, command, lisensi).

### 7.2 Dashboard Real-time
- Kartu: Balance, Equity, Floating P/L, Profit hari ini/minggu/bulan, Drawdown saat ini vs max, Win rate, Status EA (Online/Offline/Paused/Locked), last heartbeat, spread saat ini.
- Tabel posisi terbuka (ticket, arah, lot, entry, SL, TP, R saat ini, P/L) + tombol **Close / Move to BE**.
- Grafik **equity curve** & **balance curve**, grafik harian P/L.
- Indikator status **News Filter** (berita berikutnya + countdown).
- Tombol darurat besar: **PAUSE EA** & **CLOSE ALL** (dengan konfirmasi + 2FA opsional).

### 7.3 Manajemen Akun MT5
- Tambah beberapa akun MT5 (nomor akun, server, tipe real/demo, broker).
- Setiap akun punya **preset strategi** & lisensi sendiri.

### 7.4 Konfigurasi Strategi (Preset)
- Form parameter terkelompok: Sesi, Filter, Setup A, Setup B, SL/TP, Risk, Guard, Notifikasi.
- **Validasi server-side** batas aman (contoh: RiskPercent 0.1–3, MaxDD 3–30, SL minimal).
- Preset bawaan: **Conservative (0.5%)**, **Balanced (1%)**, **Aggressive (2%)**.
- **Versioning config** (riwayat perubahan, rollback, siapa mengubah).
- Tombol **Export .set** (file parameter MT5) untuk backtest di Strategy Tester.

### 7.5 Jurnal & Analitik
- Riwayat trade: filter tanggal, setup, arah, hasil, sesi.
- Statistik: Net profit, Profit Factor, Win rate, Avg R, Expectancy, Max DD, Sharpe, Recovery Factor, jumlah trade, avg holding time, best/worst trade, consecutive win/loss.
- Breakdown per **setup (A/B)**, per **sesi**, per **hari**, per **jam** → heatmap.
- Kalender P/L bulanan.
- Export CSV / PDF.
- Import laporan backtest MT5 (HTML/XML) untuk dibandingkan dengan hasil live.

### 7.6 News Calendar
- Cron tiap 1 jam mengambil kalender ekonomi (sumber bisa dikonfigurasi, mis. feed Forex Factory JSON/XML) → simpan ke DB, konversi ke GMT.
- Admin bisa menambah/menonaktifkan event manual.
- EA mengambil daftar event via `/ea/news`.

### 7.7 Notifikasi
- **Telegram Bot** per user (hubungkan via `/start <token>`): open/close trade, guard triggered, EA offline > 5 menit, laporan harian 23:59.
- Email untuk event kritis (DD lock, lisensi kedaluwarsa).
- Pengaturan jenis notifikasi yang diinginkan.

### 7.8 Lisensi (Admin)
- Generate license key, masa berlaku, maks akun, status (active/suspended/expired).
- Bind ke nomor akun + server broker; reset binding.
- Halaman download EA (.ex5) sesuai versi.

### 7.9 Monitoring Admin
- Daftar semua EA online/offline, versi EA, error rate, latency heartbeat.
- Log API & log event dengan pencarian.

---

## 8. Skema Database (MySQL)

```sql
users(id, name, email, password, role ENUM('admin','trader','viewer'), totp_secret, telegram_chat_id, created_at, updated_at)
licenses(id, user_id, license_key UNIQUE, secret_hmac, max_accounts, expires_at, status, created_at)
mt5_accounts(id, user_id, license_id, account_number, broker_server, account_type ENUM('real','demo'),
             currency, leverage, ea_version, status ENUM('online','offline','paused','locked'),
             last_heartbeat_at, preset_id, created_at)
presets(id, user_id NULL, name, is_system BOOL, params JSON, version INT, created_at, updated_at)
preset_versions(id, preset_id, version, params JSON, changed_by, created_at)
account_snapshots(id, mt5_account_id, balance, equity, margin, free_margin, floating_pl, open_positions, spread, created_at)  -- dipartisi / di-downsample
trades(id, mt5_account_id, ticket, position_id, symbol, type ENUM('buy','sell'), setup ENUM('A','B','manual'),
       lots, open_price, close_price, sl, tp, open_time, close_time, profit, commission, swap,
       r_multiple, exit_reason ENUM('tp1','tp2','trail','sl','be','time','guard','manual','friday','news'),
       status ENUM('open','closed'), UNIQUE(mt5_account_id, position_id))
trade_events(id, trade_id, event ENUM('open','partial','modify','close'), payload JSON, created_at)
commands(id, mt5_account_id, type, payload JSON, status ENUM('pending','sent','done','failed','expired'),
         created_by, expires_at, acked_at, result JSON, created_at)
ea_events(id, mt5_account_id, level ENUM('info','warning','critical'), code, message, payload JSON, created_at)
news_events(id, event_time_utc, currency, impact ENUM('low','medium','high'), title, is_active, source)
daily_stats(id, mt5_account_id, date, start_equity, end_equity, profit, trades, wins, losses, max_dd)
audit_logs(id, user_id, action, target_type, target_id, before JSON, after JSON, ip, created_at)
```
Index: `(mt5_account_id, created_at)` pada snapshot/event, `(mt5_account_id, close_time)` pada trades.
Retensi: snapshot detail 30 hari, lalu di-agregasi per 15 menit.

---

## 9. Struktur Kode EA (MQL5)

```
GoldPilot.mq5              // OnInit, OnTick, OnTimer, OnTradeTransaction, OnDeinit
Include/GoldPilot/
  Config.mqh               // struct parameter, load/save cache JSON
  Api.mqh                  // WebRequest wrapper, HMAC, retry, queue kirim ulang saat offline
  Json.mqh                 // parser JSON ringan
  Session.mqh              // konversi waktu server↔GMT, filter sesi & rollover
  NewsFilter.mqh
  Signals.mqh              // bias HTF, Setup A, Setup B
  RiskManager.mqh          // lot sizing, daily/DD guard, consecutive loss
  TradeManager.mqh         // eksekusi, partial close, BE, trailing, time exit
  Commands.mqh             // eksekusi remote command idempoten
  Logger.mqh
```
- `OnTimer` (1 detik) → heartbeat/sinkronisasi (tidak memblokir `OnTick`). Catatan: `WebRequest` tidak berfungsi di Strategy Tester → saat testing EA memakai input parameter lokal.
- Trade yang gagal terkirim ke web disimpan di **antrian lokal (file)** dan dikirim ulang saat koneksi pulih.
- Tampilkan panel info di chart (status, bias, sesi, spread, P/L hari ini, guard).

---

## 10. Kebutuhan Non-Fungsional

- **Keamanan:** HTTPS wajib, HMAC request EA, 2FA, secret di `.env`, tidak ada kredensial login MT5 yang disimpan di web (EA terhubung sendiri dari terminal).
- **Performa:** endpoint heartbeat < 150 ms; mampu 500 EA × heartbeat 10 detik (≈50 req/s) di VPS 2 vCPU / 4 GB.
- **Keandalan:** EA tetap aman saat web down; semua command idempoten; ingest trade idempoten (unique `position_id`).
- **Observability:** log terstruktur, halaman health check `/api/health`.
- **Deployment:** Docker Compose (nginx + php-fpm + mysql + scheduler), panduan deploy ke VPS/cPanel.
- **Zona waktu:** simpan semua waktu dalam **UTC**, tampilkan sesuai timezone user (default Asia/Jakarta).
- **Bahasa UI:** Bahasa Indonesia (siapkan i18n untuk English).

---

## 11. Validasi Strategi (wajib sebelum live)

1. **Backtest** di MT5 Strategy Tester mode *"Every tick based on real ticks"*, data minimal **3–5 tahun**, dengan spread & komisi realistis.
2. **Walk-forward / out-of-sample**: optimasi di 70% data, uji di 30% sisanya. Hindari over-optimization (parameter harus stabil di area sekitarnya).
3. **Monte Carlo** (acak urutan trade) → estimasi DD terburuk.
4. Target minimal untuk lanjut: Profit Factor > 1.3, Max DD < 20%, ≥ 200 trade, expectancy positif di out-of-sample.
5. **Forward test di akun demo minimal 1–2 bulan**, lalu akun real kecil / cent.
6. Web menampilkan perbandingan **backtest vs live** (deviasi win rate, avg R, slippage).

---

## 12. Milestone Pengerjaan

| # | Milestone | Output |
|---|---|---|
| M1 | Setup proyek, auth, role, 2FA, lisensi, akun MT5 | Web bisa login & generate lisensi |
| M2 | API EA (handshake, heartbeat, config, trades, events, commands) + HMAC + tes | Dokumentasi API (OpenAPI) + unit test |
| M3 | EA MQL5: koneksi API, cache config, panel chart, remote command | EA terhubung & terlihat online di web |
| M4 | EA: logika strategi (filter, bias, Setup A/B, SL/TP, sizing, trailing) + risk guard | EA bisa di-backtest dengan input lokal |
| M5 | Dashboard real-time, posisi terbuka, tombol darurat, konfigurasi preset + versioning | Kontrol penuh dari web |
| M6 | Jurnal, analitik, kalender P/L, export, news calendar | Laporan lengkap |
| M7 | Telegram & email, admin monitoring, audit log | Notifikasi berjalan |
| M8 | Hardening keamanan, Docker, dokumentasi deploy & user guide | Siap produksi |

---

## 13. Kriteria Penerimaan (Acceptance Criteria)

- [ ] EA menolak berjalan jika lisensi tidak valid / akun tidak cocok.
- [ ] Perubahan parameter di web diterapkan EA dalam ≤ 15 detik tanpa restart.
- [ ] Tombol CLOSE ALL menutup semua posisi dalam ≤ 15 detik dan status ter-ack di web.
- [ ] Daily loss limit & max DD menutup posisi dan mengunci EA sesuai aturan, notifikasi Telegram terkirim.
- [ ] Tidak ada posisi baru dibuka dalam jendela berita high-impact.
- [ ] Lot yang dihitung tidak pernah membuat risiko > RiskPercent yang disetel (toleransi pembulatan step lot).
- [ ] Saat web mati, EA tetap mengelola SL/trailing dan menyinkronkan trade yang tertunda setelah web kembali.
- [ ] Trade yang sama tidak tercatat dua kali di database.
- [ ] Hasil backtest dengan parameter sama dapat direproduksi (sinyal hanya pada candle close).
- [ ] Semua endpoint lolos uji: signature salah → 401, timestamp kedaluwarsa → 401, rate limit → 429.

---

## 14. Disclaimer (tampilkan di web)

Trading XAUUSD dengan leverage berisiko tinggi. Performa masa lalu/backtest tidak menjamin hasil di masa depan. Sistem ini adalah alat bantu; pengguna bertanggung jawab penuh atas penggunaan dan dana mereka.
