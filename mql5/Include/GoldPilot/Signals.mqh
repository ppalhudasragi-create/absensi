//+------------------------------------------------------------------+
//| GoldPilot Scalper — sinyal entry (dihitung hanya saat bar M1 baru)|
//|  A: Momentum Pullback   B: Squeeze Breakout   C: Mean Reversion  |
//+------------------------------------------------------------------+
#ifndef GPS_SIGNALS_MQH
#define GPS_SIGNALS_MQH

long g_sigSeq = 0;

void SigBuild(GpsSignal &s, const int dir, const int setup, const MqlRates &r[], const double atr, const double target)
  {
   s.valid    = true;
   s.dir      = dir;
   s.setup    = setup;
   s.barTime  = r[0].time;
   s.created  = NowServer();
   s.refClose = r[1].close;
   s.atr      = atr;
   s.target   = target;
   double lo = r[1].low, hi = r[1].high;
   for(int i = 1; i <= InpSwingBars; i++)
     {
      lo = MathMin(lo, r[i].low);
      hi = MathMax(hi, r[i].high);
     }
   s.swingLow  = lo;
   s.swingHigh = hi;
   g_sigSeq++;
   s.id = ((long)r[0].time / 60) * 10 + setup;   // unik per bar + setup
  }

//--- Setup A: pullback ke EMA cepat searah bias, RSI reset, candle konfirmasi
bool SigSetupA(GpsSignal &out, const MqlRates &r[], const double atr, const double avgVol)
  {
   if(!InpUseSetupA || g_bias == 0)
      return false;
   double e9[], e21[], rsi[];
   if(!MsCopy(hEmaFastM1, 0, 6, e9) || !MsCopy(hEmaSlowM1, 0, 3, e21) || !MsCopy(hRsiM1, 0, 7, rsi))
      return false;

   double range1 = r[1].high - r[1].low;
   double body1  = MathAbs(r[1].close - r[1].open);
   bool volOk    = (avgVol > 0 && (double)r[1].tick_volume >= avgVol * InpA_VolMult);
   bool bodyOk   = (range1 > 0 && body1 >= range1 * InpA_MinBodyPct / 100.0);
   if(!volOk || !bodyOk)
      return false;

   if(g_bias > 0)
     {
      bool pulled = false;
      double mn = rsi[1];
      for(int i = 1; i <= 3; i++)
         if(r[i].low <= e9[i]) pulled = true;
      for(int i = 1; i <= 5; i++)
         mn = MathMin(mn, rsi[i]);
      bool rsiOk  = (mn >= InpA_RSIFloor && mn <= InpA_RSIPullback && rsi[1] > rsi[2]);
      bool candle = (r[1].close > r[1].open && r[1].close > r[2].high && r[1].close >= e21[1]);
      if(pulled && rsiOk && candle)
        {
         SigBuild(out, 1, 1, r, atr, 0);
         return true;
        }
     }
   else
     {
      bool pulled = false;
      double mx = rsi[1];
      for(int i = 1; i <= 3; i++)
         if(r[i].high >= e9[i]) pulled = true;
      for(int i = 1; i <= 5; i++)
         mx = MathMax(mx, rsi[i]);
      bool rsiOk  = (mx <= 100.0 - InpA_RSIFloor && mx >= 100.0 - InpA_RSIPullback && rsi[1] < rsi[2]);
      bool candle = (r[1].close < r[1].open && r[1].close < r[2].low && r[1].close <= e21[1]);
      if(pulled && rsiOk && candle)
        {
         SigBuild(out, -1, 1, r, atr, 0);
         return true;
        }
     }
   return false;
  }

