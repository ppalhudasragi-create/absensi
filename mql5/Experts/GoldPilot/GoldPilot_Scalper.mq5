//+------------------------------------------------------------------+
//|                                          GoldPilot_Scalper.mq5   |
//|  Auto scalping XAUUSD — eksekusi M1, bias M5/M15                 |
//|  Setup A: Momentum Pullback | B: Squeeze Breakout | C: Mean Rev. |
//|  Tidak memakai martingale/grid/averaging. Setiap order punya     |
//|  hard SL. Tidak memanggil WebRequest (komunikasi via EA Bridge). |
//+------------------------------------------------------------------+
#property copyright   "GoldPilot"
#property version     "1.00"
#property description "GoldPilot Scalper - auto scalping XAUUSD M1 untuk MetaTrader 5"

#include <GoldPilot/Defines.mqh>

//=== INPUT ===========================================================
input group "=== Umum ==="
input long              InpMagic              = 240901;         // Magic number
input string            InpSymbolOverride     = "";             // Simbol (kosong = simbol chart)
input bool              InpUseBridge          = true;           // Tulis status/outbox untuk EA Bridge (live)
input bool              InpShowPanel          = true;           // Tampilkan panel info di chart

input group "=== Zona Waktu Broker ==="
input ENUM_GPS_GMT_MODE InpGMTMode            = GPS_GMT_AUTO;   // Mode offset GMT
input int               InpBrokerGMTWinter    = 2;              // Offset GMT server (musim dingin)
input ENUM_GPS_DST      InpBrokerDST          = GPS_DST_US;     // Aturan DST server

input group "=== Sesi Trading (jam GMT) ==="
input bool              InpUseLondon          = true;           // Sesi London
input string            InpLondonStart        = "07:00";
input string            InpLondonEnd          = "10:30";
input bool              InpUseNY              = true;           // Sesi overlap London-New York
input string            InpNYStart            = "12:30";
input string            InpNYEnd              = "16:30";
input bool              InpUseAsia            = false;          // Sesi Asia
input string            InpAsiaStart          = "00:00";
input string            InpAsiaEnd            = "03:00";
input string            InpRolloverStart      = "23:30";        // Awal blok rollover (jam SERVER)
input string            InpRolloverEnd        = "01:30";        // Akhir blok rollover (jam SERVER)
input int               InpFridayNoNewGMT     = 19;             // Jumat: tidak buka posisi baru mulai jam (GMT)
input string            InpFridayCloseGMT     = "20:30";        // Jumat: tutup semua posisi (GMT, kosong = off)

input group "=== Filter Pasar & Biaya ==="
input double            InpMaxSpread          = 0.20;           // Spread maksimum ($ harga)
input double            InpMaxSpreadPctSL     = 15;             // Spread maks (% dari jarak SL)
input double            InpSpreadSpikeMult    = 2.0;            // Tolak jika spread > x rata-rata
input int               InpSpreadBufferTicks  = 200;            // Jumlah tick untuk rata-rata spread
input double            InpMinATR             = 0.40;           // ATR(14) M1 minimum ($)
input double            InpMaxATR             = 2.50;           // ATR(14) M1 maksimum ($)
input int               InpMinTicksPerMin     = 40;             // Tick minimum per 60 detik (0 = off)
input int               InpMaxPingMs          = 50;             // Ping maksimum ke server (ms, live; 0 = off)
input double            InpCommissionPerLot   = 7.0;            // Komisi round-turn per lot (mata uang akun)
input double            InpEstSlippage        = 0.03;           // Estimasi slippage awal ($)
input double            InpCostMultiple       = 3.0;            // TP minimal x total biaya

input group "=== Filter Berita (High-Impact USD) ==="
input bool              InpUseNews            = true;           // Aktifkan filter berita
input int               InpNewsBeforeMin      = 15;             // Blok entry sebelum berita (menit)
input int               InpNewsAfterMin       = 30;             // Blok entry sesudah berita (menit)
input bool              InpNewsClosePositions = true;           // Tutup posisi sebelum berita
input int               InpNewsCloseBeforeMin = 2;              // Tutup posisi x menit sebelum berita
input string            InpNewsFile           = "GoldPilot\\news.csv"; // File CSV berita (Common\Files)

