//+------------------------------------------------------------------+
//|                                                        Utils.mqh |
//|  Stateless helpers: normalisation, broker limits, portfolio       |
//|  queries, time filters, formatting, logging, JSON building.       |
//|  Deliberately project-neutral names so they can move to a shared  |
//|  Common.mqh without renaming.                                     |
//+------------------------------------------------------------------+
#ifndef GFEA_UTILS_MQH
#define GFEA_UTILS_MQH

#include "State.mqh"

//+------------------------------------------------------------------+
//| LOGGING — one funnel, uniform and contextual                     |
//+------------------------------------------------------------------+
void LogInfo(const string msg)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;   // never flood optimisation agents
   PrintFormat("[%s] %s | %s", LOG_TAG, _Symbol, msg);
  }

void LogError(const string context, const int code = -1)
  {
   PrintFormat("[%s][ERR] %s | %s | err=%d", LOG_TAG, _Symbol, context,
               code >= 0 ? code : (int)GetLastError());
   ResetLastError();
  }

//+------------------------------------------------------------------+
//| SYMBOL SPEC — cached once, refreshed for the volatile fields     |
//+------------------------------------------------------------------+
bool CacheSymbolSpec(void)
  {
   g_ea.point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_ea.digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_ea.tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_ea.tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(g_ea.tickValue <= 0)
      g_ea.tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(g_ea.tickSize <= 0) g_ea.tickSize = g_ea.point;
   g_ea.volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_ea.volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_ea.volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_ea.hedging   = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
                     == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   return(g_ea.point > 0 && g_ea.tickSize > 0 && g_ea.tickValue > 0 &&
          g_ea.volStep > 0 && g_ea.volMin > 0);
  }

//+------------------------------------------------------------------+
//| NORMALISATION                                                    |
//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
  {
   if(g_ea.volStep <= 0) return 0;
   vol = MathFloor(vol / g_ea.volStep + 1e-9) * g_ea.volStep;   // floor: never risk more
   vol = MathMin(MathMax(vol, g_ea.volMin), g_ea.volMax);
   return NormalizeDouble(vol, 2);
  }

double NormalizePrice(const double price)
  {
   if(price == 0) return 0;
   double t = (g_ea.tickSize > 0 ? g_ea.tickSize : g_ea.point);
   return NormalizeDouble(MathRound(price / t) * t, g_ea.digits);
  }

//--- Minimum distance any stop / target / pending price must keep from the market.
double MinStopDistance(void)
  {
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long pts    = (long)MathMax((double)stops, (double)freeze);
   if(pts <= 0) pts = (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * 3;
   if(pts <= 0) pts = 10;
   return (double)pts * g_ea.point;
  }

//--- True when two price levels differ enough to be worth sending a modify.
bool LevelsDiffer(const double a, const double b)
  {
   double t = (g_ea.tickSize > 0 ? g_ea.tickSize : g_ea.point);
   return(MathAbs(a - b) >= t / 2.0);
  }

//--- Push a stop the legal side of the market so the server cannot reject it.
double ClampStop(const int dir, const double stop, const bool isStopLoss)
  {
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = MinStopDistance();
   double out  = stop;

   if(dir > 0)
     {
      // Long: both protective levels are measured against Bid.
      if(isStopLoss) out = MathMin(out, bid - dist);
      else           out = MathMax(out, bid + dist);
     }
   else
     {
      if(isStopLoss) out = MathMax(out, ask + dist);
      else           out = MathMin(out, ask - dist);
     }
   return NormalizePrice(out);
  }

//+------------------------------------------------------------------+
//| MONEY <-> PRICE conversion for a given volume                    |
//+------------------------------------------------------------------+
double MoneyPerPriceUnit(const double lots)
  {
   if(g_ea.tickSize <= 0 || lots <= 0) return 0;
   return (lots * g_ea.tickValue) / g_ea.tickSize;   // account currency per 1.0 of price
  }

double PriceDistanceForMoney(const double lots, const double money)
  {
   double per = MoneyPerPriceUnit(lots);
   if(per <= 0) return 0;
   return money / per;
  }

double MoneyForPriceDistance(const double lots, const double distance)
  {
   return MoneyPerPriceUnit(lots) * distance;
  }

//+------------------------------------------------------------------+
//| PORTFOLIO — every query filters on magic AND symbol              |
//+------------------------------------------------------------------+
bool IsMine(void)
  {
   return(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
          PositionGetString(POSITION_SYMBOL) == _Symbol);
  }

int CountMyPositions(void)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(IsMine()) n++;
     }
   return n;
  }

double BasketVolume(void)
  {
   double v = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(!IsMine()) continue;
      v += PositionGetDouble(POSITION_VOLUME);
     }
   return v;
  }

//--- Volume-weighted average entry of the whole basket.
//--- On a netting account this collapses to the single position's open price,
//--- which the server already maintains as the weighted average — so the same
//--- code is correct in both margin modes.
double BasketAvgPrice(void)
  {
   double num = 0, den = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(!IsMine()) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      num += PositionGetDouble(POSITION_PRICE_OPEN) * v;
      den += v;
     }
   return(den > 0 ? num / den : 0);
  }

//--- Floating P/L of the basket including swap and commission.
double BasketProfit(void)
  {
   double p = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(!IsMine()) continue;
      p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return p;
  }

//--- Direction of the live basket: +1 long, -1 short, 0 flat / mixed.
int BasketDirection(void)
  {
   int dir = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(!IsMine()) continue;
      int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(dir == 0) dir = d;
      else if(dir != d) return 0;      // hedged both ways — treat as flat
     }
   return dir;
  }

