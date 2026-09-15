//+------------------------------------------------------------------+
//|                                                     AQ_ApexEA.mq5|
//|        APEX QUANTUM — Expert Advisor for the Apex Quantum engine |
//|                                                                  |
//|  Trades the arrows produced by Indicators\ApexQuantum\AQ_Apex:   |
//|  it reads the engine through indicator handles (never through    |
//|  chart objects, so it behaves identically in the tester) and     |
//|  adds the execution layer: risk-sized volume, zone- or ATR-based |
//|  stops, break-even, partial close, trailing, session/spread/     |
//|  daily-loss guards and multi-symbol dispatch.                    |
//|                                                                  |
//|  Signals are taken from CLOSED bars only — the same bars the     |
//|  indicator draws its arrows on — so backtest and live agree.     |
//+------------------------------------------------------------------+
#property copyright "APEX QUANTUM"
#property version   "1.00"
#property description "Expert Advisor for the APEX QUANTUM confluence engine:"
#property description "graded supply/demand zones, trend rails, BOS/CHoCH, MTF score."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| CONTRACT — must mirror Indicators\ApexQuantum\AQ_Apex.mq5        |
//| (buffer map + the order of the ENGINE CORE input block)          |
//+------------------------------------------------------------------+
#define AQ_BUF_SIGNAL     8               // +1 buy, -1 sell, 0 none
#define AQ_BUF_SCORE      9               // -100 .. +100 confluence score
#define AQ_BUF_TREND     10               // +1 bullish rail, -1 bearish rail
#define AQ_BUF_DEM_TOP   11               // nearest demand zone, upper edge
#define AQ_BUF_DEM_BOT   12               // nearest demand zone, lower edge
#define AQ_BUF_SUP_TOP   13               // nearest supply zone, upper edge
#define AQ_BUF_SUP_BOT   14               // nearest supply zone, lower edge
#define AQ_BUF_ATR       17               // engine ATR

//--- mirrors ENUM_AQ_SIGNAL_MODE in the indicator (same ordinal values)
enum ENUM_AQEA_SIG_MODE
  {
   AQEA_SIG_PULLBACK = 0,   // Pullback into a zone with the trend
   AQEA_SIG_FLIP     = 1,   // Trend flip
   AQEA_SIG_BOTH     = 2    // Both models
  };

enum ENUM_AQEA_LOT
  {
   AQEA_LOT_FIXED = 0,      // Fixed lot
   AQEA_LOT_RISK  = 1       // Risk percent of equity
  };

enum ENUM_AQEA_SL
  {
   AQEA_SL_ATR   = 0,       // ATR multiple
   AQEA_SL_ZONE  = 1,       // Behind the signal zone (ATR fallback)
   AQEA_SL_FIXED = 2        // Fixed points
  };

enum ENUM_AQEA_TP
  {
   AQEA_TP_RR    = 0,       // Risk/reward multiple of the stop
   AQEA_TP_ATR   = 1,       // ATR multiple
   AQEA_TP_ZONE  = 2,       // Opposite zone (RR fallback)
   AQEA_TP_FIXED = 3,       // Fixed points
   AQEA_TP_NONE  = 4        // No take profit (manage by trail/exit)
  };

//+------------------------------------------------------------------+
//| CONFIG                                                           |
//+------------------------------------------------------------------+
input group "=== ENGINE (must match the indicator inputs) ==="
input string              InpIndPath       = "ApexQuantum\\AQ_Apex"; // Indicator path
input ENUM_TIMEFRAMES     InpTf            = PERIOD_CURRENT; // Signal timeframe
input int                 InpLookback      = 600;            // Bars analysed
input double              InpFractalFast   = 3.0;            // Minor fractal factor
input double              InpFractalSlow   = 6.0;            // Major fractal factor
input double              InpZoneFuzz      = 0.75;           // Zone thickness (ATR factor)
input bool                InpZoneMerge     = true;           // Merge overlapping zones
input bool                InpZoneExtend    = true;           // Pad zone by the fuzz distance
input int                 InpFastLen       = 3;              // Trend rail: fast length
input int                 InpSlowLen       = 7;              // Trend rail: slow length
input double              InpSarStep       = 0.02;           // Swing engine: SAR step
input double              InpSarMax        = 0.20;           // Swing engine: SAR maximum
input int                 InpAtrPeriod     = 14;             // ATR period
input bool                InpUseMtf        = true;           // Higher timeframe confirmation
input ENUM_TIMEFRAMES     InpMtf1          = PERIOD_CURRENT; // HTF 1 (CURRENT = auto x4)
input ENUM_TIMEFRAMES     InpMtf2          = PERIOD_CURRENT; // HTF 2 (CURRENT = auto x16)
input ENUM_AQEA_SIG_MODE  InpSigMode       = AQEA_SIG_BOTH;  // Entry model
input int                 InpMinScore      = 55;             // Minimum confluence score
input int                 InpCooldownBars  = 3;              // Bars between signals
input bool                InpConfirmCandle = true;           // Require a confirming candle

