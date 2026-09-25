//+------------------------------------------------------------------+
//|                                               Adrenaline_V3.mq5  |
//|        ADRENALINE V3 - spike EA for Weltrade SyntX MaxGainX 2000  |
//|           Creator: Sirojiddin Sobitov  |  Brand: Serro Deriv !!   |
//+------------------------------------------------------------------+
//
// Instrument
//   Weltrade SyntX "MaxGainX 2000" (Weltrade MT5 terminal only). MaxGainX is
//   part of the GainX family: price drifts DOWN in small ticks and jumps UP in
//   sudden spikes. Weltrade does not publish the exact spike frequency, so the
//   EA measures it from ticks instead of hard-coding it. Other GainX symbols
//   work too.
//
// Strategy (BUY only)
//   1. Spike engine   - learns the normal tick size from recent history ticks
//                       and flags an UP tick InpSpikeSensitivity times larger
//                       as a spike. No built-in indicators are used.
//   2. Fibonacci      - every spike draws a new Fibonacci (spike base ->
//                       spike top). As price drifts back down, a BUY opens
//                       just BEFORE price touches a level at or below
//                       InpEntryZone (0.236 = first level), so a position is
//                       already open when the next spike comes. Until the
//                       first spike is seen, the v7 chart-pivot swing is used.
//   3. Basket         - up to InpMaxOpenTrades BUYs. The first BUY of every
//                       new spike is always allowed; further BUYs must be
//                       InpGridGapPercent of the swing below the lowest open
//                       BUY. Lots never multiply (the v7 x1.5 ladder is gone).
//   4. Spike banking  - when a spike prints, the basket is closed if it is in
//                       net profit, otherwise profitable trades are partly
//                       closed and moved to break-even.
//   5. Protection     - basket stop, stop-adding level, daily loss/profit
//                       limits, free-margin reserve, spread filter, cooldown.
//
// Honest risk statement
//   No EA can guarantee zero losses. SyntX prices come from an algorithm and
//   spike timing is random: "ticks since the last spike" does NOT make the
//   next spike more likely, so the dashboard shows those numbers only as
//   information. What this EA does is keep every loss inside the limits you
//   choose. Test on a demo account first.
//
// Requirements: MT5 HEDGING account, Algo Trading enabled. No DLLs.
//
#property copyright   "Sirojiddin Sobitov | Serro Deriv !!"
#property version     "3.00"
#property description "ADRENALINE V3 by Sirojiddin Sobitov (Serro Deriv !!) - BUY-only spike EA for Weltrade MaxGainX 2000."
#property description "New Fibonacci on every spike, BUY before a level is touched, basket and daily protection."
#property description "Hedging accounts only. No EA can guarantee zero losses - test on demo first."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| CONFIG - inputs                                                  |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
{
   LOT_RISK_PERCENT = 0, // Risk % of equity
   LOT_FIXED        = 1  // Fixed lot
};

enum ENUM_SPIKE_ACTION
{
   SPIKE_BANK_BASKET = 0, // Bank basket (close all when in net profit)
   SPIKE_PARTIAL     = 1, // Partial close + break-even
   SPIKE_HOLD        = 2  // Hold (break-even and trailing only)
};

enum ENUM_FIB_ANCHOR
{
   FIB_SPIKE = 0,         // Every spike (spike base -> spike top)
   FIB_PIVOT = 1          // Confirmed chart pivots (v7)
};

input group "=== 1. MAIN ==="
input ENUM_LOT_MODE     InpLotMode                  = LOT_RISK_PERCENT;  // Lot mode
input double            InpRiskPercent              = 1.0;               // Risk % per trade (loss if price falls one full swing)
input double            InpFixedLot                 = 0.01;              // Fixed lot (when Lot mode = Fixed lot)
input double            InpMaxLot                   = 1.0;               // Maximum lot per trade
input bool              InpAllowMinLot              = true;              // Use broker minimum lot when the risk lot is smaller
input int               InpMaxOpenTrades            = 5;                 // Maximum open BUY trades (basket size)
input ulong             InpMagic                    = 20260818;          // Magic number (unique per chart)
input string            InpSymbolKeyword            = "GainX";           // Trade only symbols containing this text (empty = any)
input string            InpTradeComment             = "Adrenaline Open V3"; // Trade comment (max 31 characters)

input group "=== 2. ENTRY: FIBONACCI ZONE + SPIKE ENGINE ==="
input ENUM_FIB_ANCHOR   InpFibAnchor                = FIB_SPIKE;         // Draw Fibonacci on
input double            InpEntryZone                = 0.236;             // Buy only at/below this Fib level (0.236 = first level)
input double            InpBeforeTouchPercent       = 5.0;               // Pre-touch window above a Fib level (% of swing)
input double            InpGridGapPercent           = 10.0;              // Min gap below the lowest open BUY (% of swing)
input bool              InpTradeEverySpike          = true;              // First BUY of every new spike ignores the grid gap
input double            InpSpikeSensitivity         = 8.0;               // Spike = UP tick at least X times the normal tick
input int               InpWarmupTicks              = 20000;             // History ticks used to learn the symbol (0 = live only)
input int               InpMaxSpreadPoints          = 0;                 // Maximum spread in points (0 = auto)

input group "=== 3. EXIT & PROFIT PROTECTION ==="
input ENUM_SPIKE_ACTION InpOnSpike                  = SPIKE_BANK_BASKET; // When a spike prints
input double            InpPartialClosePercent      = 50.0;              // Partial close % of each profitable trade
input int               InpBreakEvenPoints          = 0;                 // Break-even trigger in points (0 = auto, -1 = off)
input int               InpTrailStartPoints         = 0;                 // Trailing start in points (0 = auto, -1 = off)
input int               InpTrailDistancePoints      = 0;                 // Trailing distance in points (0 = auto)
input double            InpBasketTakeProfitPercent  = 0.0;               // Close basket at profit % of balance (0 = off)

input group "=== 4. BASKET & ACCOUNT PROTECTION ==="
input double            InpBasketStopPercent        = 5.0;               // Close ALL when basket loss reaches % of balance
input double            InpStopAddingPercent        = 3.0;               // No new trades while basket loss >= % of balance (0 = off)
input double            InpMaxDailyLossPercent      = 5.0;               // Daily loss limit % (close all, stop until next day; 0 = off)
input double            InpMaxDailyProfitPercent    = 0.0;               // Daily profit target % (no new trades after it; 0 = off)
input double            InpFreeMarginReservePercent = 30.0;              // Keep this % of equity as free margin
input int               InpCooldownMinutes          = 30;                // Pause new trades after a basket stop (minutes)
input int               InpDisasterSLPoints         = 0;                 // Broker-side far stop-loss per trade in points (0 = off)
input int               InpSlippagePoints           = 0;                 // Maximum slippage in points (0 = auto)

input group "=== 5. TIME FILTER (server time) ==="
input bool              InpUseTimeFilter            = false;             // Trade only inside the hours below
input int               InpStartHour                = 0;                 // Start hour (0-23)
input int               InpEndHour                  = 24;                // End hour (1-24, may be lower than start for overnight)

input group "=== 6. ALERTS ==="
input bool              InpAlertPopup               = true;              // Terminal pop-up for important events
input bool              InpAlertPush                = false;             // Mobile push notifications
input bool              InpTelegram                 = false;             // Telegram messages
input string            InpTelegramToken            = "";                // Telegram bot token (keep private)
input string            InpTelegramChat             = "";                // Telegram chat id

input group "=== 7. DASHBOARD ==="
input bool              InpShowDashboard            = true;              // Show dashboard
input bool              InpDarkTheme                = true;              // Apply dark neon chart theme
input bool              InpEnableFX                 = true;              // Animated status light (cosmetic only)
input bool              InpDrawFibLevels            = true;              // Draw Fibonacci levels on chart
input bool              InpMarkSpikes               = true;              // Mark detected spikes on chart
input bool              InpVerboseLog               = false;             // Detailed Experts log

//+------------------------------------------------------------------+
//| CONFIG - constants                                               |
//+------------------------------------------------------------------+
#define EA_NAME          "ADRENALINE V3"
#define EA_DISPLAY       "Adrenaline V3"      // name used in logs and alerts
#define EA_VERSION       "3.00"
#define EA_AUTHOR        "Sirojiddin Sobitov"
#define EA_BRAND         "Serro Deriv !!"
#define EA_TAG           "ADRV3"              // prefix of terminal global variables
#define FIB_LEVELS       11
#define FIB_DEPTH        3          // bars on each side of a confirmed pivot
#define FIB_MAX_PIVOTS   32
#define HISTORY_BARS     6000       // bars scanned on the first build
#define RESUME_BARS      256        // bars copied on each new bar afterwards
#define ATR_BARS         14         // manual true-range average (no iATR)
#define TICK_EWMA        500.0      // memory of the normal-tick average, in ticks
#define STAT_ALPHA       0.2        // smoothing of spike size and interval
#define LIVE_WARMUP      300        // live ticks needed when history ticks are unavailable
#define WARMUP_ATTEMPTS  30         // seconds spent retrying history ticks
#define TRADE_RETRIES    3
#define SPIKE_MARKS      30         // spike arrows kept on chart (ring buffer)
#define NOTICE_REPEAT_MS 60000      // identical alerts are not repeated within this time
#define CONFIRM_MS       5000       // CLOSE ALL needs a second click within this time
#define TIMER_MS         500
#define THEME_PROPS      14

// THEME - every dashboard and chart colour lives here
#define CLR_PANEL        C'7,11,20'
#define CLR_CARD         C'14,21,36'
#define CLR_EDGE         C'30,50,78'
#define CLR_DIM          C'40,60,90'
#define CLR_NEON         C'0,200,255'
#define CLR_GOLD         C'255,193,7'
#define CLR_TEXT         C'226,232,244'
#define CLR_MUTED        C'122,138,164'
#define CLR_GOOD         C'0,229,160'
#define CLR_BAD          C'255,82,82'
#define CLR_WARN         C'255,152,0'
#define CLR_FIB          C'40,150,220'
#define CLR_FIB_EXT      C'150,110,240'
#define CLR_FIB_OFF      C'52,64,84'
#define CLR_CH_BG        C'5,9,18'
#define CLR_CH_FG        C'150,170,195'
#define CLR_CH_GRID      C'20,32,50'
#define CLR_CH_BULL      C'0,200,255'
#define CLR_CH_BEAR      C'120,90,220'
#define CLR_CH_BID       C'43,133,161'
#define CLR_CH_ASK       C'156,89,174'