input group "=== Bias Micro-Trend (M5/M15) ==="
input int               InpBiasFastEMA        = 20;             // EMA cepat M5
input int               InpBiasSlowEMA        = 50;             // EMA lambat M5
input int               InpBiasM15EMA         = 50;             // EMA M15
input bool              InpUseVWAP            = true;           // Wajib searah VWAP harian

input group "=== Setup A: Momentum Pullback ==="
input bool              InpUseSetupA          = true;
input int               InpA_FastEMA          = 9;              // EMA pullback cepat M1
input int               InpA_SlowEMA          = 21;             // EMA pullback lambat M1
input int               InpRSIPeriod          = 7;              // Periode RSI M1
input double            InpA_RSIFloor         = 30;             // RSI terendah (di bawah ini = trend patah)
input double            InpA_RSIPullback      = 50;             // RSI pullback maksimal
input double            InpA_MinBodyPct       = 50;             // Body candle konfirmasi minimal (%)
input double            InpA_VolMult          = 1.2;            // Tick volume minimal x rata-rata

input group "=== Setup B: Squeeze Breakout ==="
input bool              InpUseSetupB          = true;
input int               InpB_BBPeriod         = 20;             // Periode Bollinger
input double            InpB_BBDev            = 2.0;            // Deviasi Bollinger
input int               InpB_Lookback         = 120;            // Lookback persentil lebar band
input double            InpB_Percentile       = 20;             // Persentil squeeze (%)
input int               InpB_MinSqueezeBars   = 5;              // Minimal bar squeeze
input double            InpB_MinBodyPct       = 60;             // Body candle breakout minimal (%)
input double            InpB_VolMult          = 1.5;            // Volume minimal x rata-rata (searah bias)
input double            InpB_VolMultNeutral   = 2.0;            // Volume minimal x rata-rata (bias netral)
input bool              InpB_AllowNeutral     = true;           // Izinkan breakout saat bias netral
input double            InpB_MaxBarATR        = 1.5;            // Candle breakout maksimal x ATR

input group "=== Setup C: Mean Reversion (default OFF) ==="
input bool              InpUseSetupC          = false;
input double            InpC_BBDev            = 2.5;            // Deviasi Bollinger
input double            InpC_MaxADX           = 18;             // ADX(14) M5 maksimum (pasar ranging)
input double            InpC_RSILow           = 20;             // RSI ekstrem (20 / 80)
input double            InpC_MinRR            = 0.8;            // Jarak ke middle band minimal x SL

input group "=== Stop Loss / Take Profit ==="
input double            InpSL_ATRMult         = 1.2;            // SL = x ATR(14) M1
input double            InpMinSL              = 0.80;           // SL minimum ($)
input double            InpMaxSL              = 3.50;           // SL maksimum ($) — lebih lebar = skip
input int               InpSwingBars          = 5;              // Bar untuk swing high/low
input ENUM_GPS_TP_MODE  InpTPMode             = GPS_TP_SINGLE;  // Mode take profit
input double            InpTP_R               = 1.2;            // TP (R) mode tunggal
input double            InpPartialR           = 0.8;            // Partial close di (R)
input double            InpPartialPct         = 60;             // Persentase volume partial
input double            InpRunnerTP_R         = 2.0;            // TP sisa posisi (R) mode partial
input double            InpBE_R               = 0.6;            // Breakeven saat profit (R)
input double            InpTrailStartR        = 1.0;            // Mulai trailing (R)
input double            InpTrailATRMult       = 0.8;            // Jarak trailing x ATR M1
input double            InpTrailStep          = 0.05;           // Langkah minimum trailing ($)
input bool              InpStealthTP          = false;          // TP dikelola lokal (SL tetap di server)
input double            InpSignalMaxDriftATR  = 0.3;            // Batal jika harga lari > x ATR dari sinyal
input int               InpSignalValidSec     = 20;             // Masa berlaku sinyal (detik)

