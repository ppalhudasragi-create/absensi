//+------------------------------------------------------------------+
//| GoldPilot Scalper — utilitas: waktu/GMT, sesi, GV state, JSON    |
//+------------------------------------------------------------------+
#ifndef GPS_UTILS_MQH
#define GPS_UTILS_MQH

string   g_sym         = "";
int      g_digits      = 2;
double   g_point       = 0.01;
double   g_tickSize    = 0.01;
bool     g_tester      = false;
bool     g_optim       = false;
bool     g_visual      = false;
long     g_login       = 0;
string   g_statePrefix = "";   // GlobalVariable state milik EA ini (login + magic)
string   g_flagPrefix  = "";   // GlobalVariable flag yang ditulis EA Bridge (login)
int      g_gmtOffset   = 0;    // detik: waktu server - GMT
string   g_lastReject  = "";
string   g_lastSignal  = "";

// sesi yang sudah di-parse (menit dalam hari)
int g_lonS = -1, g_lonE = -1, g_nyS = -1, g_nyE = -1, g_asS = -1, g_asE = -1;
int g_rollS = -1, g_rollE = -1, g_friClose = -1;

//--- logging -------------------------------------------------------
void Log(const string msg)
  {
   if(!g_optim)
      Print("[GPS] ", msg);
  }

void SetReject(const string why)
  {
   if(why != g_lastReject)
     {
      g_lastReject = why;
      Log("Entry ditolak: " + why);
     }
  }

string Trim(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

string SetupName(const int code)
  {
   if(code == 1) return "A";
   if(code == 2) return "B";
   if(code == 3) return "C";
   return "?";
  }

//--- harga & volume ------------------------------------------------
double NormPrice(const double p)
  {
   if(g_tickSize <= 0)
      return NormalizeDouble(p, g_digits);
   return NormalizeDouble(MathRound(p / g_tickSize) * g_tickSize, g_digits);
  }

int VolDigits(const double step)
  {
   int d = 0;
   while(d < 8 && MathAbs(step * MathPow(10, d) - MathRound(step * MathPow(10, d))) > 1e-9)
      d++;
   return d;
  }

double NormVolFloor(const double v)
  {
   double step = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   double r = MathFloor(v / step + 1e-9) * step;
   return NormalizeDouble(r, VolDigits(step));
  }

//--- waktu -----------------------------------------------------------
datetime MakeDate(const int y, const int m, const int d)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year = y;
   s.mon  = m;
   s.day  = d;
   return StructToTime(s);
  }

int DayOfWeekOf(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_week;
  }

int MinuteOfDay(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour * 60 + s.min;
  }

int YearOf(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.year;
  }

int DayKey(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.year * 10000 + s.mon * 100 + s.day;
  }

datetime DayStart(const datetime t)
  {
   return (datetime)((long)t - ((long)t % 86400));
  }

// Minggu ke-n pada bulan tertentu (00:00)
datetime NthSunday(const int y, const int m, const int n)
  {
   datetime first = MakeDate(y, m, 1);
   int dow = DayOfWeekOf(first);
   int add = (7 - dow) % 7;
   return first + (add + (n - 1) * 7) * 86400;
  }

// Minggu terakhir pada bulan tertentu (00:00)
datetime LastSunday(const int y, const int m)
  {
   int ny = (m == 12) ? y + 1 : y;
   int nm = (m == 12) ? 1 : m + 1;
   datetime lastDay = MakeDate(ny, nm, 1) - 86400;
   return lastDay - DayOfWeekOf(lastDay) * 86400;
  }

bool IsDST(const datetime utc, const ENUM_GPS_DST mode)
  {
   int y = YearOf(utc);
   if(mode == GPS_DST_US)
     {
      datetime st = NthSunday(y, 3, 2) + 7 * 3600;    // 02:00 EST = 07:00 UTC
      datetime en = NthSunday(y, 11, 1) + 6 * 3600;   // 02:00 EDT = 06:00 UTC
      return (utc >= st && utc < en);
     }
   if(mode == GPS_DST_EU)
     {
      datetime st = LastSunday(y, 3) + 3600;
      datetime en = LastSunday(y, 10) + 3600;
      return (utc >= st && utc < en);
     }
   return false;
  }

int GMTOffsetForUTC(const datetime utc)
  {
   return InpBrokerGMTWinter * 3600 + (IsDST(utc, InpBrokerDST) ? 3600 : 0);
  }

void UpdateGMTOffset()
  {
   if(InpGMTMode == GPS_GMT_AUTO && !g_tester)
     {
      long diff = (long)TimeTradeServer() - (long)TimeGMT();
      g_gmtOffset = (int)(MathRound(diff / 900.0) * 900);
      return;
     }
   datetime approxUtc = TimeTradeServer() - InpBrokerGMTWinter * 3600;
   g_gmtOffset = GMTOffsetForUTC(approxUtc);
  }

