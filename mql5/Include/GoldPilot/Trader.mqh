//+------------------------------------------------------------------+
//| GoldPilot Scalper — eksekusi order, manajemen posisi,            |
//| kualitas eksekusi                                                |
//+------------------------------------------------------------------+
#ifndef GPS_TRADER_MQH
#define GPS_TRADER_MQH

#include <Trade/Trade.mqh>

// bit flag per posisi (disimpan di GlobalVariable)
#define GPS_F_BE      1
#define GPS_F_PARTIAL 2
#define GPS_F_TRAIL   4

CTrade   g_trade;

double   g_slipBuf[];
double   g_msBuf[];
int      g_eqHead = 0, g_eqCount = 0;

ulong    g_modTicket[];
ulong    g_modTime[];     // GetTickCount64 terakhir modify (throttle)
long     g_rsnPid[];
string   g_rsnText[];

void TrInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)MathMax(1, MathRound(InpMaxSlippage / g_point)));
   g_trade.SetTypeFillingBySymbol(g_sym);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   int n = MathMax(InpExecSamples, 5);
   ArrayResize(g_slipBuf, n);
   ArrayResize(g_msBuf, n);
   g_eqHead = 0;
   g_eqCount = 0;
  }

//--- kualitas eksekusi ------------------------------------------------
void EqReset() { g_eqHead = 0; g_eqCount = 0; }

void EqAdd(const double slip, const double ms)
  {
   int n = ArraySize(g_slipBuf);
   g_slipBuf[g_eqHead] = slip;
   g_msBuf[g_eqHead]   = ms;
   g_eqHead = (g_eqHead + 1) % n;
   if(g_eqCount < n) g_eqCount++;
  }

double EqAvgSlip()
  {
   if(g_eqCount == 0) return 0;
   double s = 0;
   for(int i = 0; i < g_eqCount; i++) s += g_slipBuf[i];
   return s / g_eqCount;
  }

double EqAvgMs()
  {
   if(g_eqCount == 0) return 0;
   double s = 0;
   for(int i = 0; i < g_eqCount; i++) s += g_msBuf[i];
   return s / g_eqCount;
  }

double EstSlippage()
  {
   return (g_eqCount >= 5) ? MathMax(EqAvgSlip(), 0) : InpEstSlippage;
  }

void EqCheck()
  {
   if(g_eqCount < 10 || g_autoPaused)
      return;
   bool badSlip = (EqAvgSlip() > InpMaxAvgSlippage);
   bool badMs   = (!g_tester && EqAvgMs() > InpMaxAvgExecMs);
   if(badSlip || badMs)
     {
      g_autoPaused = true;
      RiskSave();
      BusEvent("critical", "AUTO_PAUSE",
               StringFormat("Kualitas eksekusi buruk: slippage rata-rata %.3f, eksekusi %.0f ms", EqAvgSlip(), EqAvgMs()));
     }
  }

//--- alasan exit (diisi sebelum EA menutup posisi) ------------------
void SetExitReason(const long pid, const string r)
  {
   int n = ArraySize(g_rsnPid);
   for(int i = 0; i < n; i++)
      if(g_rsnPid[i] == pid) { g_rsnText[i] = r; return; }
   ArrayResize(g_rsnPid, n + 1);
   ArrayResize(g_rsnText, n + 1);
   g_rsnPid[n]  = pid;
   g_rsnText[n] = r;
  }

string PopExitReason(const long pid)
  {
   int n = ArraySize(g_rsnPid);
   for(int i = 0; i < n; i++)
      if(g_rsnPid[i] == pid)
        {
         string r = g_rsnText[i];
         g_rsnPid[i]  = g_rsnPid[n - 1];
         g_rsnText[i] = g_rsnText[n - 1];
         ArrayResize(g_rsnPid, n - 1);
         ArrayResize(g_rsnText, n - 1);
         return r;
        }
   return "";
  }

//--- throttle modify (maks 1x per detik per posisi) ----------------------
bool ThrottleOK(const ulong tk)
  {
   ulong now = GetTickCount64();
   for(int i = 0; i < ArraySize(g_modTicket); i++)
      if(g_modTicket[i] == tk)
         return (now - g_modTime[i] >= 1000);
   return true;
  }

void MarkModified(const ulong tk)
  {
   ulong now = GetTickCount64();
   int n = ArraySize(g_modTicket);
   for(int i = 0; i < n; i++)
      if(g_modTicket[i] == tk) { g_modTime[i] = now; return; }
   if(n > 50)                          // buang entri lama
     {
      ArrayResize(g_modTicket, 0);
      ArrayResize(g_modTime, 0);
      n = 0;
     }
   ArrayResize(g_modTicket, n + 1);
   ArrayResize(g_modTime, n + 1);
   g_modTicket[n] = tk;
   g_modTime[n]   = now;
  }