// METRICS - every dashboard dimension lives here (scaled at draw time)
#define UI_FONT          "Consolas"
#define UI_X             16
#define UI_Y             24
#define UI_W             440
#define UI_H             648
#define UI_L             34         // left column
#define UI_R             250        // right column
#define UI_BAR_W         404
#define UI_BTN_W         198
#define UI_BTN_H         30

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
enum ENUM_MSG_LEVEL
{
   MSG_LOG   = 0,   // Experts log only
   MSG_TRADE = 1,   // log + push + Telegram
   MSG_ALERT = 2    // log + pop-up + push + Telegram
};

struct FibPoint
{
   datetime time;
   double   price;
   int      direction;     // +1 high pivot, -1 low pivot
};

struct SFib
{
   bool     ready;
   datetime processed;     // last closed bar fed to the pivot engine
   datetime lastBar;       // open time of the forming bar
   datetime lowTime;       // active swing anchors (spike or pivot)
   datetime highTime;
   datetime keyLow;        // swing the level reservations belong to
   datetime keyHigh;
   datetime pivLowTime;    // last confirmed chart-pivot swing (v7 engine)
   datetime pivHighTime;
   double   low;
   double   high;
   double   pivLow;
   double   pivHigh;
   double   atr;           // manual 14-bar true-range average
   double   barMin;        // lowest price of the forming bar
   bool     fromSpike;     // active swing comes from the last spike
   bool     swingTraded;   // a BUY was already opened on the active swing
};

struct SSpike
{
   bool     warmed;        // statistics are trustworthy
   bool     dirWarning;    // big DOWN jumps dominate: not a GainX-type feed
   int      attempts;      // history warm-up attempts so far
   int      liveTicks;
   int      spikes;
   int      upJumps;
   int      downJumps;
   int      markIndex;
   long     ticks;         // bid changes processed
   long     lastSpikeTick;
   double   prevBid;
   double   lastDelta;
   double   avgTick;       // average |bid change| of normal ticks
   double   avgSize;       // average spike size
   double   avgInterval;   // average ticks between spikes
   double   lastSize;
   datetime lastTime;
   bool     swingOpen;     // spike still extending upward
   double   cycleLow;      // lowest bid since the last spike top
   datetime cycleLowTime;
   double   swingLow;      // last spike: base ...
   double   swingHigh;     // ... and top
   datetime swingLowTime;
   datetime swingHighTime;
};

struct SGuard
{
   datetime dayStart;
   datetime lastClosedCalc;
   datetime cooldownUntil;
   double   dayBalance;
   double   closedToday;   // closed P/L of this EA today
   double   dailyPL;       // closed today + floating
   bool     halted;        // daily loss limit reached
   bool     profitLocked;  // daily profit target reached
   bool     closedDirty;
};

struct SBasket
{
   int      count;
   int      guarded;       // positions whose stop already locks profit
   double   lots;
   double   profit;
   double   lowest;
};

struct SUi
{
   bool     enabled;       // dashboard allowed (live or visual tester)
   bool     draw;          // chart drawings allowed
   bool     pulse;
   bool     themeSaved;
   double   scale;
   ulong    confirmUntil;
};

CTrade   g_trade;
SFib     g_fib;
SSpike   g_spike;
SGuard   g_guard;
SUi      g_ui;
FibPoint g_pivots[];
MqlRates g_rates[];
double   g_ratios[FIB_LEVELS]={0.0,0.236,0.382,0.5,0.618,0.786,1.0,1.618,2.618,3.618,4.236};
bool     g_attempted[FIB_LEVELS];

bool     g_tester=false;
bool     g_paused=false;
bool     g_symbolOK=false;
bool     g_telegramOn=false;
bool     g_minLotUsed=false;
int      g_lock=INVALID_HANDLE;
int      g_digits=0;
int      g_volDigits=2;
double   g_point=0;
double   g_tickSize=0;
double   g_volMin=0;
double   g_volMax=0;
double   g_volStep=0;
double   g_nextLot=0;
datetime g_lastSecond=0;
ulong    g_lastNoticeMs=0;
string   g_prefix="";          // terminal state: global variables, lock file
string   g_pre="";             // chart objects
string   g_note="Starting";
string   g_symbolStatus="Waiting for symbol specifications";
string   g_lastNotice="";

ENUM_CHART_PROPERTY_INTEGER g_themeProps[THEME_PROPS]={CHART_COLOR_BACKGROUND,CHART_COLOR_FOREGROUND,CHART_COLOR_GRID,
   CHART_COLOR_CANDLE_BULL,CHART_COLOR_CANDLE_BEAR,CHART_COLOR_CHART_UP,CHART_COLOR_CHART_DOWN,
   CHART_COLOR_CHART_LINE,CHART_COLOR_BID,CHART_COLOR_ASK,CHART_SHOW_GRID,CHART_MODE,CHART_FOREGROUND,CHART_SHIFT};
long     g_oldTheme[THEME_PROPS];

//+------------------------------------------------------------------+
//| HELPERS - formatting and symbol data                             |
//+------------------------------------------------------------------+
double FloorToTick(const double price)
{
   if(g_tickSize<=0) return NormalizeDouble(price,g_digits);
   return NormalizeDouble(MathFloor(price/g_tickSize+1e-9)*g_tickSize,g_digits);
}
string Px(const double price)      { return price>0 ? DoubleToString(price,g_digits) : "--"; }
string Pt(const double distance)   { return g_point>0 ? DoubleToString(distance/g_point,1) : "--"; }
string Money(const double value)   { return (value>=0 ? "+" : "")+DoubleToString(value,2); }
string Lots(const double volume)   { return DoubleToString(volume,g_volDigits); }
string TfName()                    { return StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7); }
string DateKey(const datetime day) { return TimeToString(day,TIME_DATE); }
datetime DayOf(const datetime t)   { return (datetime)(((long)t/86400)*86400); }
void Debug(const string text)      { if(InpVerboseLog) Print(EA_DISPLAY," | ",text); }

string Ago(const datetime t)
{
   if(t<=0) return "--";
   long s=(long)TimeCurrent()-(long)t;
   if(s<0) s=0;
   if(s<60)   return IntegerToString(s)+"s";
   if(s<3600) return IntegerToString(s/60)+"m";
   return IntegerToString(s/3600)+"h";
}

uint HashText(const string value)
{
   uint hash=(uint)2166136261;
   for(int i=0;i<StringLen(value);i++)
      hash=(hash^(uint)StringGetCharacter(value,i))*(uint)16777619;
   return hash;
}

bool SymbolMatches()
{
   if(StringLen(InpSymbolKeyword)==0) return true;
   string symbol=_Symbol,keyword=InpSymbolKeyword;
   StringToUpper(symbol);
   StringToUpper(keyword);
   return StringFind(symbol,keyword)>=0;
}

// Broker specifications can change (and arrive late after a restart), so
// they are refreshed every second instead of being cached once.
void RefreshSymbol()
{
   g_point   =SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   g_digits  =(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   g_tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize<=0) g_tickSize=g_point;
   g_volMin =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   g_volMax =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   g_volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   g_volDigits=0;
   if(g_volStep>0)
   {
      double s=g_volStep;
      while(g_volDigits<8 && MathAbs(s-MathRound(s))>1e-8) { s*=10.0; g_volDigits++; }
   }
   double cap=MathMin(InpMaxLot,g_volMax);
   if(g_point<=0 || g_volMin<=0 || g_volMax<g_volMin || g_volStep<=0)
   { g_symbolOK=false; g_symbolStatus="WAIT / BROKER SPECIFICATIONS"; }
   else if(cap<g_volMin-1e-10)
   { g_symbolOK=false; g_symbolStatus="MAX LOT BELOW BROKER MIN "+Lots(g_volMin); }
   else
   { g_symbolOK=true; g_symbolStatus="MIN "+Lots(g_volMin)+" / STEP "+Lots(g_volStep)+" / MAX "+Lots(cap); }
}

bool TradingAllowed()
{
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}

bool TimeAllowed()
{
   if(!InpUseTimeFilter) return true;
   MqlDateTime t;
   if(!TimeToStruct(TimeCurrent(),t)) return true;
   if(InpStartHour<InpEndHour) return t.hour>=InpStartHour && t.hour<InpEndHour;
   return t.hour>=InpStartHour || t.hour<InpEndHour;     // overnight window
}