//+------------------------------------------------------------------+
//| TIME FILTERS                                                     |
//+------------------------------------------------------------------+
datetime DayStart(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
  }

bool DayOfWeekAllowed(const int dow)
  {
   switch(dow)
     {
      case 1: return InpTradeMonday;
      case 2: return InpTradeTuesday;
      case 3: return InpTradeWednesday;
      case 4: return InpTradeThursday;
      case 5: return InpTradeFriday;
     }
   return false;                       // weekends are never trading days here
  }

//--- Manual news blackout: "13:30,15:00" in server time, +/- InpNewsPauseMin.
bool InNewsBlackout(const datetime now)
  {
   if(InpNewsPauseMin <= 0 || StringLen(InpNewsTimes) == 0) return false;

   string parts[];
   int n = StringSplit(InpNewsTimes, ',', parts);
   if(n <= 0) return false;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowMin = dt.hour * 60 + dt.min;

   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);               // modifies in place and returns an int
      StringTrimRight(p);
      if(StringLen(p) < 3) continue;

      string hm[];
      if(StringSplit(p, ':', hm) != 2) continue;
      int mark = (int)StringToInteger(hm[0]) * 60 + (int)StringToInteger(hm[1]);
      if(MathAbs(nowMin - mark) <= InpNewsPauseMin) return true;
     }
   return false;
  }

bool SessionAllowsEntry(void)
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   if(!DayOfWeekAllowed(dt.day_of_week)) return false;
   if(InNewsBlackout(now))               return false;
   if(!InpUseTimeFilter)                 return true;

   if(InpStartHour == InpEndHour)        return true;
   if(InpStartHour < InpEndHour)
      return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
   return(dt.hour >= InpStartHour || dt.hour < InpEndHour);   // session wraps midnight
  }

bool IsFridayCloseTime(void)
  {
   if(InpFridayCloseHr <= 0) return false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.day_of_week == 5 && dt.hour >= InpFridayCloseHr);
  }

//+------------------------------------------------------------------+
//| MARKET STATE                                                     |
//+------------------------------------------------------------------+
int SpreadPoints(void)
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  }

bool SpreadOK(void)
  {
   return(SpreadPoints() <= InpMaxSpreadPoints);
  }

ENUM_TIMEFRAMES SignalTF(void)
  {
   return(InpSignalTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpSignalTF);
  }

bool IsNewSignalBar(void)
  {
   datetime cur = iTime(_Symbol, SignalTF(), 0);
   if(cur == 0 || cur == g_ea.lastBar) return false;
   g_ea.lastBar = cur;
   return true;
  }

//+------------------------------------------------------------------+
//| FORMATTING — panel and telemetry share these                     |
//+------------------------------------------------------------------+
string FmtPrice(const double p)   { return DoubleToString(p, g_ea.digits); }
string FmtMoney(const double m)   { return StringFormat("%s%.2f", m >= 0 ? "+" : "-", MathAbs(m)); }
string FmtPct(const double v)     { return StringFormat("%.2f%%", v); }
string FmtLots(const double l)    { return DoubleToString(l, 2); }

string RegimeText(const ENUM_MARKET_REGIME r)
  {
   switch(r)
     {
      case REG_TREND_UP:   return "TREND UP";
      case REG_TREND_DOWN: return "TREND DOWN";
      case REG_RANGE:      return "RANGE";
     }
   return "CHOP";
  }

string DirText(const int dir)
  {
   if(dir > 0) return "LONG";
   if(dir < 0) return "SHORT";
   return "FLAT";
  }

color DirColor(const int dir)
  {
   if(dir > 0) return THEME_BUY;
   if(dir < 0) return THEME_SELL;
   return THEME_TEXT_DIM;
  }

color PnlColor(const double v)
  {
   if(v > 0) return THEME_BUY;
   if(v < 0) return THEME_SELL;
   return THEME_TEXT_DIM;
  }

//+------------------------------------------------------------------+
//| JSON building — flat payloads only, no dependency needed         |
//+------------------------------------------------------------------+
string JsonEscape(const string s)
  {
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\n", " ");
   StringReplace(out, "\r", " ");
   return out;
  }

string JStr(const string k, const string v) { return "\"" + k + "\":\"" + JsonEscape(v) + "\""; }
string JNum(const string k, const double v, const int d = 5)
  {
   return "\"" + k + "\":" + DoubleToString(v, d);
  }
string JInt(const string k, const long v)   { return "\"" + k + "\":" + IntegerToString(v); }
string JBool(const string k, const bool v)  { return "\"" + k + "\":" + (v ? "true" : "false"); }
string JObj(const string body)              { return "{" + body + "}"; }
string JArr(const string body)              { return "[" + body + "]"; }

//--- Percent-encoding for Telegram query strings.
string UrlEncode(const string src)
  {
   string out = "";
   uchar bytes[];
   int n = StringToCharArray(src, bytes, 0, StringLen(src), CP_UTF8);
   for(int i = 0; i < n; i++)
     {
      uchar c = bytes[i];
      bool safe = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
                  (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == '~';
      if(safe) out += CharToString(c);
      else     out += StringFormat("%%%02X", c);
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Retryable trade retcodes                                         |
//+------------------------------------------------------------------+
bool IsRetryable(const uint rc)
  {
   return(rc == TRADE_RETCODE_REQUOTE       ||
          rc == TRADE_RETCODE_PRICE_CHANGED ||
          rc == TRADE_RETCODE_PRICE_OFF     ||
          rc == TRADE_RETCODE_TIMEOUT       ||
          rc == TRADE_RETCODE_CONNECTION);
  }

#endif // GFEA_UTILS_MQH
//+------------------------------------------------------------------+
