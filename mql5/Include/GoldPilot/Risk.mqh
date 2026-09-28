//+------------------------------------------------------------------+
//| GoldPilot Scalper — manajemen risiko & hard guard                |
//+------------------------------------------------------------------+
#ifndef GPS_RISK_MQH
#define GPS_RISK_MQH

#define GPS_GUARD_NONE      0
#define GPS_GUARD_CLOSE_ALL 1

#define GPS_HALT_NONE         0
#define GPS_HALT_DAILY_LOSS   1
#define GPS_HALT_DAILY_TARGET 2
#define GPS_HALT_GIVEBACK     3
#define GPS_HALT_CONSEC_LOSS  4

double   g_dayStartEq    = 0;
double   g_peakEq        = 0;
double   g_peakEqSaved   = 0;
double   g_dayPeakProfit = 0;
int      g_dayKey        = 0;
bool     g_locked        = false;   // max drawdown -> harus di-unlock dari web
bool     g_dayHalt       = false;
int      g_haltCode      = GPS_HALT_NONE;
bool     g_autoPaused    = false;   // kualitas eksekusi buruk
bool     g_extPause      = false;   // PAUSE dari web (flag Bridge)
datetime g_pauseUntil    = 0;
datetime g_cooldownUntil = 0;
int      g_consecLoss    = 0;
datetime g_entryTimes[];            // entry hari ini (waktu server)

string HaltName(const int code)
  {
   switch(code)
     {
      case GPS_HALT_DAILY_LOSS:   return "DAILY_LOSS";
      case GPS_HALT_DAILY_TARGET: return "DAILY_TARGET";
      case GPS_HALT_GIVEBACK:     return "PROFIT_GIVEBACK";
      case GPS_HALT_CONSEC_LOSS:  return "CONSECUTIVE_LOSS";
     }
   return "-";
  }

void RiskSave()
  {
   StSet("DAYKEY", g_dayKey);
   StSet("DAYSTART", g_dayStartEq);
   StSet("PEAK", g_peakEq);
   StSet("DAYPEAKPROFIT", g_dayPeakProfit);
   StSet("LOCK", g_locked ? 1 : 0);
   StSet("HALT", g_dayHalt ? g_haltCode : 0);
   StSet("AUTOPAUSE", g_autoPaused ? 1 : 0);
   StSet("PAUSEUNTIL", (double)g_pauseUntil);
   StSet("COOLUNTIL", (double)g_cooldownUntil);
   StSet("CONSEC", g_consecLoss);
   g_peakEqSaved = g_peakEq;
  }

void RiskLoad()
  {
   double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayKey        = (int)StGet("DAYKEY", 0);
   g_dayStartEq    = StGet("DAYSTART", eq);
   g_peakEq        = MathMax(StGet("PEAK", eq), eq);
   g_dayPeakProfit = StGet("DAYPEAKPROFIT", 0);
   g_locked        = (StGet("LOCK", 0) > 0.5);
   g_haltCode      = (int)StGet("HALT", 0);
   g_dayHalt       = (g_haltCode != GPS_HALT_NONE);
   g_autoPaused    = (StGet("AUTOPAUSE", 0) > 0.5);
   g_pauseUntil    = (datetime)StGet("PAUSEUNTIL", 0);
   g_cooldownUntil = (datetime)StGet("COOLUNTIL", 0);
   g_consecLoss    = (int)StGet("CONSEC", 0);
   g_peakEqSaved   = g_peakEq;
  }

void RiskHalt(const int code)
  {
   if(g_dayHalt)
      return;
   g_dayHalt  = true;
   g_haltCode = code;
   RiskSave();
   BusEvent("warning", HaltName(code), "Trading dihentikan sampai hari berikutnya");
  }

void RiskNewDayCheck()
  {
   int k = DayKey(NowServer());
   if(k == g_dayKey)
      return;
   g_dayKey        = k;
   g_dayStartEq    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayPeakProfit = 0;
   g_dayHalt       = false;
   g_haltCode      = GPS_HALT_NONE;
   g_consecLoss    = 0;
   ArrayResize(g_entryTimes, 0);
   RiskSave();
   Log("Hari baru, equity awal = " + DoubleToString(g_dayStartEq, 2));
  }

// Hitung ulang jumlah entry hari ini dari history (setelah restart)
void RiskRebuildCounts()
  {
   ArrayResize(g_entryTimes, 0);
   datetime srv  = NowServer();
   datetime from = DayStart(srv);
   if(!HistorySelect(from, srv + 60))
      return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != g_sym) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      int n = ArraySize(g_entryTimes);
      ArrayResize(g_entryTimes, n + 1);
      g_entryTimes[n] = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
     }
  }

void RiskOnEntry(const datetime t)
  {
   int n = ArraySize(g_entryTimes);
   ArrayResize(g_entryTimes, n + 1);
   g_entryTimes[n] = t;
  }

int TradesLastHour(const datetime now)
  {
   int c = 0;
   for(int i = ArraySize(g_entryTimes) - 1; i >= 0; i--)
      if(now - g_entryTimes[i] < 3600)
         c++;
   return c;
  }

