//+------------------------------------------------------------------+
//| GoldPilot Scalper — enum & struktur bersama                      |
//| File ini di-include SEBELUM deklarasi input.                     |
//+------------------------------------------------------------------+
#ifndef GPS_DEFINES_MQH
#define GPS_DEFINES_MQH

#define GPS_VERSION "1.00"

enum ENUM_GPS_GMT_MODE
  {
   GPS_GMT_AUTO   = 0,   // Otomatis (live); backtest pakai setelan manual
   GPS_GMT_MANUAL = 1    // Manual (offset + DST di bawah)
  };

enum ENUM_GPS_DST
  {
   GPS_DST_NONE = 0,     // Tanpa DST
   GPS_DST_US   = 1,     // DST Amerika (mayoritas broker GMT+2/+3)
   GPS_DST_EU   = 2      // DST Eropa
  };

enum ENUM_GPS_TP_MODE
  {
   GPS_TP_SINGLE  = 0,   // TP tunggal
   GPS_TP_PARTIAL = 1    // Partial close + runner trailing
  };

enum ENUM_GPS_LOT_MODE
  {
   GPS_LOT_RISK  = 0,    // Risiko % equity
   GPS_LOT_FIXED = 1     // Lot tetap (untuk testing)
  };

// Kode setup: 1 = A (Momentum Pullback), 2 = B (Squeeze Breakout), 3 = C (Mean Reversion)
struct GpsSignal
  {
   bool     valid;
   int      dir;        // 1 = buy, -1 = sell
   int      setup;
   datetime barTime;    // waktu bar M1 saat sinyal dibuat (bar 0)
   datetime created;
   double   refClose;   // close bar konfirmasi
   double   atr;        // ATR(14) M1 bar konfirmasi
   double   swingLow;
   double   swingHigh;
   double   target;     // target harga khusus setup C (0 = pakai R)
   long     id;
  };

#endif