input group "=== SYMBOLS & IDENTITY ==="
input string InpSymbols   = "";                              // Symbols (comma separated, empty = chart)
input long   InpMagic     = 20260914;                        // Magic number
input string InpComment   = "APEX";                          // Order comment
input int    InpSlippage  = 15;                              // Slippage (points)

input group "=== MONEY & RISK ==="
input ENUM_AQEA_LOT InpLotMode   = AQEA_LOT_RISK;            // Volume model
input double        InpFixedLot  = 0.10;                     // Fixed lot
input double        InpRiskPct   = 1.0;                      // Risk per trade (% of equity)
input ENUM_AQEA_SL  InpSlMode    = AQEA_SL_ZONE;             // Stop loss model
input double        InpSlAtr     = 1.8;                      // SL = ATR x
input int           InpSlPoints  = 300;                      // SL fixed (points)
input double        InpSlBufAtr  = 0.25;                     // Zone SL buffer (ATR x)
input ENUM_AQEA_TP  InpTpMode    = AQEA_TP_RR;               // Take profit model
input double        InpTpRR      = 2.0;                      // TP = risk x
input double        InpTpAtr     = 3.0;                      // TP = ATR x
input int           InpTpPoints  = 600;                      // TP fixed (points)

input group "=== TRADE MANAGEMENT ==="
input bool   InpBeEnable      = true;                        // Break even
input double InpBeTriggerR    = 1.0;                         // Break even at (R)
input double InpBeOffsetAtr   = 0.10;                        // Break even offset (ATR x)
input bool   InpPartEnable    = true;                        // Partial close
input double InpPartTriggerR  = 1.0;                         // Partial close at (R)
input double InpPartPercent   = 50.0;                        // Partial close (% of volume)
input bool   InpTrailEnable   = true;                        // Trailing stop
input double InpTrailStartR   = 1.0;                         // Trail starts at (R)
input double InpTrailAtr      = 1.5;                         // Trail distance (ATR x)
input bool   InpCloseOnFlip   = true;                        // Close on opposite signal

input group "=== FILTERS & GUARDS ==="
input int    InpMaxSpreadPts  = 40;                          // Max spread (points)
input int    InpMaxTrades     = 3;                           // Max open trades (total)
input int    InpMaxPerSymbol  = 1;                           // Max open trades per symbol
input double InpMaxDailyLoss  = 3.0;                         // Max daily loss (% of day start, 0 = off)
input double InpMaxDailyProfit= 6.0;                         // Max daily profit (% of day start, 0 = off)
input bool   InpUseSession    = false;                       // Use trading session filter
input int    InpStartHour     = 7;                           // Session start hour (server)
input int    InpEndHour       = 21;                          // Session end hour (server)
input string InpDaysMask      = "12345";                     // Trading days (0=Sun .. 6=Sat)
input string InpBlackout      = "";                          // News blackout "HH:MM-HH:MM;..."

input group "=== NOTIFICATIONS ==="
input bool   InpAlerts        = true;                        // Terminal alerts
input bool   InpPush          = false;                       // Push notifications
input bool   InpTelegram      = false;                       // Telegram messages
input string InpTgToken       = "";                          // Telegram bot token
input string InpTgChatId      = "";                          // Telegram chat id
input bool   InpVerboseLog    = true;                        // Verbose journal logging

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
struct AQSymbol
  {
   string            name;
   int               handle;
   datetime          lastBar;
   bool              ready;
  };

