//+------------------------------------------------------------------+
//| GoldPilot Scalper — kondisi pasar: tick, spread, indikator, VWAP |
//+------------------------------------------------------------------+
#ifndef GPS_MARKET_MQH
#define GPS_MARKET_MQH

#define GPS_TICKBUF 4096

int hEmaFastM1 = INVALID_HANDLE, hEmaSlowM1 = INVALID_HANDLE, hRsiM1 = INVALID_HANDLE;
int hAtrM1 = INVALID_HANDLE, hBBM1 = INVALID_HANDLE, hBBcM1 = INVALID_HANDLE;
int hEmaFastM5 = INVALID_HANDLE, hEmaSlowM5 = INVALID_HANDLE, hEmaM15 = INVALID_HANDLE, hAdxM5 = INVALID_HANDLE;

MqlTick  g_tick;
double   g_curSpread = 0;
double   g_spreadBuf[];
int      g_spreadHead = 0, g_spreadCount = 0, g_spreadSize = 200;
long     g_tickBuf[];
int      g_tickHead = 0, g_tickCount = 0;

double   g_atr  = 0;     // ATR(14) M1 bar terakhir yang close
double   g_vwap = 0;
int      g_bias = 0;     // 1 bullish, -1 bearish, 0 netral
MqlRates g_bar1;
bool     g_bar1Valid = false;