//+------------------------------------------------------------------+
//| CORE - automatic distances (0 = auto inputs)                     |
//+------------------------------------------------------------------+
double TrailDistance()
{
   if(InpTrailStartPoints<0) return 0;
   return InpTrailDistancePoints>0 ? InpTrailDistancePoints*g_point : g_fib.atr*0.5;
}
double TrailStart()
{
   if(InpTrailStartPoints<0) return 0;
   return InpTrailStartPoints>0 ? InpTrailStartPoints*g_point : MathMax(g_fib.atr,TrailDistance()*2.0);
}
double BreakEvenTrigger()
{
   if(InpBreakEvenPoints<0) return 0;
   return InpBreakEvenPoints>0 ? InpBreakEvenPoints*g_point : g_fib.atr;
}
double SpreadLimit()
{
   return InpMaxSpreadPoints>0 ? InpMaxSpreadPoints*g_point : MathMax(g_fib.atr*0.15,2.0*g_tickSize);
}
ulong Deviation()
{
   if(InpSlippagePoints>0) return (ulong)InpSlippagePoints;
   long spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   return (ulong)(2*spread>10 ? 2*spread : 10);
}
double StopsDistance()
{
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)(stops>freeze ? stops : freeze)*g_point+g_tickSize;
}
double FreezeDistance()
{
   return (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*g_point;
}

//+------------------------------------------------------------------+
//| CORE - Fibonacci swing engine (from v7, confirmed pivots only)   |
//+------------------------------------------------------------------+
bool   HasFib()                         { return g_fib.low>0 && g_fib.high>g_fib.low; }
double FibRange()                       { return HasFib() ? g_fib.high-g_fib.low : 0.0; }
double FibPrice(const double ratio)     { return g_fib.high-ratio*(g_fib.high-g_fib.low); }
double Retracement(const double price)  { return HasFib() ? (g_fib.high-price)/FibRange() : -1.0; }

bool LowPivot(const MqlRates &r[],const int p)
{
   for(int j=1;j<=FIB_DEPTH;j++)
      if(r[p].low>=r[p-j].low || r[p].low>r[p+j].low) return false;
   return true;
}

bool HighPivot(const MqlRates &r[],const int p)
{
   for(int j=1;j<=FIB_DEPTH;j++)
      if(r[p].high<=r[p-j].high || r[p].high<r[p+j].high) return false;
   return true;
}

// Pivots alternate low/high. A second pivot in the same direction only
// replaces the previous one when it is more extreme.
void AddFibPoint(const datetime time,const double price,const int direction)
{
   int n=ArraySize(g_pivots);
   if(n>0)
   {
      if(time<=g_pivots[n-1].time) return;
      if(direction==g_pivots[n-1].direction)
      {
         if((direction>0 && price>g_pivots[n-1].price) || (direction<0 && price<g_pivots[n-1].price))
         { g_pivots[n-1].time=time; g_pivots[n-1].price=price; }
         return;
      }
      if(MathAbs(price-g_pivots[n-1].price)<g_point) return;
   }
   if(n>=FIB_MAX_PIVOTS)
   {
      for(int i=1;i<n;i++) g_pivots[i-1]=g_pivots[i];
      n--;
   }
   ArrayResize(g_pivots,n+1,FIB_MAX_PIVOTS);
   g_pivots[n].time=time;
   g_pivots[n].price=price;
   g_pivots[n].direction=direction;
}

// A pivot needs FIB_DEPTH closed bars on its right, so it is confirmed and
// never repaints. A new swing = confirmed low followed by a higher confirmed high.
void ProcessFibBar(const MqlRates &r[],const int closedIndex)
{
   int p=closedIndex-FIB_DEPTH;
   if(p<FIB_DEPTH) return;
   bool low=LowPivot(r,p),high=HighPivot(r,p);
   if(low==high) return;                 // outside bar: order of its extremes is unknown
   AddFibPoint(r[p].time,low ? r[p].low : r[p].high,low ? -1 : 1);
   int n=ArraySize(g_pivots);
   if(high && n>=2 && g_pivots[n-2].direction==-1 && g_pivots[n-1].direction==1 &&
      g_pivots[n-1].time==r[p].time && g_pivots[n-1].price>g_pivots[n-2].price)
   {
      g_fib.pivLow=g_pivots[n-2].price;  g_fib.pivLowTime=g_pivots[n-2].time;
      g_fib.pivHigh=g_pivots[n-1].price; g_fib.pivHighTime=g_pivots[n-1].time;
   }
}

string LevelKey(const int level)
{
   return g_prefix+"L"+IntegerToString((long)g_fib.lowTime)+"_"+IntegerToString((long)g_fib.highTime)+"_"+IntegerToString(level);
}

// Runs once per new bar. After the first full build only the newest bars are
// copied; a gap in history triggers a clean rebuild.
bool UpdateEngine()
{
   datetime current=iTime(_Symbol,_Period,0);
   if(g_fib.ready && current>0 && current==g_fib.lastBar) return true;
   int need=2*FIB_DEPTH+ATR_BARS+2;
   int n=CopyRates(_Symbol,_Period,0,g_fib.processed>0 ? RESUME_BARS : HISTORY_BARS,g_rates);
   int start=0;
   if(n>=need && g_fib.processed>0)
   {
      while(start<n-1 && g_rates[start].time<=g_fib.processed) start++;
      if(start==0 || g_rates[start-1].time!=g_fib.processed)
      {
         g_fib.processed=0;
         start=0;
         n=CopyRates(_Symbol,_Period,0,HISTORY_BARS,g_rates);
      }
   }
   if(n<need) { g_fib.ready=false; g_note="Waiting for chart history"; return false; }
   if(g_fib.processed==0)
   {
      ArrayResize(g_pivots,0);
      g_fib.pivLow=0; g_fib.pivHigh=0; g_fib.pivLowTime=0; g_fib.pivHighTime=0;
   }
   for(int i=start;i<n-1;i++) ProcessFibBar(g_rates,i);

   double sum=0;
   for(int i=n-1-ATR_BARS;i<n-1;i++)
      sum+=MathMax(g_rates[i].high-g_rates[i].low,
                   MathMax(MathAbs(g_rates[i].high-g_rates[i-1].close),MathAbs(g_rates[i].low-g_rates[i-1].close)));
   g_fib.atr=sum/ATR_BARS;

   g_fib.processed=g_rates[n-2].time;
   g_fib.lastBar=g_rates[n-1].time;
   g_fib.barMin=g_rates[n-1].low;
   g_fib.ready=true;
   SelectSwing();
   return true;
}

// Chooses the swing the Fibonacci levels are drawn on: the last spike (base
// -> top) when that mode is on and a spike has been seen, else the v7 pivot
// swing. A new swing clears the used-level flags (restored from terminal
// global variables after a restart).
void SelectSwing()
{
   bool spike=(InpFibAnchor==FIB_SPIKE && g_spike.swingLow>0 && g_spike.swingHigh>g_spike.swingLow);
   g_fib.fromSpike=spike;
   g_fib.low     =spike ? g_spike.swingLow      : g_fib.pivLow;
   g_fib.high    =spike ? g_spike.swingHigh     : g_fib.pivHigh;
   g_fib.lowTime =spike ? g_spike.swingLowTime  : g_fib.pivLowTime;
   g_fib.highTime=spike ? g_spike.swingHighTime : g_fib.pivHighTime;
   if(g_fib.keyLow==g_fib.lowTime && g_fib.keyHigh==g_fib.highTime) return;
   g_fib.keyLow=g_fib.lowTime;
   g_fib.keyHigh=g_fib.highTime;
   g_fib.swingTraded=false;
   ArrayInitialize(g_attempted,false);
   for(int i=0;i<FIB_LEVELS;i++)
      if(!g_tester && GlobalVariableCheck(LevelKey(i))) g_attempted[i]=true;
   if(HasFib()) Debug("New "+(spike ? "spike" : "pivot")+" swing "+Px(g_fib.low)+" -> "+Px(g_fib.high));
}

// "Not touched yet" reference: on a spike swing, the lowest price since the
// spike top; on a pivot swing, the low of the forming candle (v7 rule).
double TouchFloor() { return g_fib.fromSpike ? g_spike.cycleLow : g_fib.barMin; }

// A used level is re-armed only after price has clearly moved back above it
// (1.5x the pre-touch window), so boundary noise cannot repeat an entry.
void RearmLevels(const double bid)
{
   if(!g_fib.ready || !HasFib()) return;
   double window=FibRange()*InpBeforeTouchPercent/100.0;
   for(int i=0;i<FIB_LEVELS;i++)
   {
      if(!g_attempted[i]) continue;
      double level=FibPrice(g_ratios[i]);
      if(level<=0 || bid<=level+1.5*window) continue;
      if(!g_tester && GlobalVariableCheck(LevelKey(i)))
      {
         if(!GlobalVariableDel(LevelKey(i))) continue;
         GlobalVariablesFlush();
      }
      g_attempted[i]=false;
   }
}

string NextLevelText(const double bid)
{
   if(!HasFib() || bid<=0) return "--";
   int best=-1;
   double bestGap=DBL_MAX;
   for(int i=0;i<FIB_LEVELS;i++)
   {
      if(g_attempted[i] || g_ratios[i]<InpEntryZone-1e-9) continue;
      double level=FibPrice(g_ratios[i]),gap=bid-level;
      if(level>0 && gap>0 && gap<bestGap) { best=i; bestGap=gap; }
   }
   if(best<0) return "none below price";
   return "F"+DoubleToString(g_ratios[best],3)+" @ "+Px(FibPrice(g_ratios[best]))+"  ("+Pt(bestGap)+" pt away)";
}

//+------------------------------------------------------------------+
//| CORE - spike engine (tick statistics, no indicators)             |
//+------------------------------------------------------------------+
double SpikeThreshold() { return MathMax(InpSpikeSensitivity*g_spike.avgTick,3.0*g_tickSize); }

void ResetSpikeStats()
{
   int attempts=g_spike.attempts,mark=g_spike.markIndex;
   ZeroMemory(g_spike);
   g_spike.attempts=attempts;
   g_spike.markIndex=mark;
}

void CheckSpikeDirection()
{
   // GainX spikes UP. If large DOWN jumps dominate, the feed behaves like
   // PainX and a BUY spike strategy would fight the instrument.
   g_spike.dirWarning=(g_spike.downJumps>=3 && g_spike.downJumps>2*g_spike.upJumps);
}

void MarkSpike(const datetime when,const double price)
{
   if(!g_ui.draw || !InpMarkSpikes || g_pre=="") return;
   string name=g_pre+"SPK_"+IntegerToString(g_spike.markIndex);
   g_spike.markIndex=(g_spike.markIndex+1)%SPIKE_MARKS;
   if(ObjectFind(0,name)<0)
   {
      if(!ObjectCreate(0,name,OBJ_ARROW_UP,0,when,price)) return;
      ObjectSetInteger(0,name,OBJPROP_COLOR,CLR_GOLD);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_TOP);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
   else ObjectMove(0,name,0,when,price);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"Spike "+TimeToString(when,TIME_DATE|TIME_SECONDS));
}

// Returns +1 for an UP spike, -1 for a large DOWN jump, 0 for a normal tick.
// Spikes are excluded from the normal-tick average so they cannot inflate it.
int SpikeFeed(const double delta,const datetime when,const double basePrice)
{
   double size=MathAbs(delta);
   if(size<g_point*0.5) return 0;                  // bid unchanged (ask-only update)
   g_spike.ticks++;
   double price=basePrice+delta;
   if(g_spike.avgTick<=0) { g_spike.avgTick=size; TrackCycle(delta,price,when); return 0; }
   double threshold=SpikeThreshold();
   if(delta>=threshold)
   {
      // New Fibonacci swing: base = lowest price since the previous spike
      // (normally the price just before this one), top = this spike.
      bool lowerBefore=(g_spike.cycleLow>0 && g_spike.cycleLow<basePrice);
      g_spike.swingLow     =lowerBefore ? g_spike.cycleLow : basePrice;
      g_spike.swingLowTime =lowerBefore ? g_spike.cycleLowTime : when;
      g_spike.swingHigh    =price;
      g_spike.swingHighTime=when;
      g_spike.swingOpen    =true;
      g_spike.cycleLow     =price;
      g_spike.cycleLowTime =when;
      if(g_spike.lastSpikeTick>0)
      {
         double interval=(double)(g_spike.ticks-g_spike.lastSpikeTick);
         g_spike.avgInterval=(g_spike.avgInterval<=0) ? interval : g_spike.avgInterval+STAT_ALPHA*(interval-g_spike.avgInterval);
      }
      g_spike.avgSize=(g_spike.avgSize<=0) ? delta : g_spike.avgSize+STAT_ALPHA*(delta-g_spike.avgSize);
      g_spike.lastSize=delta;
      g_spike.lastTime=when;
      g_spike.lastSpikeTick=g_spike.ticks;
      g_spike.spikes++;
      g_spike.upJumps++;
      MarkSpike(when,basePrice);
      return 1;
   }
   bool extending=TrackCycle(delta,price,when);
   if(-delta>=threshold) { g_spike.downJumps++; return -1; }
   if(!extending) g_spike.avgTick+=(size-g_spike.avgTick)/TICK_EWMA;   // spike tails stay out of the average
   return 0;
}