//--- Setup B: Bollinger squeeze lalu breakout dengan body & volume kuat
bool SigSetupB(GpsSignal &out, const MqlRates &r[], const double atr, const double avgVol)
  {
   if(!InpUseSetupB || (g_bias == 0 && !InpB_AllowNeutral))
      return false;
   int n = InpB_Lookback + 2;
   double up[], lo[], mid[];
   if(!MsCopy(hBBM1, 1, n, up) || !MsCopy(hBBM1, 2, n, lo) || !MsCopy(hBBM1, 0, n, mid))
      return false;

   double w[];
   ArrayResize(w, n);
   for(int i = 1; i < n; i++)
      w[i] = (mid[i] > 0) ? (up[i] - lo[i]) / mid[i] : 0;

   // ambang persentil lebar band dari bar 2..Lookback+1
   double sorted[];
   ArrayResize(sorted, InpB_Lookback);
   for(int k = 0; k < InpB_Lookback; k++)
      sorted[k] = w[k + 2];
   ArraySort(sorted);
   int idx = (int)MathFloor(InpB_Percentile / 100.0 * (InpB_Lookback - 1));
   double thr = sorted[idx];

   int cnt = 0;
   for(int i = 2; i < n && cnt < 30; i++)
     {
      if(w[i] <= thr) cnt++;
      else break;
     }
   if(cnt < InpB_MinSqueezeBars)
      return false;

   double rh = r[2].high, rl = r[2].low;
   for(int i = 2; i < 2 + cnt; i++)
     {
      rh = MathMax(rh, r[i].high);
      rl = MathMin(rl, r[i].low);
     }

   double range1 = r[1].high - r[1].low;
   double body1  = MathAbs(r[1].close - r[1].open);
   double vm     = (g_bias == 0) ? InpB_VolMultNeutral : InpB_VolMult;
   bool bodyOk   = (range1 > 0 && body1 >= range1 * InpB_MinBodyPct / 100.0);
   bool volOk    = (avgVol > 0 && (double)r[1].tick_volume >= avgVol * vm);
   bool sizeOk   = (range1 <= InpB_MaxBarATR * atr);
   if(!bodyOk || !volOk || !sizeOk)
      return false;

   if(g_bias >= 0 && r[1].close > rh && r[1].close > r[1].open)
     {
      SigBuild(out, 1, 2, r, atr, 0);
      return true;
     }
   if(g_bias <= 0 && r[1].close < rl && r[1].close < r[1].open)
     {
      SigBuild(out, -1, 2, r, atr, 0);
      return true;
     }
   return false;
  }

//--- Setup C: mean reversion saat pasar ranging (default OFF)
bool SigSetupC(GpsSignal &out, const MqlRates &r[], const double atr)
  {
   if(!InpUseSetupC)
      return false;
   double adx[], cu[], cl[], cm[], rsi[];
   if(!MsCopy(hAdxM5, 0, 3, adx) || adx[1] >= InpC_MaxADX)
      return false;
   if(!MsCopy(hBBcM1, 1, 4, cu) || !MsCopy(hBBcM1, 2, 4, cl) || !MsCopy(hBBcM1, 0, 4, cm) || !MsCopy(hRsiM1, 0, 5, rsi))
      return false;

   double mnR = MathMin(rsi[1], MathMin(rsi[2], rsi[3]));
   double mxR = MathMax(rsi[1], MathMax(rsi[2], rsi[3]));
   bool touchLow  = (r[1].low <= cl[1] || r[2].low <= cl[2]);
   bool touchHigh = (r[1].high >= cu[1] || r[2].high >= cu[2]);

   if(touchLow && mnR < InpC_RSILow && r[1].close > r[1].open && r[1].close > cl[1])
     {
      SigBuild(out, 1, 3, r, atr, cm[1]);
      return true;
     }
   if(touchHigh && mxR > 100.0 - InpC_RSILow && r[1].close < r[1].open && r[1].close < cu[1])
     {
      SigBuild(out, -1, 3, r, atr, cm[1]);
      return true;
     }
   return false;
  }

// Evaluasi semua setup pada bar M1 yang baru saja close
bool SigEvaluate(GpsSignal &out)
  {
   out.valid = false;
   int need = MathMax(InpB_Lookback + 3, 40);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(g_sym, PERIOD_M1, 0, need, r) < need)
      return false;

   double atr = g_atr;
   if(atr <= 0)
      return false;

   g_bias = MsComputeBias((g_tick.bid + g_tick.ask) / 2.0);

   double avgVol = 0;
   for(int i = 2; i <= 21; i++)
      avgVol += (double)r[i].tick_volume;
   avgVol /= 20.0;

   if(SigSetupA(out, r, atr, avgVol)) return true;
   if(SigSetupB(out, r, atr, avgVol)) return true;
   if(SigSetupC(out, r, atr))         return true;
   return false;
  }

#endif