datetime NowServer() { return TimeTradeServer(); }
datetime NowGMT()    { return TimeTradeServer() - g_gmtOffset; }
long     NowUTCLong() { return (long)NowGMT(); }

// selisih UTC -> server untuk waktu UTC tertentu (dipakai data berita)
int UTCToServerShift(const datetime utc)
  {
   if(InpGMTMode == GPS_GMT_AUTO && !g_tester)
      return g_gmtOffset;
   return GMTOffsetForUTC(utc);
  }

//--- sesi ------------------------------------------------------------
int ParseHHMM(const string s)
  {
   string parts[];
   if(StringSplit(Trim(s), ':', parts) != 2)
      return -1;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
  }

bool InWindow(const int nowMin, const int startMin, const int endMin)
  {
   if(startMin < 0 || endMin < 0)
      return false;
   if(startMin <= endMin)
      return (nowMin >= startMin && nowMin < endMin);
   return (nowMin >= startMin || nowMin < endMin);   // melewati tengah malam
  }

bool ParseSessions()
  {
   g_lonS  = ParseHHMM(InpLondonStart);   g_lonE  = ParseHHMM(InpLondonEnd);
   g_nyS   = ParseHHMM(InpNYStart);       g_nyE   = ParseHHMM(InpNYEnd);
   g_asS   = ParseHHMM(InpAsiaStart);     g_asE   = ParseHHMM(InpAsiaEnd);
   g_rollS = ParseHHMM(InpRolloverStart); g_rollE = ParseHHMM(InpRolloverEnd);
   g_friClose = (InpFridayCloseGMT == "") ? -1 : ParseHHMM(InpFridayCloseGMT);
   if((InpUseLondon && (g_lonS < 0 || g_lonE < 0)) ||
      (InpUseNY && (g_nyS < 0 || g_nyE < 0)) ||
      (InpUseAsia && (g_asS < 0 || g_asE < 0)))
     {
      Log("Format jam sesi salah, gunakan HH:MM");
      return false;
     }
   return true;
  }

string ActiveSessionName()
  {
   int m = MinuteOfDay(NowGMT());
   if(InpUseLondon && InWindow(m, g_lonS, g_lonE)) return "London";
   if(InpUseNY && InWindow(m, g_nyS, g_nyE))       return "New York";
   if(InpUseAsia && InWindow(m, g_asS, g_asE))     return "Asia";
   return "-";
  }

bool SessionOpen(string &why)
  {
   datetime gmt = NowGMT();
   int dow = DayOfWeekOf(gmt);
   int m   = MinuteOfDay(gmt);
   if(dow == 0 || dow == 6)
     { why = "weekend"; return false; }
   if(dow == 5 && m >= InpFridayNoNewGMT * 60)
     { why = "Jumat sore: tidak buka posisi baru"; return false; }
   if(InWindow(MinuteOfDay(NowServer()), g_rollS, g_rollE))
     { why = "jam rollover (spread lebar)"; return false; }
   if(ActiveSessionName() == "-")
     { why = "di luar sesi trading"; return false; }
   return true;
  }

bool FridayCloseDue()
  {
   if(g_friClose < 0)
      return false;
   datetime gmt = NowGMT();
   return (DayOfWeekOf(gmt) == 5 && MinuteOfDay(gmt) >= g_friClose);
  }

//--- GlobalVariable state ----------------------------------------------
double StGet(const string k, const double def)
  {
   string n = g_statePrefix + k;
   if(GlobalVariableCheck(n))
      return GlobalVariableGet(n);
   return def;
  }

void StSet(const string k, const double v) { GlobalVariableSet(g_statePrefix + k, v); }

string TkName(const long pid, const string k) { return g_statePrefix + "T" + IntegerToString(pid) + "_" + k; }

double TkGet(const long pid, const string k, const double def)
  {
   string n = TkName(pid, k);
   if(GlobalVariableCheck(n))
      return GlobalVariableGet(n);
   return def;
  }

void TkSet(const long pid, const string k, const double v) { GlobalVariableSet(TkName(pid, k), v); }

void TkDelAll(const long pid) { GlobalVariablesDeleteAll(g_statePrefix + "T" + IntegerToString(pid) + "_"); }

bool FlagGet(const string k)
  {
   string n = g_flagPrefix + k;
   return (GlobalVariableCheck(n) && GlobalVariableGet(n) > 0.5);
  }

void FlagSet(const string k, const double v) { GlobalVariableSet(g_flagPrefix + k, v); }

//--- JSON sederhana ---------------------------------------------------
string JEsc(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   return s;
  }

string JS(const string k, const string v)            { return "\"" + k + "\":\"" + JEsc(v) + "\""; }
string JN(const string k, const double v, const int d) { return "\"" + k + "\":" + DoubleToString(v, d); }
string JI(const string k, const long v)                { return "\"" + k + "\":" + IntegerToString(v); }
string JB(const string k, const bool v)                { return "\"" + k + "\":" + (v ? "true" : "false"); }

#endif