//--- helper posisi ------------------------------------------------------
bool IsMine()
  {
   return (PositionGetString(POSITION_SYMBOL) == g_sym && PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

int CountMyPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine())
         n++;
   return n;
  }

bool PositionExistsById(const long pid)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_IDENTIFIER) == pid)
         return true;
   return false;
  }

double MyFloating()
  {
   double f = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && IsMine())
         f += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   return f;
  }

bool TradeDone()
  {
   uint rc = g_trade.ResultRetcode();
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED);
  }

bool ClosePos(const ulong tk, const long pid, const string reason)
  {
   SetExitReason(pid, reason);
   if(!g_trade.PositionClose(tk) || !TradeDone())
     {
      PopExitReason(pid);
      Log(StringFormat("Gagal menutup #%I64u (%s) retcode=%u", tk, reason, g_trade.ResultRetcode()));
      return false;
     }
   Log(StringFormat("Tutup #%I64u alasan=%s", tk, reason));
   return true;
  }

void CloseAll(const string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsMine())
         continue;
      ClosePos(tk, PositionGetInteger(POSITION_IDENTIFIER), reason);
     }
  }

// Modify SL dengan validasi stops/freeze level dan throttle
bool ModifySL(const ulong tk, const int dir, const double nsl, const double curSL, const double tp, const double px)
  {
   if(!ThrottleOK(tk))
      return false;
   double stops  = (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double freeze = (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_FREEZE_LEVEL) * g_point;
   if(dir > 0 && nsl > px - stops - g_tickSize) return false;
   if(dir < 0 && nsl < px + stops + g_tickSize) return false;
   if(freeze > 0 && curSL > 0 && MathAbs(px - curSL) <= freeze) return false;
   MarkModified(tk);
   return (g_trade.PositionModify(tk, nsl, tp) && TradeDone());
  }

//--- eksekusi sinyal ------------------------------------------------------
bool TrExecute(GpsSignal &s, string &why)
  {
   MqlTick t;
   if(!SymbolInfoTick(g_sym, t)) { why = "tidak ada tick"; return false; }
   double spread = t.ask - t.bid;
   double entry  = (s.dir > 0) ? t.ask : t.bid;

   // jangan mengejar harga
   if(MathAbs(entry - s.refClose) > InpSignalMaxDriftATR * s.atr)
     { why = "harga sudah bergerak terlalu jauh dari sinyal"; s.valid = false; return false; }

   // --- Stop loss: ATR vs swing, dibatasi Min/Max
   double swingDist = (s.dir > 0) ? entry - s.swingLow + spread : s.swingHigh - entry + spread;
   double slDist = MathMax(InpSL_ATRMult * s.atr, swingDist);
   double stops  = (double)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   slDist = MathMax(slDist, stops + spread + g_tickSize);
   if(slDist > InpMaxSL)
     { why = StringFormat("SL %.2f > MaxSL", slDist); s.valid = false; return false; }
   slDist = MathMax(slDist, InpMinSL);

   // --- Take profit
   double tpDist;
   if(s.setup == 3)
     {
      tpDist = (s.dir > 0) ? s.target - entry : entry - s.target;
      if(tpDist < InpC_MinRR * slDist)
        { why = "RR mean reversion kurang"; s.valid = false; return false; }
     }
   else
      tpDist = ((InpTPMode == GPS_TP_SINGLE) ? InpTP_R : InpRunnerTP_R) * slDist;
   double refTp = (s.setup == 3) ? tpDist : InpTP_R * slDist;

   // --- Spread relatif & cost filter (sinyal tetap valid, bisa dicoba tick berikutnya)
   if(spread > slDist * InpMaxSpreadPctSL / 100.0)
     { why = StringFormat("spread %.2f > %.0f%% SL", spread, InpMaxSpreadPctSL); return false; }
   double cost = spread + CommissionPrice() + EstSlippage();
   if(refTp < InpCostMultiple * cost)
     { why = StringFormat("biaya %.2f terlalu besar vs TP %.2f", cost, refTp); return false; }

   // --- Lot & margin
   double lot = CalcLot(slDist, spread);
   if(lot <= 0)
     { why = "lot hasil hitung < lot minimum (risiko terlalu kecil / SL lebar)"; s.valid = false; return false; }
   if(!MarginOK(s.dir, lot, entry))
     { why = "margin tidak cukup"; s.valid = false; return false; }

   double sl = NormPrice(entry - s.dir * slDist);
   double tp = NormPrice(entry + s.dir * tpDist);
   string cmt = "GPS|" + SetupName(s.setup) + "|" + IntegerToString(s.id);

   bool   ok = false, naked = false;
   double reqPrice = entry;
   ulong  t0 = 0;
   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(attempt > 0)
        {
         if(!g_tester) Sleep(50);
         if(!SymbolInfoTick(g_sym, t)) break;
         double e2 = (s.dir > 0) ? t.ask : t.bid;
         if(MathAbs(e2 - s.refClose) > InpSignalMaxDriftATR * s.atr) break;
         sl = NormPrice(sl + (e2 - entry));
         tp = NormPrice(tp + (e2 - entry));
         entry = e2;
         reqPrice = e2;
        }
      double tpSend = InpStealthTP ? 0 : tp;
      t0 = GetMicrosecondCount();
      ok = (s.dir > 0) ? g_trade.Buy(lot, g_sym, 0, sl, tpSend, cmt) : g_trade.Sell(lot, g_sym, 0, sl, tpSend, cmt);
      if(ok && TradeDone())
         break;
      ok = false;
      uint rc = g_trade.ResultRetcode();
      if(rc == TRADE_RETCODE_INVALID_STOPS)
        {
         // broker menolak SL/TP pada market order: buka dulu lalu pasang SL segera
         t0 = GetMicrosecondCount();
         ok = (s.dir > 0) ? g_trade.Buy(lot, g_sym, 0, 0, 0, cmt) : g_trade.Sell(lot, g_sym, 0, 0, 0, cmt);
         ok = ok && TradeDone();
         naked = ok;
         break;
        }
      if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED && rc != TRADE_RETCODE_PRICE_OFF)
         break;
     }

   if(!ok)
     {
      why = StringFormat("order gagal retcode=%u %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      s.valid = false;
      return false;
     }

   double ms   = (double)(GetMicrosecondCount() - t0) / 1000.0;
   double fill = g_trade.ResultPrice();
   if(fill <= 0) fill = reqPrice;
   double slip = s.dir * (fill - reqPrice);          // positif = merugikan

   long pid = 0;
   ulong deal = g_trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal))
      pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(pid == 0)
      pid = (long)g_trade.ResultOrder();

   // SL/TP relatif terhadap harga fill sebenarnya
   sl = NormPrice(fill - s.dir * slDist);
   tp = NormPrice(fill + s.dir * tpDist);

   if(naked)
     {
      bool modOk = false;
      for(int i = 0; i < 3 && !modOk; i++)
         modOk = (g_trade.PositionModify((ulong)pid, sl, InpStealthTP ? 0 : tp) && TradeDone());
      if(!modOk)
        {
         SetExitReason(pid, "no_sl");
         g_trade.PositionClose((ulong)pid);
         BusEvent("critical", "NO_SL", "Gagal memasang SL, posisi ditutup demi keamanan");
         s.valid = false;
         why = "gagal memasang SL";
         return false;
        }
     }

   TkSet(pid, "R", slDist);
   TkSet(pid, "F", 0);
   TkSet(pid, "S", s.setup);
   TkSet(pid, "TP", tp);
   TkSet(pid, "MFE", 0);
   TkSet(pid, "MAE", 0);

   EqAdd(slip, ms);
   EqCheck();

   g_lastSignal = StringFormat("%s %s %s lot=%.2f @%s SL=%s TP=%s", TimeToString(NowServer(), TIME_MINUTES),
                               SetupName(s.setup), s.dir > 0 ? "BUY" : "SELL", lot,
                               DoubleToString(fill, g_digits), DoubleToString(sl, g_digits), DoubleToString(tp, g_digits));
   Log("ENTRY " + g_lastSignal + StringFormat(" slip=%.3f exec=%.0fms spread=%.2f", slip, ms, spread));

   BusEmit("trade_open",
           JI("position_id", pid) + "," + JI("signal_id", s.id) + "," + JS("setup", SetupName(s.setup)) + "," +
           JS("side", s.dir > 0 ? "buy" : "sell") + "," + JN("lots", lot, 2) + "," +
           JN("request_price", reqPrice, g_digits) + "," + JN("open_price", fill, g_digits) + "," +
           JN("slippage", slip, g_digits) + "," + JN("exec_ms", ms, 1) + "," + JN("spread", spread, g_digits) + "," +
           JN("sl", sl, g_digits) + "," + JN("tp", tp, g_digits) + "," + JN("risk_dist", slDist, g_digits) + "," +
           JB("stealth_tp", InpStealthTP));

   s.valid = false;
   g_lastReject = "";
   return true;
  }