bool MsInit()
  {
   hEmaFastM1 = iMA(g_sym, PERIOD_M1, InpA_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlowM1 = iMA(g_sym, PERIOD_M1, InpA_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRsiM1     = iRSI(g_sym, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hAtrM1     = iATR(g_sym, PERIOD_M1, 14);
   hBBM1      = iBands(g_sym, PERIOD_M1, InpB_BBPeriod, 0, InpB_BBDev, PRICE_CLOSE);
   hBBcM1     = iBands(g_sym, PERIOD_M1, InpB_BBPeriod, 0, InpC_BBDev, PRICE_CLOSE);
   hEmaFastM5 = iMA(g_sym, PERIOD_M5, InpBiasFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlowM5 = iMA(g_sym, PERIOD_M5, InpBiasSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEmaM15    = iMA(g_sym, PERIOD_M15, InpBiasM15EMA, 0, MODE_EMA, PRICE_CLOSE);
   hAdxM5     = iADX(g_sym, PERIOD_M5, 14);

   if(hEmaFastM1 == INVALID_HANDLE || hEmaSlowM1 == INVALID_HANDLE || hRsiM1 == INVALID_HANDLE ||
      hAtrM1 == INVALID_HANDLE || hBBM1 == INVALID_HANDLE || hBBcM1 == INVALID_HANDLE ||
      hEmaFastM5 == INVALID_HANDLE || hEmaSlowM5 == INVALID_HANDLE || hEmaM15 == INVALID_HANDLE ||
      hAdxM5 == INVALID_HANDLE)
     {
      Log("Gagal membuat handle indikator, err=" + IntegerToString(GetLastError()));
      return false;
     }

   g_spreadSize = MathMax(InpSpreadBufferTicks, 20);
   ArrayResize(g_spreadBuf, g_spreadSize);
   ArrayResize(g_tickBuf, GPS_TICKBUF);
   return true;
  }

void MsRelease()
  {
   IndicatorRelease(hEmaFastM1); IndicatorRelease(hEmaSlowM1); IndicatorRelease(hRsiM1);
   IndicatorRelease(hAtrM1);     IndicatorRelease(hBBM1);      IndicatorRelease(hBBcM1);
   IndicatorRelease(hEmaFastM5); IndicatorRelease(hEmaSlowM5); IndicatorRelease(hEmaM15);
   IndicatorRelease(hAdxM5);
  }

bool MsReady()
  {
   return (BarsCalculated(hEmaFastM1) > 0 && BarsCalculated(hEmaSlowM1) > 0 &&
           BarsCalculated(hRsiM1) > 0 && BarsCalculated(hAtrM1) > 0 &&
           BarsCalculated(hBBM1) > InpB_Lookback + 2 && BarsCalculated(hBBcM1) > 0 &&
           BarsCalculated(hEmaFastM5) > 0 && BarsCalculated(hEmaSlowM5) > 0 &&
           BarsCalculated(hEmaM15) > 0 && BarsCalculated(hAdxM5) > 0);
  }

bool MsCopy(const int h, const int buf, const int count, double &arr[])
  {
   ArraySetAsSeries(arr, true);
   return (CopyBuffer(h, buf, 0, count, arr) == count);
  }

//--- dipanggil setiap tick -------------------------------------------
bool MsOnTick()
  {
   if(!SymbolInfoTick(g_sym, g_tick))
      return false;
   g_curSpread = g_tick.ask - g_tick.bid;

   g_spreadBuf[g_spreadHead] = g_curSpread;
   g_spreadHead = (g_spreadHead + 1) % g_spreadSize;
   if(g_spreadCount < g_spreadSize)
      g_spreadCount++;

   g_tickBuf[g_tickHead] = g_tick.time_msc;
   g_tickHead = (g_tickHead + 1) % GPS_TICKBUF;
   if(g_tickCount < GPS_TICKBUF)
      g_tickCount++;
   return true;
  }

double MsAvgSpread()
  {
   if(g_spreadCount == 0)
      return g_curSpread;
   double s = 0;
   for(int i = 0; i < g_spreadCount; i++)
      s += g_spreadBuf[i];
   return s / g_spreadCount;
  }

int MsTicksLastMinute()
  {
   long now = g_tick.time_msc;
   int n = 0;
   for(int k = 0; k < g_tickCount; k++)
     {
      int idx = (g_tickHead - 1 - k + GPS_TICKBUF) % GPS_TICKBUF;
      if(now - g_tickBuf[idx] > 60000)
         break;
      n++;
     }
   return n;
  }

//--- dipanggil setiap bar M1 baru -------------------------------------
void MsUpdateBar()
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   g_bar1Valid = (CopyRates(g_sym, PERIOD_M1, 1, 1, r) == 1);
   if(g_bar1Valid)
      g_bar1 = r[0];

   double a[];
   if(MsCopy(hAtrM1, 0, 3, a))
      g_atr = a[1];
  }

// VWAP harian (reset 00:00 GMT) dari tick volume M1
void MsUpdateVWAP()
  {
   datetime srv  = NowServer();
   datetime from = DayStart(srv - g_gmtOffset) + g_gmtOffset;
   MqlRates r[];
   int n = CopyRates(g_sym, PERIOD_M1, from, srv, r);
   double pv = 0, v = 0;
   for(int i = 0; i < n; i++)
     {
      double tp = (r[i].high + r[i].low + r[i].close) / 3.0;
      pv += tp * (double)r[i].tick_volume;
      v  += (double)r[i].tick_volume;
     }
   g_vwap = (v > 0) ? pv / v : 0;
  }

// Bias micro-trend: EMA M5 + slope + posisi terhadap EMA M15 + VWAP
int MsComputeBias(const double price)
  {
   double f[], s[], e15[];
   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(!MsCopy(hEmaFastM5, 0, 5, f) || !MsCopy(hEmaSlowM5, 0, 3, s) || !MsCopy(hEmaM15, 0, 3, e15))
      return 0;
   if(CopyRates(g_sym, PERIOD_M15, 0, 3, m15) < 3)
      return 0;

   bool up = (f[1] > s[1] && f[1] > f[3] && m15[1].close > e15[1]);
   bool dn = (f[1] < s[1] && f[1] < f[3] && m15[1].close < e15[1]);
   if(InpUseVWAP && g_vwap > 0)
     {
      if(up && price < g_vwap) up = false;
      if(dn && price > g_vwap) dn = false;
     }
   if(up) return 1;
   if(dn) return -1;
   return 0;
  }

#endif