// A spike can take several up ticks: the top keeps rising until the first
// down tick. The cycle low is the lowest price since that top.
bool TrackCycle(const double delta,const double price,const datetime when)
{
   if(g_spike.swingOpen)
   {
      if(delta>0 && price>g_spike.swingHigh)
      {
         g_spike.swingHigh=price;
         g_spike.cycleLow=price;
         g_spike.cycleLowTime=when;
         return true;
      }
      if(delta<0) g_spike.swingOpen=false;
   }
   if(g_spike.cycleLow<=0 || price<g_spike.cycleLow) { g_spike.cycleLow=price; g_spike.cycleLowTime=when; }
   return false;
}

// Learns the symbol from recent history ticks. The median move seeds the
// normal-tick size because it is not distorted by the rare spikes.
bool SpikeWarmup()
{
   if(InpWarmupTicks<=0 || g_point<=0) return false;
   MqlTick ticks[];
   int n=CopyTicks(_Symbol,ticks,COPY_TICKS_INFO,0,(uint)InpWarmupTicks);
   if(n<LIVE_WARMUP) return false;
   double moves[];
   if(ArrayResize(moves,n)<n) return false;
   int m=0;
   for(int i=1;i<n;i++)
   {
      if(ticks[i].bid<=0 || ticks[i-1].bid<=0) continue;
      double move=MathAbs(ticks[i].bid-ticks[i-1].bid);
      if(move>=g_point*0.5) moves[m++]=move;
   }
   if(m<LIVE_WARMUP/2) return false;
   ArrayResize(moves,m);
   ArraySort(moves);
   ResetSpikeStats();
   g_spike.avgTick=moves[m/2];
   for(int i=1;i<n;i++)
   {
      if(ticks[i].bid<=0 || ticks[i-1].bid<=0) continue;
      SpikeFeed(ticks[i].bid-ticks[i-1].bid,ticks[i].time,ticks[i-1].bid);
   }
   g_spike.prevBid=ticks[n-1].bid;
   g_spike.warmed=true;
   CheckSpikeDirection();
   Print(EA_DISPLAY," | Learned ",n," ticks: normal tick ",Pt(g_spike.avgTick)," pt, spike threshold ",Pt(SpikeThreshold()),
         " pt, spikes ",g_spike.spikes,", avg every ",DoubleToString(g_spike.avgInterval,0)," ticks");
   return true;
}

int SpikeOnTick(const MqlTick &q)
{
   double delta=(g_spike.prevBid>0) ? q.bid-g_spike.prevBid : 0.0;
   g_spike.prevBid=q.bid;
   g_spike.lastDelta=delta;
   if(g_point<=0 || MathAbs(delta)<g_point*0.5) return 0;
   int jump=SpikeFeed(delta,q.time,q.bid-delta);
   if(jump!=0) CheckSpikeDirection();
   if(!g_spike.warmed)
   {
      g_spike.liveTicks++;
      bool historyDone=(InpWarmupTicks<=0 || g_spike.attempts>=WARMUP_ATTEMPTS);
      if(historyDone && g_spike.liveTicks>=LIVE_WARMUP)
      {
         g_spike.warmed=true;
         Print(EA_DISPLAY," | Learned from ",g_spike.liveTicks," live ticks: spike threshold ",Pt(SpikeThreshold())," pt");
      }
   }
   return jump;
}

//+------------------------------------------------------------------+
//| RISK - lot sizing, margin, basket, daily limits                  |
//+------------------------------------------------------------------+
bool IsMine()
{
   return PositionGetString(POSITION_SYMBOL)==_Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic &&
          PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
}

void ScanBasket(SBasket &b)
{
   b.count=0; b.guarded=0; b.lots=0; b.profit=0; b.lowest=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || !IsMine()) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      b.count++;
      b.lots+=PositionGetDouble(POSITION_VOLUME);
      b.profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      b.lowest=(b.lowest<=0) ? open : MathMin(b.lowest,open);
      if(sl>0 && sl>=open) b.guarded++;
   }
}

// Money lost by 1 lot if price falls by `distance`. OrderCalcProfit is the
// most reliable source on synthetic symbols; tick value is the fallback.
double LossPerLot(const double distance)
{
   if(distance<=0) return 0;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK),profit=0;
   if(ask>distance && OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,ask,ask-distance,profit) && profit<0) return -profit;
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue<=0) tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickValue<=0 || g_tickSize<=0) return 0;
   return distance/g_tickSize*tickValue;
}

// With no per-trade stop, risk is measured against one full swing range:
// RiskPercent = equity lost if price falls the whole last swing after entry.
double RiskDistance()
{
   double range=MathMax(FibRange(),g_spike.avgSize);
   return range>0 ? range : g_fib.atr*10.0;
}

double CalcLots(string &why)
{
   why="";
   g_minLotUsed=false;
   if(!g_symbolOK) { why=g_symbolStatus; return 0; }
   double raw=InpFixedLot;
   if(InpLotMode==LOT_RISK_PERCENT)
   {
      double perLot=LossPerLot(RiskDistance());
      if(perLot<=0) { why="Waiting for tick value to size the lot"; return 0; }
      raw=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0/perLot;
   }
   double cap=MathMin(InpMaxLot,g_volMax);
   double lots=NormalizeDouble(MathFloor(MathMin(raw,cap)/g_volStep+1e-8)*g_volStep,g_volDigits);
   if(lots<g_volMin-1e-10)
   {
      if(!InpAllowMinLot) { why="Risk lot "+DoubleToString(raw,4)+" is below broker minimum "+Lots(g_volMin); return 0; }
      lots=g_volMin;
      g_minLotUsed=(InpLotMode==LOT_RISK_PERCENT);
   }
   return lots;
}

bool MarginAllows(const double equity,const double freeMargin,const double newMargin,
                  const double spreadCost,const double reservePercent)
{
   return equity>0 && newMargin>=0 && spreadCost>=0 &&
          freeMargin-newMargin-spreadCost>=equity*reservePercent/100.0;
}

// Broker directional limits include other EAs and manual positions/orders.
bool VolumeAvailable(const double volume)
{
   double limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);
   if(limit<=0) return true;
   double total=0;
   for(int i=0;i<PositionsTotal();i++)
      if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) total+=PositionGetDouble(POSITION_VOLUME);
   for(int i=0;i<OrdersTotal();i++)
   {
      if(OrderGetTicket(i)==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      long type=OrderGetInteger(ORDER_TYPE);
      if(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT)
         total+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return total+volume<=limit+1e-8;
}

string HaltKey() { return g_prefix+"HALT_"+DateKey(g_guard.dayStart); }

bool InCooldown() { return g_guard.cooldownUntil>0 && TimeCurrent()<g_guard.cooldownUntil; }

void StartCooldown()
{
   if(InpCooldownMinutes<=0) return;
   g_guard.cooldownUntil=TimeCurrent()+InpCooldownMinutes*60;
   if(!g_tester)
   {
      GlobalVariableSet(g_prefix+"COOLDOWN",(double)g_guard.cooldownUntil);
      GlobalVariablesFlush();
   }
}

// The day-start balance is stored per server date, so a restart during the
// day keeps the same baseline for the daily limits.
void CheckNewDay()
{
   datetime now=TimeCurrent();
   if(now<=0) return;
   datetime day=DayOf(now);
   if(day==g_guard.dayStart) return;
   bool rollover=(g_guard.dayStart>0);
   g_guard.dayStart=day;
   g_guard.profitLocked=false;
   g_guard.closedToday=0;
   g_guard.closedDirty=true;
   string key=g_prefix+"DAY_"+DateKey(day);
   if(!g_tester && GlobalVariableCheck(key)) g_guard.dayBalance=GlobalVariableGet(key);
   else
   {
      g_guard.dayBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      if(!g_tester) { GlobalVariableSet(key,g_guard.dayBalance); GlobalVariablesFlush(); }
   }
   g_guard.halted=(!g_tester && GlobalVariableCheck(HaltKey()));
   if(rollover) Notify("New server day. Day-start balance "+DoubleToString(g_guard.dayBalance,2),MSG_LOG);
}

// Closed P/L of this EA today. Broker-side stop deals can carry magic 0, so
// they are matched through the position id of this EA's entry deals.
bool UpdateClosedToday()
{
   datetime from=g_guard.dayStart;
   if(from<=0) return false;
   if(!HistorySelect(from-7*86400,TimeCurrent()+3600)) return false;
   int total=HistoryDealsTotal();
   long ids[];
   int nIds=0;
   for(int i=0;i<total;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)==InpMagic && HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
      {
         ArrayResize(ids,nIds+1,256);
         ids[nIds++]=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      }
   }
   double sum=0;
   for(int i=0;i<total;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      if((datetime)HistoryDealGetInteger(deal,DEAL_TIME)<from) continue;
      bool mine=((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)==InpMagic);
      if(!mine)
      {
         long id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
         for(int k=0;k<nIds && !mine;k++) mine=(ids[k]==id);
      }
      if(!mine) continue;
      sum+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+
           HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
   }
   g_guard.closedToday=sum;
   return true;
}

// Once per second (tick time, and the timer when live).
void Housekeeping()
{
   RefreshSymbol();
   CheckNewDay();
   datetime now=TimeCurrent();
   if(g_guard.closedDirty || (long)now-(long)g_guard.lastClosedCalc>=60)
   {
      if(UpdateClosedToday()) { g_guard.closedDirty=false; g_guard.lastClosedCalc=now; }
   }
   if(!g_spike.warmed && InpWarmupTicks>0 && g_spike.attempts<WARMUP_ATTEMPTS)
   {
      g_spike.attempts++;
      SpikeWarmup();
   }
}

//+------------------------------------------------------------------+
//| ALERTS                                                           |
//+------------------------------------------------------------------+
string UrlEncode(const string text)
{
   uchar bytes[];
   int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n>0 && bytes[n-1]==0) n--;
   string out="";
   for(int i=0;i<n;i++)
   {
      uchar c=bytes[i];
      bool plain=(c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9') || c=='-' || c=='_' || c=='.' || c=='~';
      out+=plain ? CharToString(c) : StringFormat("%%%02X",c);
   }
   return out;
}