//--- manajemen posisi (setiap tick) -------------------------------------
void TrManage(const bool newBar)
  {
   datetime now = NowServer();
   bool newsClose = (InpUseNews && InpNewsClosePositions && NewsCloseWindow(now));
   bool friClose  = FridayCloseDue();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsMine())
         continue;

      int      dir  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double   open = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl   = PositionGetDouble(POSITION_SL);
      double   tp   = PositionGetDouble(POSITION_TP);
      double   vol  = PositionGetDouble(POSITION_VOLUME);
      datetime ot   = (datetime)PositionGetInteger(POSITION_TIME);
      long     pid  = PositionGetInteger(POSITION_IDENTIFIER);

      double risk = TkGet(pid, "R", 0);
      if(risk <= 0)
        {
         risk = (sl > 0) ? MathAbs(open - sl) : InpMinSL;
         if(risk <= 0) risk = InpMinSL;
         TkSet(pid, "R", risk);
        }
      int    flags = (int)TkGet(pid, "F", 0);
      double px    = (dir > 0) ? g_tick.bid : g_tick.ask;
      double move  = dir * (px - open);
      double curR  = move / risk;
      long   age   = (long)(now - ot);

      // MAE / MFE (dalam harga)
      if(move > TkGet(pid, "MFE", 0) + g_tickSize) TkSet(pid, "MFE", move);
      if(move < TkGet(pid, "MAE", 0) - g_tickSize) TkSet(pid, "MAE", move);

      if(newsClose)                                           { ClosePos(tk, pid, "news");   continue; }
      if(friClose)                                            { ClosePos(tk, pid, "friday"); continue; }
      if(age >= InpMaxHoldMin * 60)                           { ClosePos(tk, pid, "time");   continue; }
      if(age >= InpStaleMin * 60 && curR < InpStaleMinR)      { ClosePos(tk, pid, "stale");  continue; }
      if(InpStealthTP)
        {
         double stp = TkGet(pid, "TP", 0);
         if(stp > 0 && dir * (px - stp) >= 0)                  { ClosePos(tk, pid, "tp");     continue; }
        }

      // early exit: candle M1 kuat berlawanan sebelum posisi aman di BE
      if(newBar && InpUseEarlyExit && (flags & GPS_F_BE) == 0 && g_bar1Valid &&
         g_bar1.time >= (datetime)((long)ot - (long)ot % 60))
        {
         double rng  = g_bar1.high - g_bar1.low;
         double body = g_bar1.close - g_bar1.open;
         if(rng > 0 && MathAbs(body) >= rng * InpEarlyExitBodyPct / 100.0 && body * dir < 0)
           { ClosePos(tk, pid, "early"); continue; }
        }

      // partial close
      if(InpTPMode == GPS_TP_PARTIAL && (flags & GPS_F_PARTIAL) == 0 && curR >= InpPartialR)
        {
         double vmin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
         double cv   = NormVolFloor(vol * InpPartialPct / 100.0);
         if(cv >= vmin && vol - cv >= vmin - 1e-9)
           {
            if(g_trade.PositionClosePartial(tk, cv) && TradeDone())
              {
               flags |= GPS_F_PARTIAL;
               TkSet(pid, "F", flags);
               Log(StringFormat("Partial close #%I64u %.2f lot @%.1fR", tk, cv, curR));
               BusEmit("trade_partial", JI("position_id", pid) + "," + JN("lots", cv, 2) + "," +
                       JN("price", px, g_digits) + "," + JN("r", curR, 2));
              }
           }
         else
           {
            flags |= GPS_F_PARTIAL;   // volume terlalu kecil untuk dibagi
            TkSet(pid, "F", flags);
           }
        }

      // breakeven (+ biaya)
      if((flags & GPS_F_BE) == 0 && (curR >= InpBE_R || ((flags & GPS_F_PARTIAL) != 0 && InpTPMode == GPS_TP_PARTIAL)))
        {
         double be = NormPrice(open + dir * (g_curSpread + CommissionPrice()));
         if(sl == 0 || dir * (be - sl) > 0)
           {
            if(ModifySL(tk, dir, be, sl, tp, px))
              {
               flags |= GPS_F_BE;
               TkSet(pid, "F", flags);
               sl = be;
              }
           }
         else
           {
            flags |= GPS_F_BE;
            TkSet(pid, "F", flags);
           }
        }

      // trailing ATR
      if(curR >= InpTrailStartR && g_atr > 0)
        {
         double nsl = NormPrice(px - dir * InpTrailATRMult * g_atr);
         if(sl == 0 || dir * (nsl - sl) >= InpTrailStep)
            if(ModifySL(tk, dir, nsl, sl, tp, px))
              {
               flags |= (GPS_F_TRAIL | GPS_F_BE);
               TkSet(pid, "F", flags);
              }
        }
     }
  }

#endif
