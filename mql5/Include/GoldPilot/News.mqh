//+------------------------------------------------------------------+
//| GoldPilot Scalper — filter berita high-impact USD                |
//| Sumber:                                                          |
//|  1. Kalender ekonomi bawaan MT5 (live saja)                      |
//|  2. File CSV di Common\Files (untuk backtest / dari EA Bridge)   |
//|     format: waktu_utc,currency,impact,judul                      |
//|     contoh: 2024.01.05 13:30,USD,high,Non-Farm Payrolls          |
//+------------------------------------------------------------------+
#ifndef GPS_NEWS_MQH
#define GPS_NEWS_MQH

datetime g_newsTime[];    // waktu server, terurut
string   g_newsTitle[];
int      g_newsIdx    = 0;
datetime g_newsLoaded = 0;

void NewsAdd(const datetime srvTime, const string title)
  {
   int n = ArraySize(g_newsTime);
   for(int i = 0; i < n; i++)
      if(g_newsTime[i] == srvTime)
         return;                       // hindari duplikat
   ArrayResize(g_newsTime, n + 1);
   ArrayResize(g_newsTitle, n + 1);
   g_newsTime[n]  = srvTime;
   g_newsTitle[n] = title;
  }

void NewsSort()
  {
   int n = ArraySize(g_newsTime);
   for(int i = 1; i < n; i++)
     {
      datetime t = g_newsTime[i];
      string   s = g_newsTitle[i];
      int j = i - 1;
      while(j >= 0 && g_newsTime[j] > t)
        {
         g_newsTime[j + 1]  = g_newsTime[j];
         g_newsTitle[j + 1] = g_newsTitle[j];
         j--;
        }
      g_newsTime[j + 1]  = t;
      g_newsTitle[j + 1] = s;
     }
  }

void NewsLoadCalendar()
  {
   if(g_tester)
      return;                          // kalender MT5 tidak tersedia di Strategy Tester
   MqlCalendarValue vals[];
   datetime from = NowServer() - 86400;
   datetime to   = NowServer() + 8 * 86400;
   if(!CalendarValueHistory(vals, from, to, NULL, "USD"))
      return;
   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      NewsAdd(vals[i].time, ev.name);  // waktu kalender = waktu server
     }
  }

void NewsLoadCSV()
  {
   if(InpNewsFile == "" || !FileIsExist(InpNewsFile, FILE_COMMON))
      return;
   int h = FileOpen(InpNewsFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string line = Trim(FileReadString(h));
      if(line == "")
         continue;
      ushort c0 = StringGetCharacter(line, 0);
      if(c0 < '0' || c0 > '9')
         continue;                     // header / komentar
      string f[];
      int n = StringSplit(line, ',', f);
      datetime utc = StringToTime(Trim(f[0]));
      if(utc <= 0)
         continue;
      string cur = (n > 1) ? Trim(f[1]) : "USD";
      string imp = (n > 2) ? Trim(f[2]) : "high";
      StringToUpper(cur);
      StringToLower(imp);
      if(cur != "USD" || imp != "high")
         continue;
      string title = (n > 3) ? Trim(f[3]) : "High impact USD";
      NewsAdd(utc + UTCToServerShift(utc), title);
     }
   FileClose(h);
  }

void NewsLoad()
  {
   ArrayResize(g_newsTime, 0);
   ArrayResize(g_newsTitle, 0);
   if(InpUseNews)
     {
      NewsLoadCalendar();
      NewsLoadCSV();
      NewsSort();
     }
   g_newsIdx    = 0;
   g_newsLoaded = NowServer();
   if(InpUseNews)
      Log("Berita high-impact dimuat: " + IntegerToString(ArraySize(g_newsTime)));
  }

void NewsAdvance(const datetime now)
  {
   int n = ArraySize(g_newsTime);
   while(g_newsIdx < n && g_newsTime[g_newsIdx] + InpNewsAfterMin * 60 < now)
      g_newsIdx++;
  }

bool NewsBlocked(const datetime now, string &why)
  {
   NewsAdvance(now);
   int n = ArraySize(g_newsTime);
   for(int j = g_newsIdx; j < n && g_newsTime[j] - InpNewsBeforeMin * 60 <= now; j++)
     {
      if(now >= g_newsTime[j] - InpNewsBeforeMin * 60 && now <= g_newsTime[j] + InpNewsAfterMin * 60)
        {
         why = "jendela berita: " + g_newsTitle[j] + " " + TimeToString(g_newsTime[j], TIME_MINUTES);
         return true;
        }
     }
   return false;
  }

// true jika posisi terbuka harus ditutup karena berita segera rilis
bool NewsCloseWindow(const datetime now)
  {
   NewsAdvance(now);
   int n = ArraySize(g_newsTime);
   for(int j = g_newsIdx; j < n && g_newsTime[j] - InpNewsCloseBeforeMin * 60 <= now; j++)
      if(now >= g_newsTime[j] - InpNewsCloseBeforeMin * 60 && now < g_newsTime[j])
         return true;
   return false;
  }

string NewsNextText(const datetime now)
  {
   NewsAdvance(now);
   if(g_newsIdx >= ArraySize(g_newsTime))
      return "-";
   return TimeToString(g_newsTime[g_newsIdx], TIME_DATE | TIME_MINUTES) + " " + g_newsTitle[g_newsIdx];
  }

#endif