// Needs https://api.telegram.org in Tools > Options > Expert Advisors >
// "Allow WebRequest for listed URL". Not available in the Strategy Tester.
void SendTelegram(const string text)
{
   string url="https://api.telegram.org/bot"+InpTelegramToken+"/sendMessage";
   string body="chat_id="+UrlEncode(InpTelegramChat)+"&text="+UrlEncode(text);
   string headers="Content-Type: application/x-www-form-urlencoded\r\n",resultHeaders;
   char post[],result[];
   int len=StringToCharArray(body,post,0,WHOLE_ARRAY,CP_UTF8);
   if(len>0) ArrayResize(post,len-1);        // drop the terminating zero
   ResetLastError();
   int status=WebRequest("POST",url,headers,5000,post,result,resultHeaders);
   if(status==-1)
   {
      int err=GetLastError();
      if(err==4014)
      {
         Print(EA_DISPLAY," | Telegram disabled: add https://api.telegram.org to Tools > Options > Expert Advisors > Allow WebRequest.");
         g_telegramOn=false;
      }
      else Print(EA_DISPLAY," | Telegram WebRequest failed, error ",err);
   }
   else if(status!=200) Print(EA_DISPLAY," | Telegram HTTP ",status,": ",CharArrayToString(result));
}

void Notify(const string text,const ENUM_MSG_LEVEL level)
{
   string msg=_Symbol+" | "+EA_DISPLAY+" | "+text;
   Print(msg);
   if(g_tester || level==MSG_LOG) return;
   ulong now=GetTickCount64();
   if(text==g_lastNotice && now-g_lastNoticeMs<NOTICE_REPEAT_MS) return;
   g_lastNotice=text;
   g_lastNoticeMs=now;
   if(level==MSG_ALERT && InpAlertPopup) Alert(msg);
   if(InpAlertPush && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      if(!SendNotification(StringSubstr(msg,0,255))) Debug("Push notification failed, error "+IntegerToString(GetLastError()));
   if(g_telegramOn) SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| TRADE - all order traffic lives here                             |
//+------------------------------------------------------------------+
bool IsDone(const uint rc)      { return rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED; }
bool IsRetryable(const uint rc) { return rc==TRADE_RETCODE_REQUOTE || rc==TRADE_RETCODE_PRICE_CHANGED || rc==TRADE_RETCODE_PRICE_OFF; }

bool ClosePosition(const ulong ticket)
{
   for(int attempt=0;attempt<TRADE_RETRIES;attempt++)
   {
      bool sent=g_trade.PositionClose(ticket,Deviation());
      uint rc=g_trade.ResultRetcode();
      if(sent && IsDone(rc)) return true;
      if(!PositionSelectByTicket(ticket)) return true;     // already closed (e.g. stop hit)
      if(!IsRetryable(rc))
      {
         Print(EA_DISPLAY," | Close #",ticket," failed: ",rc," ",g_trade.ResultRetcodeDescription());
         return false;
      }
   }
   return false;
}

bool ClosePartial(const ulong ticket,const double volume)
{
   for(int attempt=0;attempt<TRADE_RETRIES;attempt++)
   {
      bool sent=g_trade.PositionClosePartial(ticket,volume,Deviation());
      uint rc=g_trade.ResultRetcode();
      if(sent && IsDone(rc)) return true;
      if(!PositionSelectByTicket(ticket)) return false;
      if(!IsRetryable(rc))
      {
         Print(EA_DISPLAY," | Partial close #",ticket," failed: ",rc," ",g_trade.ResultRetcodeDescription());
         return false;
      }
   }
   return false;
}

int CloseBasket(const string reason,const ENUM_MSG_LEVEL level=MSG_ALERT)
{
   int closed=0,failed=0;
   double pl=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsMine()) continue;
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(ClosePosition(ticket)) { closed++; pl+=profit; }
      else failed++;
   }
   if(closed+failed>0)
   {
      g_guard.closedDirty=true;
      string text=reason+": closed "+IntegerToString(closed)+" trade(s), about "+Money(pl);
      if(failed>0) text+=" | "+IntegerToString(failed)+" failed, retrying";
      Notify(text,level);
   }
   return failed;
}

// Stops are only ever placed in profit and only ever tightened, so they can
// never turn a basket trade into a loss (the basket stop handles losses).
bool MoveStop(const ulong ticket,const double target,const MqlTick &q)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double open=PositionGetDouble(POSITION_PRICE_OPEN),old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   double sl=FloorToTick(target);
   if(sl<open+g_tickSize*0.5) return false;
   if(old>0 && sl<old+g_tickSize*0.5) return false;       // never loosen, never resend the same value
   if(q.bid-sl<StopsDistance()) return false;
   if(old>0 && q.bid-old<=FreezeDistance()) return false;
   if(!g_trade.PositionModify(ticket,sl,tp))
   {
      Debug("Stop move #"+IntegerToString((long)ticket)+" failed: "+g_trade.ResultRetcodeDescription());
      return false;
   }
   uint rc=g_trade.ResultRetcode();
   return rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_NO_CHANGES;
}

void ManageProfitStops(const MqlTick &q)
{
   if(!TradingAllowed()) return;
   double beTrigger=BreakEvenTrigger(),trailStart=TrailStart(),trailDist=TrailDistance();
   bool trailing=(trailStart>0 && trailDist>0);
   if(beTrigger<=0 && !trailing) return;
   double lock=(q.ask-q.bid)+2.0*g_tickSize;
   double stops=StopsDistance();
   double step=MathMax(g_tickSize,trailing ? trailDist*0.1 : 0.0);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsMine()) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),old=PositionGetDouble(POSITION_SL);
      double gain=q.bid-open,target=0;
      if(beTrigger>0 && gain>=beTrigger) target=open+lock;
      if(trailing && gain>=trailStart) target=MathMax(target,q.bid-MathMax(trailDist,stops));
      if(target<=0) continue;
      if(old>=open && target<old+step) continue;           // already protected: move in useful steps only
      MoveStop(ticket,target,q);
   }
}

// Profitable trades that are not yet protected: close part, then move the
// rest to break-even. A trade too small to split is closed completely.
void PartialOnSpike()
{
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q)) return;
   double lock=(q.ask-q.bid)+2.0*g_tickSize;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !IsMine()) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      double volume=PositionGetDouble(POSITION_VOLUME),profit=PositionGetDouble(POSITION_PROFIT);
      if(profit<=0 || (sl>0 && sl>=open)) continue;
      double part=NormalizeDouble(MathFloor(volume*InpPartialClosePercent/100.0/g_volStep+1e-8)*g_volStep,g_volDigits);
      bool split=(part>=g_volMin-1e-10 && volume-part>=g_volMin-1e-10);
      string id="#"+IntegerToString((long)ticket);
      if(!split)
      {
         if(ClosePosition(ticket)) Notify("Spike: closed "+id+" ("+Lots(volume)+" lots, too small to split) "+Money(profit),MSG_TRADE);
         continue;
      }
      if(ClosePartial(ticket,part))
      {
         Notify("Spike: closed "+Lots(part)+" of "+id+", rest moved to break-even",MSG_TRADE);
         MoveStop(ticket,open+lock,q);
      }
   }
}

void ReactToSpike(const SBasket &b)
{
   Debug("Spike +"+Pt(g_spike.lastSize)+" pt detected");
   if(b.count==0 || InpOnSpike==SPIKE_HOLD || !TradingAllowed()) return;
   if(InpOnSpike==SPIKE_BANK_BASKET && b.profit>0) { CloseBasket("SPIKE BANKED",MSG_TRADE); return; }
   PartialOnSpike();
}

// Returns true when it closed trades, so the caller re-reads the basket.
bool EvaluateGuards(const SBasket &b)
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance<=0) return false;
   double base=(g_guard.dayBalance>0) ? g_guard.dayBalance : balance;
   g_guard.dailyPL=g_guard.closedToday+b.profit;
   bool acted=false;

   if(b.count>0 && b.profit<=-balance*InpBasketStopPercent/100.0)
   {
      CloseBasket("BASKET STOP "+DoubleToString(InpBasketStopPercent,1)+"%");
      StartCooldown();
      acted=true;
   }
   else if(b.count>0 && InpBasketTakeProfitPercent>0 && b.profit>=balance*InpBasketTakeProfitPercent/100.0)
   {
      CloseBasket("BASKET TARGET "+DoubleToString(InpBasketTakeProfitPercent,1)+"%",MSG_TRADE);
      acted=true;
   }

   if(!g_guard.halted && InpMaxDailyLossPercent>0 && g_guard.dailyPL<=-base*InpMaxDailyLossPercent/100.0)
   {
      g_guard.halted=true;
      if(!g_tester) { GlobalVariableSet(HaltKey(),1.0); GlobalVariablesFlush(); }
      Notify("DAILY LOSS LIMIT reached ("+Money(g_guard.dailyPL)+"). No trading until the next server day.",MSG_ALERT);
      if(!acted) { CloseBasket("DAILY LOSS LIMIT"); acted=true; }
   }
   else if(g_guard.halted && !acted && b.count>0)
   {
      CloseBasket("DAILY LOSS LIMIT");                    // finish closing any leftovers
      acted=true;
   }

   if(!g_guard.profitLocked && InpMaxDailyProfitPercent>0 && g_guard.dailyPL>=base*InpMaxDailyProfitPercent/100.0)
   {
      g_guard.profitLocked=true;
      Notify("DAILY PROFIT TARGET reached ("+Money(g_guard.dailyPL)+"). No new trades today; open trades stay managed.",MSG_ALERT);
   }
   return acted;
}