struct AQPosFlag
  {
   ulong             ticket;
   bool              beDone;
   bool              partDone;
   double            risk0;           // stop distance as first seen — R never drifts
  };

struct AQEaState
  {
   AQSymbol          sym[];
   int               symCount;
   AQPosFlag         pos[];
   int               posCount;
   datetime          dayStamp;
   double            dayStartBalance;
   bool              halted;          // daily guard tripped
  };
AQEaState g_ea;

CTrade g_trade;

#define AQ_LOG "APEX EA: "

//+------------------------------------------------------------------+
//| CORE — helpers                                                   |
//+------------------------------------------------------------------+
void AQLog(const string text)
  {
   if(InpVerboseLog) Print(AQ_LOG, text);
  }

double NormalizeVolume(const string sym, double vol)
  {
   double minV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return(0.0);
   vol = MathFloor(vol / step) * step;                       // floor: never risk more than planned
   return(MathMin(MathMax(vol, minV), maxV));
  }

double NormalizePrice(const string sym, const double price)
  {
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(tick <= 0.0) return(price);
   return(MathRound(price / tick) * tick);                   // tick size, not just digits
  }

double MinStopDistance(const string sym)
  {
   long stops  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   long pts    = (long)MathMax(stops, freeze);
   if(pts == 0) pts = SymbolInfoInteger(sym, SYMBOL_SPREAD) * 3;   // brokers that report zero
   return(pts * SymbolInfoDouble(sym, SYMBOL_POINT));
  }

double LotsForRisk(const string sym, const double slDistance)
  {
   if(InpLotMode == AQEA_LOT_FIXED) return(NormalizeVolume(sym, InpFixedLot));

   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0) return(0.0);

   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return(0.0);
   return(NormalizeVolume(sym, riskMoney / lossPerLot));
  }

//+------------------------------------------------------------------+
//| CORE — session, day and news guards                              |
//+------------------------------------------------------------------+
datetime StartOfDay(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return(StructToTime(dt));
  }

bool DayAllowed(void)
  {
   if(!InpUseSession) return(true);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(StringFind(InpDaysMask, (string)dt.day_of_week) >= 0);
  }

bool SessionAllowed(void)
  {
   if(!InpUseSession) return(true);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpStartHour <= InpEndHour) return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
   return(dt.hour >= InpStartHour || dt.hour < InpEndHour);   // window wrapping midnight
  }

//--- manual news blackout: "13:25-13:45;15:55-16:20" in server time
bool BlackoutNow(void)
  {
   if(StringLen(InpBlackout) == 0) return(false);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;

   string spans[];
   int n = StringSplit(InpBlackout, StringGetCharacter(";", 0), spans);
   for(int i = 0; i < n; i++)
     {
      string s = spans[i];
      StringTrimLeft(s); StringTrimRight(s);                 // in place: they return an int
      if(StringLen(s) < 11) continue;
      string ab[];
      if(StringSplit(s, StringGetCharacter("-", 0), ab) != 2) continue;
      int a = (int)StringToInteger(StringSubstr(ab[0], 0, 2)) * 60 + (int)StringToInteger(StringSubstr(ab[0], 3, 2));
      int b = (int)StringToInteger(StringSubstr(ab[1], 0, 2)) * 60 + (int)StringToInteger(StringSubstr(ab[1], 3, 2));
      if(nowMin >= a && nowMin <= b) return(true);
     }
   return(false);
  }

//--- realised and floating result of this EA today
void DayResult(double &closedOut, double &floatingOut)
  {
   double closed = 0.0, floating = 0.0;
   datetime from = StartOfDay();

   if(HistorySelect(from, TimeCurrent() + 60))
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
         long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN) continue;                // opening deals carry no result
         closed += HistoryDealGetDouble(t, DEAL_PROFIT)
                 + HistoryDealGetDouble(t, DEAL_SWAP)
                 + HistoryDealGetDouble(t, DEAL_COMMISSION);
        }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }

   closedOut   = closed;
   floatingOut = floating;
  }

