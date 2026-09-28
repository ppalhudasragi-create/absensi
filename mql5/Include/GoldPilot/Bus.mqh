//+------------------------------------------------------------------+
//| GoldPilot Scalper — FileBus: komunikasi lokal ke EA Bridge       |
//| Scalper TIDAK memanggil WebRequest. Semua data ke web ditulis    |
//| sebagai file JSON di Common\Files\GoldPilot\<login>\ lalu        |
//| dikirim oleh EA Bridge.                                          |
//+------------------------------------------------------------------+
#ifndef GPS_BUS_MQH
#define GPS_BUS_MQH

bool   g_busOn  = false;
string g_busDir = "";
int    g_busSeq = 0;

void BusInit()
  {
   g_busOn = (InpUseBridge && !g_tester);
   if(!g_busOn)
      return;
   g_busDir = "GoldPilot\\" + IntegerToString(g_login) + "\\";
   FolderCreate("GoldPilot", FILE_COMMON);
   FolderCreate("GoldPilot\\" + IntegerToString(g_login), FILE_COMMON);
   FolderCreate(g_busDir + "outbox", FILE_COMMON);
  }

// Tulis atomik: .tmp lalu rename, supaya Bridge tidak membaca file setengah jadi
bool BusWriteFile(const string rel, const string content)
  {
   string tmp = g_busDir + rel + ".tmp";
   string dst = g_busDir + rel;
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      Log("Gagal menulis " + tmp + " err=" + IntegerToString(GetLastError()));
      return false;
     }
   FileWriteString(h, content);
   FileClose(h);
   if(!FileMove(tmp, FILE_COMMON, dst, FILE_COMMON | FILE_REWRITE))
     {
      Log("Gagal rename " + tmp + " err=" + IntegerToString(GetLastError()));
      return false;
     }
   return true;
  }

// Masukkan pesan ke outbox (trade_open, trade_close, trade_partial, event)
void BusEmit(const string kind, const string body)
  {
   if(!g_busOn)
      return;
   g_busSeq = (g_busSeq + 1) % 1000000;
   string name = "outbox\\" + IntegerToString((long)TimeTradeServer()) + "_" +
                 IntegerToString(g_busSeq, 6, '0') + "_" + kind + ".json";
   string json = "{" + JS("type", kind) + "," + JI("account", g_login) + "," +
                 JI("magic", InpMagic) + "," + JI("ts_utc", NowUTCLong()) +
                 (body == "" ? "" : "," + body) + "}";
   BusWriteFile(name, json);
  }

void BusEvent(const string level, const string code, const string msg)
  {
   Log("[" + level + "] " + code + ": " + msg);
   BusEmit("event", JS("level", level) + "," + JS("code", code) + "," + JS("message", msg));
  }

#endif