input group "=== Manajemen Waktu ==="
input int               InpMaxHoldMin         = 20;             // Lama posisi maksimum (menit)
input int               InpStaleMin           = 5;              // Cek stale setelah (menit)
input double            InpStaleMinR          = 0.2;            // Tutup jika profit < x R saat stale
input bool              InpUseEarlyExit       = true;           // Keluar jika candle kuat berlawanan
input double            InpEarlyExitBodyPct   = 70;             // Body candle berlawanan minimal (%)
input int               InpCooldownMin        = 3;              // Jeda setelah trade (menit)
input int               InpCooldownLossMin    = 10;             // Jeda setelah loss (menit)

input group "=== Risiko & Lot ==="
input ENUM_GPS_LOT_MODE InpLotMode            = GPS_LOT_RISK;   // Mode lot
input double            InpRiskPct            = 0.5;            // Risiko per trade (% equity, maks 1.5)
input double            InpFixedLot           = 0.01;           // Lot tetap (mode fixed)
input double            InpMaxLot             = 5.0;            // Batas lot absolut
input double            InpMinMarginLevel     = 500;            // Margin level minimum setelah entry (%)
input int               InpMaxPositions       = 1;              // Posisi terbuka maksimum
input int               InpMaxTradesHour      = 6;              // Trade maksimum per jam
input int               InpMaxTradesDay       = 25;             // Trade maksimum per hari

input group "=== Hard Guard ==="
input double            InpDailyLossPct       = 2.0;            // Daily loss limit (% equity awal hari)
input bool              InpUseDailyTarget     = false;          // Stop saat target harian tercapai
input double            InpDailyTargetPct     = 3.0;            // Target profit harian (%)
input bool              InpUseGiveback        = true;           // Proteksi profit giveback
input double            InpGivebackPct        = 50;             // Stop jika profit turun x% dari puncak harian
input double            InpGivebackMinPct     = 0.5;            // Aktif setelah profit harian >= x%
input double            InpMaxDDPct           = 8.0;            // Max drawdown dari puncak equity (%) -> kunci
input int               InpConsecLossPause    = 3;              // Loss beruntun -> pause
input int               InpConsecPauseMin     = 60;             // Lama pause (menit)
input int               InpConsecLossStop     = 5;              // Loss beruntun -> stop hari ini

input group "=== Kualitas Eksekusi ==="
input double            InpMaxSlippage        = 0.10;           // Deviasi harga maksimum per order ($)
input double            InpMaxAvgSlippage     = 0.05;           // Auto-pause jika rata-rata slippage > ($)
input double            InpMaxAvgExecMs       = 500;            // Auto-pause jika rata-rata eksekusi > (ms)
input int               InpExecSamples        = 20;             // Jumlah sampel rata-rata

#include <GoldPilot/Utils.mqh>
#include <GoldPilot/Bus.mqh>
#include <GoldPilot/MarketState.mqh>
#include <GoldPilot/News.mqh>
#include <GoldPilot/Risk.mqh>
#include <GoldPilot/Signals.mqh>
#include <GoldPilot/Trader.mqh>