bool RiskGuardOk(void)
  {
   //--- reset the guard at the start of every server day
   datetime day = StartOfDay();
   if(g_ea.dayStamp != day)
     {
      double closed = 0.0, floating = 0.0;
      DayResult(closed, floating);
      g_ea.dayStamp        = day;
      g_ea.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - closed;
      g_ea.halted          = false;
     }
   if(InpMaxDailyLoss <= 0.0 && InpMaxDailyProfit <= 0.0) return(true);
   if(g_ea.halted) return(false);

   double base = (g_ea.dayStartBalance > 0.0) ? g_ea.dayStartBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   if(base <= 0.0) return(true);

   double closed = 0.0, floating = 0.0;
   DayResult(closed, floating);
   double pct = (closed + floating) / base * 100.0;

   if(InpMaxDailyLoss > 0.0 && pct <= -InpMaxDailyLoss)
     {
      g_ea.halted = true;
      AQLog(StringFormat("daily loss limit hit (%.2f%%) — no new trades today", pct));
      return(false);
     }
   if(InpMaxDailyProfit > 0.0 && pct >= InpMaxDailyProfit)
     {
      g_ea.halted = true;
      AQLog(StringFormat("daily profit target hit (%.2f%%) — no new trades today", pct));
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| CORE — position bookkeeping                                      |
//+------------------------------------------------------------------+
int PosIndex(const ulong ticket)
  {
   for(int i = 0; i < g_ea.posCount; i++)
      if(g_ea.pos[i].ticket == ticket) return(i);
   return(-1);
  }

int PosTouch(const ulong ticket, const double riskNow)
  {
   int idx = PosIndex(ticket);
   if(idx >= 0) return(idx);
   ArrayResize(g_ea.pos, g_ea.posCount + 1, 16);
   g_ea.pos[g_ea.posCount].ticket   = ticket;
   g_ea.pos[g_ea.posCount].beDone   = false;
   g_ea.pos[g_ea.posCount].partDone = false;
   g_ea.pos[g_ea.posCount].risk0    = riskNow;
   g_ea.posCount++;
   return(g_ea.posCount - 1);
  }

void PosPrune(void)
  {
   for(int i = g_ea.posCount - 1; i >= 0; i--)
     {
      if(PositionSelectByTicket(g_ea.pos[i].ticket)) continue;
      for(int k = i; k < g_ea.posCount - 1; k++) g_ea.pos[k] = g_ea.pos[k + 1];
      g_ea.posCount--;
     }
   ArrayResize(g_ea.pos, (int)MathMax(g_ea.posCount, 1), 16);
  }

int CountPositions(const string sym)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(sym != "" && PositionGetString(POSITION_SYMBOL) != sym) continue;
      n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| CORE — engine access                                             |
//+------------------------------------------------------------------+
bool ReadBuffer(const int handle, const int buffer, const int shift, double &value)
  {
   double v[1];
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1) return(false);
   value = v[0];
   return(true);
  }

//--- engine handle of a symbol, or INVALID_HANDLE
int HandleOf(const string sym)
  {
   for(int i = 0; i < g_ea.symCount; i++)
      if(g_ea.sym[i].name == sym) return(g_ea.sym[i].handle);
   return(INVALID_HANDLE);
  }

//+------------------------------------------------------------------+
//| NOTIFY                                                           |
//+------------------------------------------------------------------+
void SendTelegram(const string text)
  {
   //--- WebRequest is unavailable in the tester and needs the URL whitelisted
   //--- in Tools -> Options -> Expert Advisors
   if(!InpTelegram || MQLInfoInteger(MQL_TESTER)) return;
   if(StringLen(InpTgToken) == 0 || StringLen(InpTgChatId) == 0) return;

   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + InpTgChatId + "&text=" + text;
   char post[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string answer;
   StringToCharArray(body, post, 0, StringLen(body));
   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, result, answer);
   if(code != 200) PrintFormat("%sTelegram failed http=%d err=%d", AQ_LOG, code, GetLastError());
  }

void Notify(const string text)
  {
   if(InpAlerts && !MQLInfoInteger(MQL_OPTIMIZATION)) Alert(text);
   if(InpPush) SendNotification(text);
   SendTelegram(text);
   AQLog(text);
  }

//+------------------------------------------------------------------+
//| TRADE — entry                                                    |
//+------------------------------------------------------------------+
bool OpenTrade(const string sym, const int dir, const double atr,
               const double demTop, const double demBot,
               const double supTop, const double supBot, const int score)
  {
   bool   isBuy = (dir > 0);
   double price = SymbolInfoDouble(sym, isBuy ? SYMBOL_ASK : SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(price <= 0.0 || point <= 0.0 || atr <= 0.0) return(false);

   //--- stop distance
   double slDist = atr * InpSlAtr;
   if(InpSlMode == AQEA_SL_FIXED) slDist = InpSlPoints * point;
   else if(InpSlMode == AQEA_SL_ZONE)
     {
      double edge = isBuy ? demBot : supTop;
      if(edge > 0.0)
        {
         double d = isBuy ? (price - edge) : (edge - price);
         d += atr * InpSlBufAtr;                             // breathing room behind the zone
         if(d > 0.0) slDist = d;
        }
     }
   slDist = MathMax(slDist, MinStopDistance(sym));

   //--- target distance
   double tpDist = 0.0;
   switch(InpTpMode)
     {
      case AQEA_TP_RR:    tpDist = slDist * InpTpRR;       break;
      case AQEA_TP_ATR:   tpDist = atr * InpTpAtr;         break;
      case AQEA_TP_FIXED: tpDist = InpTpPoints * point;    break;
      case AQEA_TP_NONE:  tpDist = 0.0;                    break;
      case AQEA_TP_ZONE:
        {
         double target = isBuy ? supBot : demTop;
         tpDist = (target > 0.0) ? MathAbs(target - price) : slDist * InpTpRR;
         break;
        }
     }
   if(tpDist > 0.0) tpDist = MathMax(tpDist, MinStopDistance(sym));

   double sl = NormalizePrice(sym, isBuy ? price - slDist : price + slDist);
   double tp = (tpDist > 0.0) ? NormalizePrice(sym, isBuy ? price + tpDist : price - tpDist) : 0.0;

   double lot = LotsForRisk(sym, slDist);
   if(lot <= 0.0)
     {
      AQLog(sym + ": volume below the symbol minimum for this risk — trade skipped");
      return(false);
     }

   //--- margin pre-check
   double need = 0.0;
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(type, sym, lot, price, need) ||
      need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      AQLog(sym + ": not enough free margin — trade skipped");
      return(false);
     }

   g_trade.SetTypeFillingBySymbol(sym);
   string comment = InpComment + " " + (string)score;

   for(int attempt = 0; attempt < 3; attempt++)
     {
      bool ok = isBuy ? g_trade.Buy(lot, sym, 0.0, sl, tp, comment)
                      : g_trade.Sell(lot, sym, 0.0, sl, tp, comment);
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
        {
         Notify(StringFormat("%s %s %.2f @ %s  SL %s  TP %s  (score %d)",
                             sym, isBuy ? "BUY" : "SELL", lot,
                             DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                             DoubleToString(sl,    (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                             tp > 0.0 ? DoubleToString(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) : "-",
                             score));
         return(true);
        }
      if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED &&
         rc != TRADE_RETCODE_PRICE_OFF) break;               // not worth retrying
      price = SymbolInfoDouble(sym, isBuy ? SYMBOL_ASK : SYMBOL_BID);
     }

   PrintFormat("%s%s open failed retcode=%u (%s)", AQ_LOG, sym,
               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(false);
  }

//+------------------------------------------------------------------+
//| TRADE — break even, partial close, trailing                      |
//+------------------------------------------------------------------+
void ManagePositions(void)
  {
   PosPrune();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      long   type  = PositionGetInteger(POSITION_TYPE);
      bool   isBuy = (type == POSITION_TYPE_BUY);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = SymbolInfoDouble(sym, isBuy ? SYMBOL_BID : SYMBOL_ASK);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(price <= 0.0 || point <= 0.0) continue;

      double risk = MathAbs(open - sl);
      if(risk <= 0.0) continue;

      //--- R is measured against the stop distance as first seen, so moving the
      //--- stop to break even cannot inflate it
      int    idx  = PosTouch(ticket, risk);
      double r0   = (g_ea.pos[idx].risk0 > 0.0) ? g_ea.pos[idx].risk0 : risk;
      double move = isBuy ? (price - open) : (open - price);
      double rNow = move / r0;

      //--- live ATR from the engine; the stop distance is only the fallback
      double atr = r0 / MathMax(InpSlAtr, 0.1);
      int    hs  = HandleOf(sym);
      if(hs != INVALID_HANDLE)
        {
         double a = 0.0;
         if(ReadBuffer(hs, AQ_BUF_ATR, 1, a) && a > 0.0) atr = a;
        }
      double minDist = MinStopDistance(sym);

      //--- 1. partial close
      if(InpPartEnable && !g_ea.pos[idx].partDone && rNow >= InpPartTriggerR)
        {
         double part = NormalizeVolume(sym, vol * InpPartPercent / 100.0);
         double rest = vol - part;
         if(part > 0.0 && rest >= SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN))
           {
            if(g_trade.PositionClosePartial(ticket, part))
              {
               g_ea.pos[idx].partDone = true;
               Notify(StringFormat("%s partial close %.2f at %.2fR", sym, part, rNow));
               continue;                                     // volume changed, revisit next tick
              }
           }
         else
            g_ea.pos[idx].partDone = true;                   // cannot split this position
        }

      //--- 2. break even
      if(InpBeEnable && !g_ea.pos[idx].beDone && rNow >= InpBeTriggerR)
        {
         double off    = atr * InpBeOffsetAtr;
         double target = NormalizePrice(sym, isBuy ? open + off : open - off);
         bool   better = isBuy ? (target > sl + point) : (target < sl - point);
         bool   legal  = isBuy ? (price - target > minDist) : (target - price > minDist);
         if(better && legal && g_trade.PositionModify(ticket, target, tp))
           {
            g_ea.pos[idx].beDone = true;
            sl = target;
            AQLog(sym + ": stop moved to break even");
           }
        }

      //--- 3. trailing
      if(InpTrailEnable && rNow >= InpTrailStartR)
        {
         double dist   = atr * InpTrailAtr;
         double target = NormalizePrice(sym, isBuy ? price - dist : price + dist);
         bool   better = isBuy ? (target > sl + point) : (target < sl - point);
         bool   legal  = isBuy ? (price - target > minDist) : (target - price > minDist);
         if(better && legal)
            g_trade.PositionModify(ticket, target, tp);      // never sends a no-change modify
        }
     }
  }

void CloseSymbol(const string sym, const int dir, const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type == POSITION_TYPE_BUY);
      if(dir != 0 && ((dir > 0 && isBuy) || (dir < 0 && !isBuy))) continue;
      if(g_trade.PositionClose(t)) AQLog(sym + ": closed (" + why + ")");
     }
  }