// Every gate writes a plain-English note for the dashboard.
void TryBuy(const MqlTick &q,const SBasket &b,const int jump)
{
   g_nextLot=0;
   if(!g_symbolOK)                          { g_note=g_symbolStatus; return; }
   if(g_guard.halted)                       { g_note="Daily loss limit hit - waiting for the next server day"; return; }
   if(g_paused)                             { g_note="Manual pause - open trades are still managed"; return; }
   if(!TradingAllowed())                    { g_note="Algo Trading is disabled"; return; }
   if(InCooldown())                         { g_note="Cooldown after basket stop until "+TimeToString(g_guard.cooldownUntil,TIME_MINUTES); return; }
   if(g_guard.profitLocked)                 { g_note="Daily profit target reached - no new trades today"; return; }
   if(!TimeAllowed())                       { g_note="Outside trading hours"; return; }
   if(!g_spike.warmed)                      { g_note="Learning the symbol's tick behaviour"; return; }
   if(g_spike.dirWarning)                   { g_note="Big DOWN jumps dominate - not a GainX-type symbol"; return; }
   if(!g_fib.ready || !HasFib())            { g_note="Waiting for a confirmed Fibonacci swing"; return; }
   if((long)TimeCurrent()-(long)q.time>60)  { g_note="Waiting for a live quote"; return; }
   if(jump>0)                               { g_note="Spike in progress - no entry on a spike tick"; return; }
   if(g_spike.lastDelta>=0)                 { g_note="Waiting for a falling tick into a Fibonacci level"; return; }

   double spread=q.ask-q.bid;
   if(spread>SpreadLimit()) { g_note="Spread "+Pt(spread)+" pt is above the limit "+Pt(SpreadLimit())+" pt"; return; }
   long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL && mode!=SYMBOL_TRADE_MODE_LONGONLY) { g_note="Symbol does not accept new BUYs"; return; }
   if(b.count>=InpMaxOpenTrades) { g_note="Maximum open trades reached - managing the basket"; return; }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   if(b.count>0 && InpStopAddingPercent>0 && b.profit<=-balance*InpStopAddingPercent/100.0)
   { g_note="Basket "+Money(b.profit)+" - no new trades at the stop-adding level"; return; }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong order=OrderGetTicket(i);
      if(order>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic)
      { g_note="Waiting for an outstanding order"; return; }
   }

   // The v7 grid never used the lowest open price, so BUYs could stack at
   // almost the same price. Each new BUY must now be clearly lower.
   // The first BUY of every new spike is allowed anywhere (InpTradeEverySpike);
   // later BUYs on the same spike must respect the grid gap.
   double range=FibRange(),window=range*InpBeforeTouchPercent/100.0;
   bool spikeTrade=(InpTradeEverySpike && g_fib.fromSpike && !g_fib.swingTraded);
   if(b.count>0 && !spikeTrade && q.ask>b.lowest-range*InpGridGapPercent/100.0)
   { g_note="Waiting for the grid gap below the lowest BUY "+Px(b.lowest); return; }
   double untouched=TouchFloor();

   int selected=-1;
   double nearest=DBL_MAX;
   for(int i=0;i<FIB_LEVELS;i++)
   {
      if(g_attempted[i] || g_ratios[i]<InpEntryZone-1e-9) continue;
      double level=FibPrice(g_ratios[i]),gap=q.bid-level;
      // Pre-touch: price is falling toward the level, has not touched it yet
      // (since the spike, or in this candle on a pivot swing) and is inside
      // the window just above it.
      if(level>0 && gap>0 && gap<=window && untouched>level && gap<nearest) { selected=i; nearest=gap; }
   }
   if(selected<0)
   {
      g_note="Scanning: price at "+DoubleToString(Retracement(q.bid)*100.0,1)+"% of swing, entry zone from "+
             DoubleToString(InpEntryZone*100.0,1)+"%";
      return;
   }

   string why="";
   double volume=CalcLots(why);
   if(volume<=0) { g_note=why; return; }
   g_nextLot=volume;
   if(!VolumeAvailable(volume)) { g_note="Broker volume limit blocks "+Lots(volume)+" lots"; return; }
   double margin=0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,volume,q.ask,margin)) { g_note="Waiting for margin calculation"; return; }
   double immediate=0,spreadCost=0;
   if(OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,volume,q.ask,q.bid,immediate)) spreadCost=MathMax(0.0,-immediate);
   if(!MarginAllows(AccountInfoDouble(ACCOUNT_EQUITY),AccountInfoDouble(ACCOUNT_MARGIN_FREE),margin,spreadCost,InpFreeMarginReservePercent))
   { g_note="Margin guard: keeping "+DoubleToString(InpFreeMarginReservePercent,0)+"% of equity free"; return; }

   // Reserve the level BEFORE sending: no repeat on the same approach, even after a restart.
   g_attempted[selected]=true;
   if(!g_tester)
   {
      if(GlobalVariableSet(LevelKey(selected),(double)TimeCurrent())==0) { g_note="Cannot store the level reservation"; return; }
      GlobalVariablesFlush();
   }

   double sl=0;
   if(InpDisasterSLPoints>0) sl=FloorToTick(q.bid-MathMax(InpDisasterSLPoints*g_point,StopsDistance()));
   string ratio=DoubleToString(g_ratios[selected],3);
   g_trade.SetDeviationInPoints(Deviation());
   bool done=false;
   uint rc=0;
   for(int attempt=0;attempt<TRADE_RETRIES && !done;attempt++)
   {
      bool sent=g_trade.Buy(volume,_Symbol,0.0,sl,0.0,InpTradeComment);
      rc=g_trade.ResultRetcode();
      done=(sent && IsDone(rc));
      if(!done && !IsRetryable(rc)) break;
   }
   if(done)
   {
      g_fib.swingTraded=true;
      g_note="BUY "+Lots(volume)+" lots at Fib "+ratio;
      Notify("BUY "+Lots(volume)+" lots @ "+Px(g_trade.ResultPrice())+" | Fib "+ratio+
             (g_minLotUsed ? " | broker minimum lot (above risk %)" : ""),MSG_TRADE);
   }
   else
   {
      g_note="BUY rejected: "+g_trade.ResultRetcodeDescription()+" - level reserved";
      Notify("BUY rejected ("+IntegerToString(rc)+" "+g_trade.ResultRetcodeDescription()+"), Fib "+ratio+" reserved",MSG_LOG);
   }
}

//+------------------------------------------------------------------+
//| UI - chart theme, dashboard, chart drawings                      |
//+------------------------------------------------------------------+
int PX(const int value) { return (int)MathRound(value*g_ui.scale); }

void ApplyTheme()
{
   if(!InpDarkTheme || !g_ui.enabled) return;
   for(int i=0;i<THEME_PROPS;i++) g_oldTheme[i]=ChartGetInteger(0,g_themeProps[i]);
   g_ui.themeSaved=true;
   long values[THEME_PROPS];
   values[0]=CLR_CH_BG;    values[1]=CLR_CH_FG;    values[2]=CLR_CH_GRID;
   values[3]=CLR_CH_BULL;  values[4]=CLR_CH_BEAR;  values[5]=CLR_CH_BULL;
   values[6]=CLR_CH_BEAR;  values[7]=CLR_CH_BULL;  values[8]=CLR_CH_BID;
   values[9]=CLR_CH_ASK;   values[10]=0;           values[11]=CHART_CANDLES;
   values[12]=0;           values[13]=1;
   for(int i=0;i<THEME_PROPS;i++) ChartSetInteger(0,g_themeProps[i],values[i]);
}

void RestoreTheme()
{
   if(!g_ui.themeSaved) return;
   for(int i=0;i<THEME_PROPS;i++) ChartSetInteger(0,g_themeProps[i],g_oldTheme[i]);
   g_ui.themeSaved=false;
}

void HUDBox(const string id,const int x,const int y,const int w,const int h,const color fill,const color edge)
{
   string n=g_pre+"HUD_"+id;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,PX(x));
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,PX(y));
   ObjectSetInteger(0,n,OBJPROP_XSIZE,MathMax(1,PX(w)));
   ObjectSetInteger(0,n,OBJPROP_YSIZE,MathMax(1,PX(h)));
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,fill);
   ObjectSetInteger(0,n,OBJPROP_COLOR,edge);
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,5);
}

void HUDText(const string id,const int x,const int y,const string text,const color ink,const int size=9)
{
   string n=g_pre+"HUD_"+id;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,PX(x));
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,PX(y));
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,MathMax(6,PX(size)));
   ObjectSetInteger(0,n,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,6);
   ObjectSetString(0,n,OBJPROP_FONT,UI_FONT);
   ObjectSetString(0,n,OBJPROP_TEXT,text);
   ObjectSetString(0,n,OBJPROP_TOOLTIP,text);
}

void HUDButton(const string id,const int x,const int y,const string text,const color ink)
{
   string n=g_pre+"HUD_"+id;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,PX(x));
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,PX(y));
   ObjectSetInteger(0,n,OBJPROP_XSIZE,PX(UI_BTN_W));
   ObjectSetInteger(0,n,OBJPROP_YSIZE,PX(UI_BTN_H));
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,CLR_CARD);
   ObjectSetInteger(0,n,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,ink);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,MathMax(6,PX(9)));
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,10);
   ObjectSetString(0,n,OBJPROP_FONT,UI_FONT);
   ObjectSetString(0,n,OBJPROP_TEXT,text);
}

string HUDShort(const string value,const int length=56)
{
   return StringLen(value)<=length ? value : StringSubstr(value,0,length-3)+"...";
}

// Fraction bar: background + fill. `fraction` is clamped to 0..1.
void HUDBar(const string id,const int y,const double fraction,const color fill)
{
   HUDBox(id+"_BG",UI_L,y,UI_BAR_W,6,CLR_CARD,CLR_CARD);
   int width=(int)MathRound(UI_BAR_W*MathMax(0.0,MathMin(1.0,fraction)));
   HUDBox(id,UI_L,y,MathMax(1,width),6,width>0 ? fill : CLR_CARD,CLR_PANEL);
}

string StatusText(const SBasket &b,color &accent)
{
   accent=CLR_NEON;
   if(!g_symbolOK)          { accent=CLR_BAD;  return "SYMBOL CONFIG / BLOCKED"; }
   if(g_guard.halted)       { accent=CLR_BAD;  return "DAILY LOSS LIMIT / HALTED"; }
   if(!TradingAllowed())    { accent=CLR_BAD;  return "ALGO TRADING DISABLED"; }
   if(g_spike.dirWarning)   { accent=CLR_BAD;  return "DOWN JUMPS DETECTED / BLOCKED"; }
   if(g_paused)             { accent=CLR_GOLD; return "MANUAL PAUSE / MANAGING"; }
   if(InCooldown())         { accent=CLR_WARN; return "COOLDOWN AFTER BASKET STOP"; }
   if(g_guard.profitLocked) { accent=CLR_GOLD; return "DAILY TARGET HIT / MANAGING"; }
   if(!g_spike.warmed)      { accent=CLR_WARN; return "LEARNING SYMBOL TICKS"; }
   if(!HasFib())            { accent=CLR_WARN; return "WAITING FOR FIB SWING"; }
   if(!TimeAllowed())       { accent=CLR_WARN; return "OUTSIDE TRADING HOURS"; }
   if(b.count>0)            { accent=CLR_GOOD; return "BASKET ACTIVE / HUNTING SPIKE"; }
   return "SCANNING DISCOUNT ZONE";
}