//=== STATE =============================================================
GpsSignal g_sig;
datetime  g_lastBarTime   = 0;
ulong     g_lastStatusMs  = 0;
double    g_onTickAvgUs   = 0;
bool      g_initialized   = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_tester = (bool)MQLInfoInteger(MQL_TESTER);
   g_optim  = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_visual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);

   g_sym = (InpSymbolOverride != "") ? InpSymbolOverride : _Symbol;
   if(!SymbolSelect(g_sym, true))
     {
      Print("[GPS] Simbol tidak ditemukan: ", g_sym);
      return INIT_FAILED;
     }
   string up = g_sym;
   StringToUpper(up);
   if(StringFind(up, "XAU") < 0 && StringFind(up, "GOLD") < 0)
      Print("[GPS] PERINGATAN: EA ini dirancang untuk XAUUSD, simbol saat ini ", g_sym);

   // validasi parameter
   if(InpMinSL <= 0 || InpMinSL >= InpMaxSL || InpRiskPct <= 0 || InpTP_R <= 0 ||
      InpBE_R <= 0 || InpMaxPositions < 1 || InpB_Lookback < 30 || InpSwingBars < 1 ||
      InpB_Lookback + 3 > 1000)
     {
      Print("[GPS] Parameter tidak valid");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPct > 1.5)
      Print("[GPS] RiskPct dibatasi maksimal 1.5%");

   g_digits   = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_point    = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0) g_tickSize = g_point;
   g_login       = AccountInfoInteger(ACCOUNT_LOGIN);
   g_statePrefix = "GPS_" + IntegerToString(g_login) + "_" + IntegerToString(InpMagic) + "_";
   g_flagPrefix  = "GPS_" + IntegerToString(g_login) + "_";

   if(g_tester)
      GlobalVariablesDeleteAll(g_statePrefix);   // backtest selalu mulai bersih

   if(!ParseSessions())
      return INIT_PARAMETERS_INCORRECT;
   UpdateGMTOffset();
   if(!MsInit())
      return INIT_FAILED;
   TrInit();
   BusInit();
   RiskLoad();
   RiskNewDayCheck();
   RiskRebuildCounts();
   NewsLoad();
   ZeroMemory(g_sig);

   if(!g_optim)
      EventSetTimer(1);

   long mode = SymbolInfoInteger(g_sym, SYMBOL_TRADE_MODE);
   if(mode != SYMBOL_TRADE_MODE_FULL)
      Log("PERINGATAN: mode trading simbol tidak FULL (" + IntegerToString(mode) + ")");
   if(!g_tester && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Log("PERINGATAN: tombol AutoTrading terminal nonaktif");

   Log(StringFormat("Start v%s %s magic=%I64d digits=%d tick=%.3f stops=%d offsetGMT=%+.1fh",
                    GPS_VERSION, g_sym, InpMagic, g_digits, g_tickSize,
                    (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL), g_gmtOffset / 3600.0));
   BusEvent("info", "EA_START", "GoldPilot Scalper v" + GPS_VERSION + " " + g_sym);
   g_initialized = true;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_initialized)
     {
      RiskSave();
      MsRelease();
      BusEvent("info", "EA_STOP", "reason=" + IntegerToString(reason));
     }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Flag dari EA Bridge (web): PAUSE, CLOSEALL, RESUME, UNLOCK        |
//+------------------------------------------------------------------+
void HandleFlags()
  {
   g_extPause = FlagGet("PAUSE");
   if(FlagGet("CLOSEALL"))
     {
      FlagSet("CLOSEALL", 0);
      CloseAll("manual");
      BusEvent("warning", "CLOSE_ALL", "Semua posisi ditutup atas perintah web");
     }
   if(FlagGet("RESUME"))
     {
      FlagSet("RESUME", 0);
      g_autoPaused = false;
      g_pauseUntil = 0;
      EqReset();
      RiskSave();
      BusEvent("info", "RESUME", "Auto-pause & pause loss beruntun dibersihkan");
     }
   if(FlagGet("UNLOCK"))
     {
      FlagSet("UNLOCK", 0);
      g_locked = false;
      g_peakEq = AccountInfoDouble(ACCOUNT_EQUITY);
      RiskSave();
      BusEvent("warning", "UNLOCK", "Kunci max drawdown dibuka, puncak equity di-reset");
     }
  }