// Evaluasi guard berbasis equity — dipanggil setiap tick
int RiskCheckGuards(string &reason)
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEq <= 0)
      g_dayStartEq = eq;

   if(eq > g_peakEq)
     {
      g_peakEq = eq;
      if(g_peakEq > g_peakEqSaved * 1.001)
        {
         StSet("PEAK", g_peakEq);
         g_peakEqSaved = g_peakEq;
        }
     }

   // 1. Max drawdown dari puncak equity -> tutup semua + kunci
   if(!g_locked && g_peakEq > 0 && eq <= g_peakEq * (1.0 - InpMaxDDPct / 100.0))
     {
      g_locked = true;
      RiskSave();
      reason = StringFormat("MAX_DD: equity %.2f <= %.1f%% dari puncak %.2f", eq, 100 - InpMaxDDPct, g_peakEq);
      return GPS_GUARD_CLOSE_ALL;
     }

   // 2. Daily loss limit -> tutup semua, berhenti hari ini
   if(!(g_dayHalt && g_haltCode == GPS_HALT_DAILY_LOSS) &&
      eq <= g_dayStartEq * (1.0 - InpDailyLossPct / 100.0))
     {
      g_dayHalt  = false;
      RiskHalt(GPS_HALT_DAILY_LOSS);
      reason = StringFormat("DAILY_LOSS: equity %.2f, awal hari %.2f", eq, g_dayStartEq);
      return GPS_GUARD_CLOSE_ALL;
     }

   double profit = eq - g_dayStartEq;
   if(profit > g_dayPeakProfit)
      g_dayPeakProfit = profit;

   if(!g_dayHalt)
     {
      // 3. Target profit harian -> stop buka posisi baru
      if(InpUseDailyTarget && profit >= g_dayStartEq * InpDailyTargetPct / 100.0)
         RiskHalt(GPS_HALT_DAILY_TARGET);
      // 4. Profit giveback -> stop buka posisi baru
      else if(InpUseGiveback && g_dayPeakProfit >= g_dayStartEq * InpGivebackMinPct / 100.0 &&
              profit <= g_dayPeakProfit * (1.0 - InpGivebackPct / 100.0))
         RiskHalt(GPS_HALT_GIVEBACK);
     }
   return GPS_GUARD_NONE;
  }

// Dipanggil saat posisi tertutup penuh (profit bersih termasuk komisi & swap)
void RiskOnPositionClosed(const double netProfit)
  {
   datetime now = NowServer();
   if(netProfit < 0)
     {
      g_consecLoss++;
      g_cooldownUntil = now + InpCooldownLossMin * 60;
      if(g_consecLoss >= InpConsecLossStop)
         RiskHalt(GPS_HALT_CONSEC_LOSS);
      else if(g_consecLoss == InpConsecLossPause)
        {
         g_pauseUntil = now + InpConsecPauseMin * 60;
         BusEvent("warning", "CONSEC_LOSS_PAUSE",
                  IntegerToString(g_consecLoss) + " loss beruntun, pause s/d " + TimeToString(g_pauseUntil, TIME_MINUTES));
        }
     }
   else
     {
      g_consecLoss    = 0;
      g_cooldownUntil = now + InpCooldownMin * 60;
     }
   RiskSave();
  }

bool RiskAllowsNew(string &why)
  {
   datetime now = NowServer();
   if(g_locked)            { why = "TERKUNCI: max drawdown (unlock dari web)"; return false; }
   if(g_dayHalt)           { why = "berhenti hari ini: " + HaltName(g_haltCode); return false; }
   if(g_autoPaused)        { why = "AUTO-PAUSE: kualitas eksekusi buruk"; return false; }
   if(g_extPause)          { why = "PAUSE dari web"; return false; }
   if(now < g_pauseUntil)  { why = "pause loss beruntun s/d " + TimeToString(g_pauseUntil, TIME_MINUTES); return false; }
   if(now < g_cooldownUntil) { why = "cooldown s/d " + TimeToString(g_cooldownUntil, TIME_SECONDS); return false; }
   if(ArraySize(g_entryTimes) >= InpMaxTradesDay) { why = "batas trade harian tercapai"; return false; }
   if(TradesLastHour(now) >= InpMaxTradesHour)    { why = "batas trade per jam tercapai"; return false; }
   return true;
  }

//--- position sizing -----------------------------------------------------
double TickValueLoss()
  {
   double tv = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0)
      tv = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   return tv;
  }

// Komisi round-turn per lot dikonversi ke jarak harga
double CommissionPrice()
  {
   double tv = TickValueLoss();
   if(tv <= 0 || g_tickSize <= 0)
      return 0;
   return InpCommissionPerLot * g_tickSize / tv;
  }

double CalcLot(const double slDist, const double spread)
  {
   double vmin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double lot;

   if(InpLotMode == GPS_LOT_FIXED)
      lot = InpFixedLot;
   else
     {
      double riskPct = MathMin(MathMax(InpRiskPct, 0.01), 1.5);   // batas keras 1.5%
      double riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0;
      double tv = TickValueLoss();
      if(tv <= 0 || g_tickSize <= 0)
         return 0;
      double lossPerLot = ((slDist + spread) / g_tickSize) * tv + InpCommissionPerLot;
      if(lossPerLot <= 0)
         return 0;
      lot = riskAmt / lossPerLot;
     }

   lot = MathMin(lot, MathMin(vmax, InpMaxLot));
   lot = NormVolFloor(lot);
   if(lot < vmin - 1e-9)
      return 0;                        // jangan paksa lot minimum di atas risiko
   return lot;
  }

bool MarginOK(const int dir, const double lot, const double price)
  {
   double m = 0;
   if(!OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, g_sym, lot, price, m))
      return false;
   if(m > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      return false;
   double used = AccountInfoDouble(ACCOUNT_MARGIN) + m;
   if(used <= 0)
      return true;
   return (AccountInfoDouble(ACCOUNT_EQUITY) / used * 100.0 >= InpMinMarginLevel);
  }

#endif