void DrawDashboard()
{
   if(!g_ui.enabled || g_pre=="") return;
   double width=(double)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),height=(double)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   g_ui.scale=MathMax(0.6,MathMin(1.15,MathMin(width/(UI_W+40),height/(UI_H+40))));
   MqlTick q;
   ZeroMemory(q);
   bool quoted=SymbolInfoTick(_Symbol,q);
   SBasket b;
   ScanBasket(b);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY);
   color accent=CLR_NEON;
   string state=StatusText(b,accent);

   // Header and status
   HUDBox("BASE",UI_X,UI_Y,UI_W,UI_H,CLR_PANEL,CLR_EDGE);
   HUDBox("STRIPE",UI_X,UI_Y,UI_W,3,accent,accent);
   HUDText("BRAND",UI_L,40,EA_NAME,CLR_GOLD,15);
   HUDText("SUB",UI_L,68,"BY "+EA_AUTHOR+"  /  "+EA_BRAND+"  /  BUY BEFORE SPIKE",CLR_MUTED,8);
   HUDText("SYM",UI_L,88,HUDShort(_Symbol+"  "+TfName()+"  HEDGING  MAGIC "+IntegerToString((long)InpMagic),48),CLR_NEON,9);
   HUDBox("STATUS_BG",UI_L,110,UI_BAR_W,38,CLR_CARD,CLR_EDGE);
   HUDBox("LIGHT",UI_L+12,124,10,10,(InpEnableFX && g_ui.pulse) ? CLR_DIM : accent,accent);
   HUDText("STATUS",UI_L+32,120,state,accent,10);

   // 01 Spike engine
   HUDText("S1",UI_L,160,"01 / SPIKE ENGINE",CLR_MUTED,9);
   HUDText("S1A",UI_L,182,"THRESHOLD  "+Pt(SpikeThreshold())+" pt",CLR_TEXT);
   HUDText("S1B",UI_R,182,"NORMAL TICK  "+Pt(g_spike.avgTick)+" pt",CLR_TEXT);
   HUDText("S1C",UI_L,202,"SPIKES SEEN  "+IntegerToString(g_spike.spikes),CLR_TEXT);
   HUDText("S1D",UI_R,202,"AVG EVERY  "+(g_spike.avgInterval>0 ? DoubleToString(g_spike.avgInterval,0)+" ticks" : "--"),CLR_TEXT);
   HUDText("S1E",UI_L,222,"LAST  "+(g_spike.spikes>0 ? "+"+Pt(g_spike.lastSize)+" pt  "+Ago(g_spike.lastTime)+" ago" : "--"),CLR_GOLD);
   HUDText("S1F",UI_R,222,"SINCE  "+(g_spike.lastSpikeTick>0 ? IntegerToString(g_spike.ticks-g_spike.lastSpikeTick)+" ticks" : "--"),CLR_TEXT);
   string direction=!g_spike.warmed ? "LEARNING  "+IntegerToString(g_spike.liveTicks)+" live ticks" :
                    (g_spike.dirWarning ? "DIRECTION  DOWN JUMPS - ENTRIES BLOCKED" : "DIRECTION  UP SPIKES - OK");
   HUDText("S1G",UI_L,242,direction,!g_spike.warmed ? CLR_WARN : (g_spike.dirWarning ? CLR_BAD : CLR_GOOD));

   // 02 Fibonacci zone
   HUDBox("RULE1",UI_L,266,UI_BAR_W,1,CLR_EDGE,CLR_EDGE);
   HUDText("S2",UI_L,276,"02 / FIBONACCI  ("+(g_fib.fromSpike ? "LAST SPIKE" : "CHART PIVOTS")+")",CLR_MUTED,9);
   HUDText("S2A",UI_L,298,"SWING LOW  "+Px(g_fib.low),CLR_NEON);
   HUDText("S2B",UI_R,298,"SWING HIGH  "+Px(g_fib.high),CLR_NEON);
   double retr=(quoted && HasFib()) ? Retracement(q.bid) : 0.0;
   bool inZone=(HasFib() && retr>=InpEntryZone);
   string zone=!HasFib() ? "--" : DoubleToString(retr*100.0,1)+"%  "+(inZone ? "IN ZONE" : "ABOVE ZONE");
   HUDText("S2C",UI_L,318,"RETRACE  "+zone,inZone ? CLR_GOOD : CLR_TEXT);
   HUDText("S2D",UI_R,318,"ENTRY FROM  "+DoubleToString(InpEntryZone*100.0,1)+"%",CLR_GOLD);
   HUDBar("S2BAR",340,retr,inZone ? CLR_GOOD : CLR_NEON);
   int zoneX=UI_L+(int)MathRound(UI_BAR_W*MathMin(1.0,InpEntryZone));
   HUDBox("S2MARK",MathMin(zoneX,UI_L+UI_BAR_W-2),336,2,14,CLR_GOLD,CLR_GOLD);
   HUDText("S2E",UI_L,356,"NEXT LEVEL  "+(quoted ? NextLevelText(q.bid) : "--"),CLR_TEXT);

   // 03 Basket
   HUDBox("RULE2",UI_L,380,UI_BAR_W,1,CLR_EDGE,CLR_EDGE);
   HUDText("S3",UI_L,390,"03 / BASKET",CLR_MUTED,9);
   HUDText("S3A",UI_L,412,"OPEN  "+IntegerToString(b.count)+" / "+IntegerToString(InpMaxOpenTrades)+"   LOTS  "+Lots(b.lots),CLR_TEXT);
   HUDText("S3B",UI_R,412,"FLOATING  "+Money(b.profit),b.profit>=0 ? CLR_GOOD : CLR_BAD);
   HUDText("S3C",UI_L,432,"LOWEST  "+Px(b.lowest),CLR_TEXT);
   HUDText("S3D",UI_R,432,"PROTECTED  "+IntegerToString(b.guarded)+" / "+IntegerToString(b.count),b.guarded>0 ? CLR_GOOD : CLR_TEXT);
   HUDText("S3E",UI_L,452,"BASKET STOP  "+Money(-balance*InpBasketStopPercent/100.0),CLR_BAD);
   string why="";
   double preview=(g_nextLot>0) ? g_nextLot : CalcLots(why);
   string lotText=(preview>0) ? Lots(preview)+(g_minLotUsed ? " MIN" : "") : "BLOCKED";
   HUDText("S3F",UI_R,452,"NEXT LOT  "+lotText,g_minLotUsed ? CLR_WARN : CLR_NEON);

   // 04 Risk guard
   HUDBox("RULE3",UI_L,476,UI_BAR_W,1,CLR_EDGE,CLR_EDGE);
   HUDText("S4",UI_L,486,"04 / RISK GUARD",CLR_MUTED,9);
   HUDText("S4A",UI_L,508,"BALANCE  "+DoubleToString(balance,2),CLR_TEXT);
   HUDText("S4B",UI_R,508,"EQUITY  "+DoubleToString(equity,2),CLR_TEXT);
   double base=(g_guard.dayBalance>0) ? g_guard.dayBalance : balance;
   double lossLimit=base*InpMaxDailyLossPercent/100.0,profitTarget=base*InpMaxDailyProfitPercent/100.0;
   string limitText=(InpMaxDailyLossPercent>0) ? "LIMIT -"+DoubleToString(lossLimit,2) : "LIMIT OFF";
   HUDText("S4C",UI_L,528,"TODAY  "+Money(g_guard.dailyPL)+"   "+limitText,g_guard.dailyPL>=0 ? CLR_GOOD : CLR_BAD);
   double dayFill=0;
   if(g_guard.dailyPL<0 && lossLimit>0) dayFill=-g_guard.dailyPL/lossLimit;
   if(g_guard.dailyPL>0 && profitTarget>0) dayFill=g_guard.dailyPL/profitTarget;
   HUDBar("S4BAR",548,dayFill,g_guard.dailyPL>=0 ? CLR_GOOD : CLR_BAD);
   double spread=quoted ? q.ask-q.bid : 0.0;
   HUDText("S4D",UI_L,560,"SPREAD  "+Pt(spread)+" / "+Pt(SpreadLimit())+" pt",spread>SpreadLimit() ? CLR_BAD : CLR_TEXT);
   string guardText="GUARD  READY";
   color guardInk=CLR_GOOD;
   if(g_guard.halted)            { guardText="GUARD  HALTED TODAY";  guardInk=CLR_BAD; }
   else if(InCooldown())         { guardText="COOLDOWN  "+TimeToString(g_guard.cooldownUntil,TIME_MINUTES); guardInk=CLR_WARN; }
   else if(g_guard.profitLocked) { guardText="GUARD  TARGET HIT";    guardInk=CLR_GOLD; }
   HUDText("S4E",UI_R,560,guardText,guardInk);

   // Notes, footer, buttons
   HUDText("NOTE",UI_L,584,HUDShort(g_note,60),CLR_TEXT,8);
   ObjectSetString(0,g_pre+"HUD_NOTE",OBJPROP_TOOLTIP,g_note);
   string be=(BreakEvenTrigger()>0) ? Pt(BreakEvenTrigger()) : "OFF";
   string trail=(TrailStart()>0 && TrailDistance()>0) ? Pt(TrailStart())+"/"+Pt(TrailDistance()) : "OFF";
   HUDText("FOOT",UI_L,604,"BE "+be+" pt   TRAIL "+trail+" pt   SLIP "+IntegerToString((long)Deviation())+" pt",CLR_MUTED,8);
   HUDButton("PAUSE",UI_L,626,g_paused ? "RESUME NEW ENTRIES" : "PAUSE NEW ENTRIES",g_paused ? CLR_GOLD : CLR_NEON);
   bool confirming=(g_ui.confirmUntil>0 && GetTickCount64()<=g_ui.confirmUntil);
   HUDButton("CLOSE",UI_L+UI_BAR_W-UI_BTN_W,626,confirming ? "CLICK AGAIN TO CONFIRM" : "CLOSE ALL TRADES",confirming ? CLR_BAD : CLR_GOLD);
}

void DrawLevels()
{
   if(!g_ui.draw || !InpDrawFibLevels || g_pre=="") return;
   for(int i=0;i<FIB_LEVELS;i++)
   {
      string name=g_pre+"LVL_"+IntegerToString(i);
      double price=HasFib() ? FibPrice(g_ratios[i]) : 0.0;
      if(price<=0) { ObjectDelete(0,name); continue; }
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      color ink=(g_ratios[i]<InpEntryZone-1e-9) ? CLR_FIB_OFF : (g_attempted[i] ? CLR_DIM : (i>6 ? CLR_FIB_EXT : CLR_FIB));
      ObjectSetDouble(0,name,OBJPROP_PRICE,price);
      ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetString(0,name,OBJPROP_TEXT,"F "+DoubleToString(g_ratios[i],3));
   }
   string zone=g_pre+"ZONE";
   if(!HasFib()) { ObjectDelete(0,zone); return; }
   double price=FibPrice(InpEntryZone);
   if(ObjectFind(0,zone)<0) ObjectCreate(0,zone,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,zone,OBJPROP_PRICE,price);
   ObjectSetInteger(0,zone,OBJPROP_COLOR,CLR_GOLD);
   ObjectSetInteger(0,zone,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,zone,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,zone,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,zone,OBJPROP_BACK,true);
   ObjectSetString(0,zone,OBJPROP_TEXT,"ENTRY ZONE "+DoubleToString(InpEntryZone,3));
}