//+------------------------------------------------------------------+
//| Filter sebelum entry                                              |
//+------------------------------------------------------------------+
bool CanOpen(string &why)
  {
   if(!g_tester && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
     { why = "AutoTrading nonaktif"; return false; }
   if(!RiskAllowsNew(why))
      return false;
   if(CountMyPositions() >= InpMaxPositions)
     { why = "posisi maksimum sudah terbuka"; return false; }
   if(!SessionOpen(why))
      return false;
   if(InpUseNews && NewsBlocked(NowServer(), why))
      return false;

   if(g_curSpread > InpMaxSpread)
     { why = StringFormat("spread %.2f > maks %.2f", g_curSpread, InpMaxSpread); return false; }
   if(g_spreadCount >= 50 && g_curSpread > MsAvgSpread() * InpSpreadSpikeMult)
     { why = StringFormat("spread spike %.2f (rata-rata %.2f)", g_curSpread, MsAvgSpread()); return false; }
   if(g_atr < InpMinATR || g_atr > InpMaxATR)
     { why = StringFormat("ATR %.2f di luar rentang %.2f-%.2f", g_atr, InpMinATR, InpMaxATR); return false; }
   if(InpMinTicksPerMin > 0 && MsTicksLastMinute() < InpMinTicksPerMin)
     { why = "pasar sepi (tick/menit rendah)"; return false; }
   if(!g_tester && InpMaxPingMs > 0)
     {
      double ping = (double)TerminalInfoInteger(TERMINAL_PING_LAST) / 1000.0;   // mikrodetik -> ms
      if(ping > InpMaxPingMs)
        { why = StringFormat("ping %.0f ms > maks", ping); return false; }
     }
   return true;
  }

//+------------------------------------------------------------------+
void OnNewBar()
  {
   UpdateGMTOffset();
   MsUpdateBar();
   MsUpdateVWAP();
   if(!MsReady())
      return;

   GpsSignal s;
   ZeroMemory(s);
   if(SigEvaluate(s))
     {
      g_sig = s;
      Log(StringFormat("Sinyal %s %s | bias=%d ATR=%.2f", SetupName(s.setup), s.dir > 0 ? "BUY" : "SELL", g_bias, s.atr));
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ulong t0 = GetMicrosecondCount();
   if(!MsOnTick())
      return;

   RiskNewDayCheck();
   HandleFlags();

   string gr = "";
   if(RiskCheckGuards(gr) == GPS_GUARD_CLOSE_ALL)
     {
      CloseAll("guard");
      BusEvent("critical", "GUARD", gr);
     }

   datetime bt = iTime(g_sym, PERIOD_M1, 0);
   bool newBar = (bt > 0 && bt != g_lastBarTime);
   if(newBar)
     {
      g_lastBarTime = bt;
      OnNewBar();
     }

   TrManage(newBar);

   if(g_sig.valid)
     {
      if(NowServer() - g_sig.created > InpSignalValidSec || g_sig.barTime != bt)
        {
         g_sig.valid = false;
         SetReject("sinyal kedaluwarsa");
        }
      else
        {
         string why = "";
         if(!CanOpen(why) || !TrExecute(g_sig, why))
            SetReject(why);
        }
     }

   double us = (double)(GetMicrosecondCount() - t0);
   g_onTickAvgUs = (g_onTickAvgUs == 0) ? us : g_onTickAvgUs * 0.99 + us * 0.01;
  }

//+------------------------------------------------------------------+
//| Posisi tertutup -> statistik, guard, outbox                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal))
      return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != g_sym || HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
      return;

   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   long pid   = HistoryDealGetInteger(deal, DEAL_POSITION_ID);

   if(entry == DEAL_ENTRY_IN)
     {
      RiskOnEntry((datetime)HistoryDealGetInteger(deal, DEAL_TIME));
      return;
     }
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;
   if(PositionExistsById(pid))
      return;                                        // partial close, posisi masih ada

   double   closePrice = HistoryDealGetDouble(deal, DEAL_PRICE);
   datetime closeTime  = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   long     dealReason = HistoryDealGetInteger(deal, DEAL_REASON);

   double   net = 0, openPrice = 0, openVol = 0;
   datetime openTime = 0;
   long     side = 0;
   if(HistorySelectByPosition(pid))
     {
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) +
                HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
         if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            openPrice = HistoryDealGetDouble(d, DEAL_PRICE);
            openVol   = HistoryDealGetDouble(d, DEAL_VOLUME);
            openTime  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            side      = HistoryDealGetInteger(d, DEAL_TYPE);
           }
        }
     }

   int flags = (int)TkGet(pid, "F", 0);
   string rsn = PopExitReason(pid);
   if(rsn == "")
     {
      if(dealReason == DEAL_REASON_SL)      rsn = ((flags & GPS_F_TRAIL) != 0) ? "trail" : (((flags & GPS_F_BE) != 0) ? "be" : "sl");
      else if(dealReason == DEAL_REASON_TP) rsn = "tp";
      else if(dealReason == DEAL_REASON_SO) rsn = "stopout";
      else                                  rsn = "manual";
     }

   double risk      = TkGet(pid, "R", 0);
   double tv        = TickValueLoss();
   double riskMoney = (risk > 0 && g_tickSize > 0) ? risk / g_tickSize * tv * openVol : 0;
   double rMult     = (riskMoney > 0) ? net / riskMoney : 0;
   double mfeR      = (risk > 0) ? TkGet(pid, "MFE", 0) / risk : 0;
   double maeR      = (risk > 0) ? TkGet(pid, "MAE", 0) / risk : 0;
   int    setup     = (int)TkGet(pid, "S", 0);

   RiskOnPositionClosed(net);

   Log(StringFormat("CLOSE #%I64d %s net=%.2f (%.2fR) alasan=%s durasi=%ds",
                    pid, SetupName(setup), net, rMult, rsn, (int)(closeTime - openTime)));

   BusEmit("trade_close",
           JI("position_id", pid) + "," + JS("setup", SetupName(setup)) + "," +
           JS("side", side == DEAL_TYPE_BUY ? "buy" : "sell") + "," + JN("lots", openVol, 2) + "," +
           JN("open_price", openPrice, g_digits) + "," + JN("close_price", closePrice, g_digits) + "," +
           JI("open_time_utc", (long)openTime - g_gmtOffset) + "," + JI("close_time_utc", (long)closeTime - g_gmtOffset) + "," +
           JI("duration_sec", (long)(closeTime - openTime)) + "," + JN("net_profit", net, 2) + "," +
           JN("r_multiple", rMult, 2) + "," + JN("mfe_r", mfeR, 2) + "," + JN("mae_r", maeR, 2) + "," +
           JS("exit_reason", rsn));

   TkDelAll(pid);
  }