//+------------------------------------------------------------------+
//| CORE — one symbol, one closed bar                                |
//+------------------------------------------------------------------+
void ProcessSymbol(const int s)
  {
   string sym = g_ea.sym[s].name;
   int    h   = g_ea.sym[s].handle;
   if(h == INVALID_HANDLE) return;

   ENUM_TIMEFRAMES tf = (InpTf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : InpTf;
   datetime cur = iTime(sym, tf, 0);
   if(cur == 0 || cur == g_ea.sym[s].lastBar) return;        // one decision per closed bar
   g_ea.sym[s].lastBar = cur;

   if(BarsCalculated(h) < 100) return;                       // engine still warming up

   double sig = 0.0, scr = 0.0, atr = 0.0;                   // shift 1 = last CLOSED bar
   if(!ReadBuffer(h, AQ_BUF_SIGNAL, 1, sig)) return;
   if(!ReadBuffer(h, AQ_BUF_SCORE,  1, scr)) return;
   if(!ReadBuffer(h, AQ_BUF_ATR,    1, atr)) return;
   if(atr <= 0.0) return;

   int dir   = (int)sig;
   int score = (int)scr;

   //--- exit before entry: an opposite arrow closes the running trade
   if(InpCloseOnFlip && dir != 0) CloseSymbol(sym, -dir, "opposite signal");
   if(dir == 0) return;

   //--- filters
   if(!RiskGuardOk())                                          return;
   if(!DayAllowed() || !SessionAllowed() || BlackoutNow())      return;
   if(SymbolInfoInteger(sym, SYMBOL_SPREAD) > InpMaxSpreadPts)
     {
      AQLog(sym + ": spread filter blocked the entry");
      return;
     }
   if(CountPositions("") >= InpMaxTrades)                       return;
   if(CountPositions(sym) >= InpMaxPerSymbol)                   return;
   if(MathAbs(score) < InpMinScore)                             return;

   double demTop = 0.0, demBot = 0.0, supTop = 0.0, supBot = 0.0;
   ReadBuffer(h, AQ_BUF_DEM_TOP, 0, demTop);                 // zero simply means "none in range"
   ReadBuffer(h, AQ_BUF_DEM_BOT, 0, demBot);
   ReadBuffer(h, AQ_BUF_SUP_TOP, 0, supTop);
   ReadBuffer(h, AQ_BUF_SUP_BOT, 0, supBot);

   OpenTrade(sym, dir, atr, demTop, demBot, supTop, supBot, score);
  }

//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- symbol list
   string list = InpSymbols;
   StringTrimLeft(list); StringTrimRight(list);
   string names[];
   int n = 0;
   if(StringLen(list) == 0)
     {
      ArrayResize(names, 1);
      names[0] = _Symbol;
      n = 1;
     }
   else
      n = StringSplit(list, StringGetCharacter(",", 0), names);

   ArrayResize(g_ea.sym, n);
   g_ea.symCount = 0;

   ENUM_TIMEFRAMES tf = (InpTf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : InpTf;

   for(int i = 0; i < n; i++)
     {
      string s = names[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      if(!SymbolSelect(s, true))
        {
         PrintFormat("%sunknown symbol '%s' — skipped", AQ_LOG, s);
         continue;
        }

      int h = iCustom(s, tf, InpIndPath,
                      InpLookback, InpFractalFast, InpFractalSlow, InpZoneFuzz,
                      InpZoneMerge, InpZoneExtend, InpFastLen, InpSlowLen,
                      InpSarStep, InpSarMax, InpAtrPeriod, InpUseMtf,
                      InpMtf1, InpMtf2, InpSigMode, InpMinScore,
                      InpCooldownBars, InpConfirmCandle);
      if(h == INVALID_HANDLE)
        {
         PrintFormat("%siCustom failed for %s (path '%s') err=%d",
                     AQ_LOG, s, InpIndPath, GetLastError());
         continue;
        }

      g_ea.sym[g_ea.symCount].name    = s;
      g_ea.sym[g_ea.symCount].handle  = h;
      g_ea.sym[g_ea.symCount].lastBar = 0;
      g_ea.sym[g_ea.symCount].ready   = false;
      g_ea.symCount++;
     }

   if(g_ea.symCount == 0)
     {
      Print(AQ_LOG, "no tradable symbol could be initialised");
      return(INIT_FAILED);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   g_ea.posCount        = 0;
   g_ea.dayStamp        = 0;
   g_ea.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_ea.halted          = false;
   ArrayResize(g_ea.pos, 1, 16);

   PrintFormat("%sstarted on %d symbol(s), magic %s", AQ_LOG, g_ea.symCount, (string)InpMagic);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   for(int i = 0; i < g_ea.symCount; i++)
      if(g_ea.sym[i].handle != INVALID_HANDLE) IndicatorRelease(g_ea.sym[i].handle);
  }

void OnTick()
  {
   //--- management runs on every tick; entries only on a closed bar
   ManagePositions();
   for(int i = 0; i < g_ea.symCount; i++) ProcessSymbol(i);
  }

//+------------------------------------------------------------------+
//| Closed-trade reporting                                           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) return;

   long   reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string why    = (reason == DEAL_REASON_SL) ? "SL" : (reason == DEAL_REASON_TP) ? "TP" : "manual/signal";
   double pl     = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   Notify(StringFormat("%s closed by %s, result %.2f %s",
                       HistoryDealGetString(trans.deal, DEAL_SYMBOL), why, pl,
                       AccountInfoString(ACCOUNT_CURRENCY)));
  }

//+------------------------------------------------------------------+
//| Optimisation criterion: profit weighted by quality, punished by  |
//| drawdown, with a floor on the sample size                        |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 30) return(0.0);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = MathMax(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 1.0);
   return(TesterStatistics(STAT_PROFIT) * pf / dd);
  }
//+------------------------------------------------------------------+