void RefreshUi()
{
   if(!g_ui.draw) return;
   DrawLevels();
   DrawDashboard();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
string ValidateInputs()
{
   if(InpLotMode==LOT_RISK_PERCENT && (InpRiskPercent<=0 || InpRiskPercent>10)) return "Risk % must be above 0 and at most 10";
   if(InpLotMode==LOT_FIXED && InpFixedLot<=0)          return "Fixed lot must be above 0";
   if(InpMaxLot<=0)                                     return "Maximum lot must be above 0";
   if(InpLotMode==LOT_FIXED && InpFixedLot>InpMaxLot)   return "Fixed lot is above the maximum lot";
   if(InpMaxOpenTrades<1 || InpMaxOpenTrades>50)        return "Maximum open trades must be 1-50";
   if(InpMagic==0)                                      return "Magic number must not be 0";
   if(StringLen(InpTradeComment)<1 || StringLen(InpTradeComment)>31) return "Trade comment must be 1-31 characters";
   if(InpEntryZone<0 || InpEntryZone>4.236)             return "Entry zone must be 0-4.236";
   if(InpBeforeTouchPercent<=0 || InpBeforeTouchPercent>20) return "Pre-touch window must be above 0 and at most 20%";
   if(InpGridGapPercent<0 || InpGridGapPercent>100)     return "Grid gap must be 0-100%";
   if(InpSpikeSensitivity<3 || InpSpikeSensitivity>200) return "Spike sensitivity must be 3-200";
   if(InpWarmupTicks<0 || InpWarmupTicks>500000)        return "Warm-up ticks must be 0-500000";
   if(InpMaxSpreadPoints<0 || InpSlippagePoints<0 || InpDisasterSLPoints<0) return "Spread, slippage and disaster SL must not be negative";
   if(InpPartialClosePercent<1 || InpPartialClosePercent>99) return "Partial close must be 1-99%";
   if(InpBreakEvenPoints<-1 || InpTrailStartPoints<-1 || InpTrailDistancePoints<0) return "Break-even/trailing: use -1 (off), 0 (auto) or points";
   if(InpTrailStartPoints>0 && InpTrailDistancePoints>0 && InpTrailStartPoints<=InpTrailDistancePoints) return "Trailing start must be larger than trailing distance";
   if(InpBasketTakeProfitPercent<0)                     return "Basket take-profit must not be negative";
   if(InpBasketStopPercent<=0 || InpBasketStopPercent>=100) return "Basket stop must be above 0 and below 100%";
   if(InpStopAddingPercent<0 || InpStopAddingPercent>InpBasketStopPercent) return "Stop-adding level must be between 0 and the basket stop";
   if(InpMaxDailyLossPercent<0 || InpMaxDailyLossPercent>=100) return "Daily loss limit must be 0-99%";
   if(InpMaxDailyProfitPercent<0)                       return "Daily profit target must not be negative";
   if(InpFreeMarginReservePercent<0 || InpFreeMarginReservePercent>=100) return "Free margin reserve must be 0-99%";
   if(InpCooldownMinutes<0 || InpCooldownMinutes>1440)  return "Cooldown must be 0-1440 minutes";
   if(InpStartHour<0 || InpStartHour>23 || InpEndHour<1 || InpEndHour>24) return "Hours: start 0-23, end 1-24";
   return "";
}

int OnInit()
{
   // Globals survive a timeframe change, so every piece of state is reset here.
   g_tester=(MQLInfoInteger(MQL_TESTER)!=0);
   ZeroMemory(g_fib);
   ZeroMemory(g_spike);
   ZeroMemory(g_guard);
   ZeroMemory(g_ui);
   ArrayResize(g_pivots,0);
   ArrayInitialize(g_attempted,false);
   g_ui.draw=(!g_tester || MQLInfoInteger(MQL_VISUAL_MODE)!=0);
   g_ui.enabled=(InpShowDashboard && g_ui.draw);
   g_ui.scale=1.0;
   g_paused=false; g_minLotUsed=false; g_nextLot=0; g_lastSecond=0;
   g_lastNotice=""; g_lastNoticeMs=0; g_note="Starting"; g_prefix=""; g_pre="";

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print(EA_DISPLAY," | A HEDGING account is required (baskets and partial closes). Netting accounts are not supported.");
      return INIT_FAILED;
   }
   string problem=ValidateInputs();
   if(problem!="") { Print(EA_DISPLAY," | Input error: ",problem); return INIT_PARAMETERS_INCORRECT; }
   if(!SymbolMatches())
   {
      Print(EA_DISPLAY," | ",_Symbol," does not contain '",InpSymbolKeyword,"'. Attach to MaxGainX 2000 or clear 'Trade only symbols containing'.");
      return INIT_PARAMETERS_INCORRECT;
   }

   RefreshSymbol();
   string identity=AccountInfoString(ACCOUNT_SERVER)+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+_Symbol+IntegerToString((long)InpMagic);
   g_prefix=EA_TAG+"_"+IntegerToString((long)HashText(identity))+"_";
   if(!g_tester)
   {
      // Exclusive open without FILE_SHARE flags: a second copy with the same
      // account/symbol/magic cannot start. The OS releases it after a crash.
      g_lock=FileOpen(g_prefix+"instance.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(g_lock==INVALID_HANDLE)
      {
         Print(EA_DISPLAY," | Another copy already runs on this account/symbol/magic. Use a different magic number.");
         return INIT_FAILED;
      }
   }
   g_pre=g_prefix+IntegerToString(ChartID())+"_";

   if(!g_tester)
   {
      if(GlobalVariableCheck(g_prefix+"PAUSE"))    g_paused=(GlobalVariableGet(g_prefix+"PAUSE")>0);
      if(GlobalVariableCheck(g_prefix+"COOLDOWN")) g_guard.cooldownUntil=(datetime)(long)GlobalVariableGet(g_prefix+"COOLDOWN");
   }
   g_telegramOn=(InpTelegram && !g_tester && StringLen(InpTelegramToken)>0 && StringLen(InpTelegramChat)>0);
   if(InpTelegram && !g_tester && !g_telegramOn) Print(EA_DISPLAY," | Telegram is on but the token or chat id is empty - Telegram disabled.");

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetAsyncMode(false);
   g_trade.SetDeviationInPoints(Deviation());
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   // History ticks are loaded by the first timer/tick, not here: CopyTicks
   // can wait up to 45 s for synchronisation and would freeze the chart.
   RefreshSymbol();
   CheckNewDay();
   UpdateEngine();
   ApplyTheme();
   if(g_ui.draw) EventSetMillisecondTimer(TIMER_MS);
   RefreshUi();

   Print(EA_DISPLAY," | ",EA_NAME," v",EA_VERSION," by ",EA_AUTHOR," (",EA_BRAND,") on ",_Symbol," ",TfName()," | lot mode ",EnumToString(InpLotMode),
         " | basket stop ",DoubleToString(InpBasketStopPercent,1),"% | daily loss ",DoubleToString(InpMaxDailyLossPercent,1),
         "% | ",g_symbolStatus);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_pre!="") ObjectsDeleteAll(0,g_pre);
   if(g_lock!=INVALID_HANDLE) { FileClose(g_lock); g_lock=INVALID_HANDLE; }
   RestoreTheme();
   ChartRedraw(0);
   // Open positions and their broker-side stops are left untouched.
}

void OnTick()
{
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q) || q.bid<=0 || q.ask<q.bid) return;
   if(q.time!=g_lastSecond) { g_lastSecond=q.time; Housekeeping(); }

   int jump=SpikeOnTick(q);
   bool fibReady=UpdateEngine();
   SelectSwing();
   if(fibReady)
   {
      double candleLow=iLow(_Symbol,_Period,0);
      g_fib.barMin=MathMin(g_fib.barMin,q.bid);
      if(candleLow>0) g_fib.barMin=MathMin(g_fib.barMin,candleLow);
   }

   // Management first: it runs even when new entries are blocked.
   SBasket b;
   ScanBasket(b);
   if(jump>0 && g_spike.warmed) { ReactToSpike(b); ScanBasket(b); }
   if(EvaluateGuards(b)) ScanBasket(b);
   ManageProfitStops(q);

   if(fibReady) RearmLevels(q.bid);
   TryBuy(q,b,jump);
}

void OnTimer()
{
   static int beat=0;
   beat++;
   if(beat%2==0) Housekeeping();                         // once a second, even without ticks
   if(g_ui.confirmUntil>0 && GetTickCount64()>g_ui.confirmUntil) g_ui.confirmUntil=0;
   g_ui.pulse=InpEnableFX ? !g_ui.pulse : false;
   SelectSwing();
   RefreshUi();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==g_pre+"HUD_PAUSE")
   {
      g_paused=!g_paused;
      if(!g_tester) { GlobalVariableSet(g_prefix+"PAUSE",g_paused ? 1.0 : 0.0); GlobalVariablesFlush(); }
      Notify(g_paused ? "New entries PAUSED from the dashboard" : "New entries RESUMED from the dashboard",MSG_LOG);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      RefreshUi();
   }
   else if(id==CHARTEVENT_OBJECT_CLICK && sparam==g_pre+"HUD_CLOSE")
   {
      ulong now=GetTickCount64();
      if(g_ui.confirmUntil>0 && now<=g_ui.confirmUntil)
      {
         g_ui.confirmUntil=0;
         if(CloseBasket("MANUAL CLOSE ALL")==0) g_note="All EA trades closed from the dashboard";
      }
      else g_ui.confirmUntil=now+CONFIRM_MS;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      RefreshUi();
   }
   else if(id==CHARTEVENT_CHART_CHANGE) RefreshUi();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   g_guard.closedDirty=true;
   if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   double pl=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
             HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)+HistoryDealGetDouble(trans.deal,DEAL_FEE);
   long reason=HistoryDealGetInteger(trans.deal,DEAL_REASON);
   string volume=Lots(HistoryDealGetDouble(trans.deal,DEAL_VOLUME));
   // EA-initiated closes are already summarised by CloseBasket/PartialOnSpike.
   if(reason==DEAL_REASON_SL)      Notify("Profit stop hit: "+volume+" lots "+Money(pl),MSG_TRADE);
   else if(reason==DEAL_REASON_TP) Notify("Take profit hit: "+volume+" lots "+Money(pl),MSG_TRADE);
   else if(reason==DEAL_REASON_SO) Notify("BROKER STOP OUT: "+volume+" lots "+Money(pl),MSG_ALERT);
   else                            Debug("Closed "+volume+" lots "+Money(pl));
}

double OnTester()
{
   double trades=TesterStatistics(STAT_TRADES);
   if(trades<30) return 0.0;                              // too few trades to trust
   double profit=TesterStatistics(STAT_PROFIT);
   if(profit<=0) return profit;
   double pf=TesterStatistics(STAT_PROFIT_FACTOR);
   double dd=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   return profit*pf/MathMax(dd,1.0);
}
//+------------------------------------------------------------------+