//+------------------------------------------------------------------+
//| Status untuk Bridge + panel chart                                 |
//+------------------------------------------------------------------+
string StatusText()
  {
   if(g_locked)          return "TERKUNCI (max DD)";
   if(g_dayHalt)         return "STOP HARI INI (" + HaltName(g_haltCode) + ")";
   if(g_autoPaused)      return "AUTO-PAUSE (eksekusi)";
   if(g_extPause)        return "PAUSE (web)";
   if(NowServer() < g_pauseUntil) return "PAUSE loss beruntun";
   return "AKTIF";
  }

void WriteStatus()
  {
   if(!g_busOn)
      return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string json = "{" + JI("account", g_login) + "," + JS("server", AccountInfoString(ACCOUNT_SERVER)) + "," +
                 JS("symbol", g_sym) + "," + JI("magic", InpMagic) + "," + JS("ea_version", GPS_VERSION) + "," +
                 JI("ts_utc", NowUTCLong()) + "," + JS("status", StatusText()) + "," +
                 JN("balance", bal, 2) + "," + JN("equity", eq, 2) + "," +
                 JN("margin", AccountInfoDouble(ACCOUNT_MARGIN), 2) + "," +
                 JN("free_margin", AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "," +
                 JN("floating", MyFloating(), 2) + "," + JI("open_positions", CountMyPositions()) + "," +
                 JN("spread", g_curSpread, g_digits) + "," + JN("spread_avg", MsAvgSpread(), g_digits) + "," +
                 JN("ping_ms", (double)TerminalInfoInteger(TERMINAL_PING_LAST) / 1000.0, 1) + "," +
                 JI("ticks_per_min", MsTicksLastMinute()) + "," + JN("atr", g_atr, g_digits) + "," +
                 JI("bias", g_bias) + "," + JS("session", ActiveSessionName()) + "," +
                 JI("trades_today", ArraySize(g_entryTimes)) + "," + JI("consec_loss", g_consecLoss) + "," +
                 JN("day_start_equity", g_dayStartEq, 2) + "," + JN("peak_equity", g_peakEq, 2) + "," +
                 JN("avg_slippage", EqAvgSlip(), g_digits) + "," + JN("avg_exec_ms", EqAvgMs(), 1) + "," +
                 JN("ontick_us", g_onTickAvgUs, 0) + "," + JS("last_reject", g_lastReject) + "," +
                 JS("last_signal", g_lastSignal) + "}";
   BusWriteFile("status.json", json);
  }

void DrawPanel()
  {
   if(!InpShowPanel || (g_tester && !g_visual))
      return;
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double pl  = eq - g_dayStartEq;
   double plP = (g_dayStartEq > 0) ? pl / g_dayStartEq * 100.0 : 0;
   double dd  = (g_peakEq > 0) ? (g_peakEq - eq) / g_peakEq * 100.0 : 0;
   string bias = (g_bias > 0) ? "BULLISH" : (g_bias < 0 ? "BEARISH" : "NETRAL");
   string txt =
      "GoldPilot Scalper v" + GPS_VERSION + "  |  " + g_sym + "  |  magic " + IntegerToString(InpMagic) + "\n" +
      "Status      : " + StatusText() + "\n" +
      "Waktu GMT   : " + TimeToString(NowGMT(), TIME_MINUTES) + " (server " + StringFormat("%+.1f", g_gmtOffset / 3600.0) + ")  Sesi: " + ActiveSessionName() + "\n" +
      "Bias M5/M15 : " + bias + "   ATR M1: " + DoubleToString(g_atr, 2) + "   VWAP: " + DoubleToString(g_vwap, g_digits) + "\n" +
      StringFormat("Spread      : %.2f (avg %.2f)  Tick/mnt: %d  Ping: %.0f ms\n",
                   g_curSpread, MsAvgSpread(), MsTicksLastMinute(), (double)TerminalInfoInteger(TERMINAL_PING_LAST) / 1000.0) +
      StringFormat("Trade       : hari ini %d/%d  jam ini %d/%d  loss beruntun %d\n",
                   ArraySize(g_entryTimes), InpMaxTradesDay, TradesLastHour(NowServer()), InpMaxTradesHour, g_consecLoss) +
      StringFormat("P/L hari ini: %.2f (%.2f%%)   DD dari puncak: %.2f%%   Floating: %.2f\n", pl, plP, dd, MyFloating()) +
      StringFormat("Eksekusi    : slip avg %.3f  exec avg %.0f ms  OnTick %.0f us\n", EqAvgSlip(), EqAvgMs(), g_onTickAvgUs) +
      "Berita      : " + (InpUseNews ? NewsNextText(NowServer()) : "off") + "\n" +
      "Entry akhir : " + (g_lastSignal == "" ? "-" : g_lastSignal) + "\n" +
      "Ditolak     : " + (g_lastReject == "" ? "-" : g_lastReject);
   Comment(txt);
  }

void OnTimer()
  {
   DrawPanel();
   ulong now = GetTickCount64();
   if(now - g_lastStatusMs >= 5000)
     {
      g_lastStatusMs = now;
      WriteStatus();
     }
   if(!g_tester && InpUseNews && NowServer() - g_newsLoaded >= 1800)
      NewsLoad();
  }

//+------------------------------------------------------------------+
//| Kriteria optimasi: Profit Factor x sqrt(jumlah trade)             |
//| (butuh >= 100 trade supaya tidak overfit pada sampel kecil)       |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double ddPct  = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(trades < 100 || pf <= 1.0)
      return 0;
   return pf * MathSqrt(trades) * (ddPct < 15 ? 1.0 : 15.0 / ddPct);
  }
//+------------------------------------------------------------------+
