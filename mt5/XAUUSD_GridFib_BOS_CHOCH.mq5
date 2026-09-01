//+------------------------------------------------------------------+
//|                         XAUUSD_GridFib_BOS_CHOCH.mq5              |
//| Grid + Fibonacci + BOS/CHOCH + capped martingale + auto distance  |
//| v3.00 adds: DOM/tick microstructure, FVG + liquidity sweeps,      |
//| HTF confirmation, per-position BE/trail/partial, calendar news    |
//| filter, alert/push/Telegram routing, CSV journal, file-persisted  |
//| state and a neon dashboard with live profile switching.           |
//|                                                                   |
//| Educational/research software. No profitability is guaranteed.    |
//| A grid with lot progression can lose more than a single trade     |
//| ever risks: run it on a demo account first and size it so the     |
//| full ladder is survivable.                                        |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      "https://www.mql5.com"
#property version   "3.00"
#property description "Multi-profile XAUUSD structure/grid/scalp EA with capped recovery and futuristic controls"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| CONFIG - enumerations                                            |
//+------------------------------------------------------------------+
enum ENUM_GF_SIGNAL_MODE
  {
   GF_SIGNAL_BOS_AND_CHOCH=0,          // BOS and CHOCH
   GF_SIGNAL_BOS_ONLY=1,               // BOS only
   GF_SIGNAL_CHOCH_ONLY=2              // CHOCH only
  };

enum ENUM_GF_DISTANCE_MODE
  {
   GF_DISTANCE_FIXED=0,                // Fixed price distance
   GF_DISTANCE_ATR=1,                  // ATR distance
   GF_DISTANCE_AUTO_SWITCH=2           // ATR distance with volatility regime switch
  };

enum ENUM_GF_LOT_MODE
  {
   GF_LOT_FIXED=0,                     // Fixed lot on every level
   GF_LOT_GEOMETRIC=1,                 // Geometric (capped martingale)
   GF_LOT_FIBONACCI=2,                 // Fibonacci sequence
   GF_LOT_RISK_PERCENT=3               // Risk percent of equity per level
  };

enum ENUM_GF_PROFILE
  {
   GF_PROFILE_NORMAL=0,                // Normal structure trading
   GF_PROFILE_HFT=1,                   // HFT-style micro scalp
   GF_PROFILE_AGGRESSIVE=2,            // Aggressive
   GF_PROFILE_INSANE=3                 // Insane sniper
  };

enum ENUM_GF_NEWS_LEVEL
  {
   GF_NEWS_OFF=0,                      // Do not filter news
   GF_NEWS_HIGH=1,                     // Block high impact only
   GF_NEWS_MODERATE=2,                 // Block moderate and high
   GF_NEWS_ALL=3                       // Block every scheduled event
  };

//+------------------------------------------------------------------+
//| CONFIG - inputs                                                  |
//+------------------------------------------------------------------+
input group "Identity and execution"
input bool                 InpRequireGoldSymbol=true;         // Refuse to run on non-gold symbols
input ulong                InpMagic=26090201;                 // Magic number
input int                  InpDeviationPoints=30;             // Max deviation (points)
input bool                 InpAllowLong=true;                 // Allow long baskets
input bool                 InpAllowShort=true;                // Allow short baskets

input group "Runtime trading profiles"
input ENUM_GF_PROFILE      InpTradingProfile=GF_PROFILE_NORMAL; // Starting profile
input bool                 InpAllowDashboardProfileSwitch=true; // Allow profile switching from the panel
input double               InpHFTLotFactor=0.75;              // HFT lot factor
input double               InpAggressiveLotFactor=1.50;       // Aggressive lot factor
input double               InpInsaneLotFactor=3.00;           // Insane lot factor
input double               InpHFTTargetFactor=0.25;           // HFT basket target factor
input double               InpAggressiveTargetFactor=0.80;    // Aggressive basket target factor
input double               InpInsaneTargetFactor=4.00;        // Insane basket target factor
input double               InpHFTDistanceFactor=0.35;         // HFT grid distance factor
input double               InpAggressiveDistanceFactor=0.65;  // Aggressive grid distance factor
input double               InpInsaneDistanceFactor=0.50;      // Insane grid distance factor

input group "HFT-inspired tick and DOM scalp"
input bool                 InpUseHFTDepthOfMarket=true;       // Subscribe to depth of market
input int                  InpHFTTickWindow=20;               // Tick window for micro impulse
input double               InpHFTImpulsePrice=0.30;           // Micro impulse size (price)
input double               InpHFTDOMThreshold=0.10;           // DOM imbalance threshold (-1..1)
input int                  InpHFTMinSignalGapSeconds=3;       // Min seconds between micro signals

input group "BOS / CHOCH market structure"
input ENUM_TIMEFRAMES      InpStructureTF=PERIOD_M15;         // Structure timeframe
input ENUM_GF_SIGNAL_MODE  InpSignalMode=GF_SIGNAL_BOS_AND_CHOCH; // Accepted structure events
input int                  InpPivotLeft=3;                    // Pivot bars to the left
input int                  InpPivotRight=3;                   // Pivot bars to the right
input int                  InpStructureLookback=350;          // Structure warm-up bars
input double               InpBreakBufferPrice=0.10;          // Break confirmation buffer (price)
input bool                 InpCloseOnOppositeStructure=true;  // Close basket on opposite structure
input bool                 InpDrawStructure=true;             // Draw structure objects

input group "Smart money confluence"
input bool                 InpUseFVG=true;                    // Detect fair value gaps
input bool                 InpUseLiquiditySweep=true;         // Detect liquidity sweeps
input bool                 InpRequireDiscountPremium=false;   // Longs in discount, shorts in premium only
input bool                 InpUseHTFConfirmation=true;        // Use higher timeframe confirmation
input ENUM_TIMEFRAMES      InpHTFTimeframe=PERIOD_H1;         // Higher timeframe
input int                  InpHTFFastMA=21;                   // HTF fast EMA period
input int                  InpHTFSlowMA=55;                   // HTF slow EMA period
input bool                 InpHTFBlocksCounterTrend=true;     // Reject entries against the HTF trend

input group "Fibonacci retracement entry"
input bool                 InpUseFibRetracement=false;        // Wait for a Fibonacci retracement
input double               InpFibRetraceShallow=0.382;        // Shallow retracement ratio
input double               InpFibRetraceDeep=0.618;           // Deep retracement ratio
input int                  InpFibEntryExpiryBars=12;          // Setup expiry (bars)

input group "Grid and automatic distance"
input int                  InpMaxGridLevels=5;                // Max grid levels
input ENUM_GF_DISTANCE_MODE InpDistanceMode=GF_DISTANCE_AUTO_SWITCH; // Grid distance mode
input double               InpFixedDistancePrice=3.00;        // Fixed grid distance (price)
input bool                 InpUseFibGridSpacing=true;         // Widen the grid on the Fibonacci sequence
input int                  InpATRPeriod=14;                   // ATR period
input ENUM_TIMEFRAMES      InpATRTF=PERIOD_M15;               // ATR timeframe
input double               InpATRDistanceMultiplier=1.20;     // ATR distance multiplier
input int                  InpATRRegimeLookback=50;           // ATR regime lookback
input double               InpAutoLowRatio=0.75;              // Quiet regime ratio
input double               InpAutoHighRatio=1.30;             // Volatile regime ratio
input double               InpAutoLowMultiplier=0.80;         // Quiet regime distance multiplier
input double               InpAutoNormalMultiplier=1.00;      // Normal regime distance multiplier
input double               InpAutoHighMultiplier=1.50;        // Volatile regime distance multiplier
input double               InpMinDistancePrice=1.50;          // Min grid distance (price)
input double               InpMaxDistancePrice=15.00;         // Max grid distance (price)
input int                  InpMinSecondsBetweenEntries=60;    // Min seconds between entries

input group "Lot progression / martingale"
input ENUM_GF_LOT_MODE     InpLotMode=GF_LOT_GEOMETRIC;       // Lot progression mode
input double               InpBaseLot=0.01;                   // Base lot
input double               InpRiskPercentPerLevel=0.25;       // Risk percent per level (risk mode)
input double               InpRiskStopPrice=8.00;             // Reference stop distance for risk sizing
input double               InpMartingaleMultiplier=1.35;      // Geometric multiplier
input double               InpMaxLotPerOrder=0.10;            // Max lot per order
input double               InpMaxBasketLots=0.25;             // Max total basket lots

input group "Basket exits"
input double               InpBasketTakeProfitMoney=35.0;     // Basket target (account currency)
input double               InpBasketStopLossMoney=150.0;      // Basket hard stop (account currency)
input bool                 InpUseBasketProfitTrail=true;      // Trail the basket profit
input double               InpTrailStartMoney=20.0;           // Basket trail activation (money)
input double               InpTrailGivebackMoney=8.0;         // Basket trail giveback (money)
input double               InpEmergencySLPrice=0.0;           // Per-order emergency stop (price, 0 = off)
input int                  InpCooldownAfterBasketSeconds=900; // Cooldown after a basket closes
input int                  InpMaxBasketMinutes=0;             // Basket time stop (minutes, 0 = off)

input group "Per-position protection"
input bool                 InpUseBreakEven=true;              // Move stops to break-even
input double               InpBreakEvenTriggerPrice=2.50;     // Break-even trigger (price)
input double               InpBreakEvenOffsetPrice=0.30;      // Break-even offset (price)
input bool                 InpUseTrailingStop=true;           // Trail per-position stops
input double               InpTrailATRMultiplier=1.50;        // Trailing distance (ATR multiple)
input double               InpTrailStepPrice=0.40;            // Min trailing step (price)
input bool                 InpUsePartialClose=false;          // Take a partial profit
input double               InpPartialTriggerPrice=4.00;       // Partial close trigger (price)
input double               InpPartialClosePercent=50.0;       // Percent of the position to close

input group "Account and entry protection"
input double               InpMaxDailyLossPct=3.0;            // Max daily loss (% of day-start balance)
input double               InpMaxDailyProfitPct=0.0;          // Daily profit lock (%, 0 = off)
input double               InpMaxIntradayEquityDDPct=8.0;     // Max intraday equity drawdown (%)
input double               InpMaxSpreadPrice=0.80;            // Max spread (price)
input double               InpMinMarginLevelPct=300.0;        // Min margin level (%)
input double               InpMinFreeMarginPct=35.0;          // Min projected free margin (%)
input int                  InpSessionStartHour=0;             // Session start hour (server)
input int                  InpSessionEndHour=0;               // Session end hour (server)

input group "Economic calendar news filter"
input ENUM_GF_NEWS_LEVEL   InpNewsFilterLevel=GF_NEWS_HIGH;   // News importance to block
input string               InpNewsCurrencies="USD,XAU";       // Currencies to watch (comma separated)
input int                  InpNewsMinutesBefore=15;           // Block minutes before an event
input int                  InpNewsMinutesAfter=15;            // Block minutes after an event
input bool                 InpNewsClosesBasket=false;         // Close the basket before an event

input group "Alerts and reporting"
input bool                 InpUseTerminalAlerts=false;        // Terminal alert popups
input bool                 InpUsePushNotifications=false;     // MetaQuotes ID push notifications
input bool                 InpUseTelegram=false;              // Telegram messages
input string               InpTelegramToken="";               // Telegram bot token
input string               InpTelegramChatId="";              // Telegram chat id
input bool                 InpWriteCsvJournal=true;           // Write a CSV trade journal

input group "Chart control panel"
input bool                 InpShowPanel=true;                 // Show the dashboard
input ENUM_BASE_CORNER     InpPanelCorner=CORNER_LEFT_UPPER;  // Panel corner
input int                  InpPanelX=12;                      // Panel X offset
input int                  InpPanelY=28;                      // Panel Y offset

//+------------------------------------------------------------------+
//| CONFIG - THEME (every colour in the program is defined here)     |
//+------------------------------------------------------------------+
#define THEME_BG            C'7,12,20'         // Panel background
#define THEME_SURFACE       C'13,24,38'        // Card surface
#define THEME_SURFACE_2     C'20,34,52'        // Raised surface
#define THEME_BORDER        C'61,91,122'       // Panel border
#define THEME_TEXT          C'238,246,255'     // Primary text
#define THEME_MUTED         C'176,197,219'     // Secondary text
#define THEME_CYAN          C'76,201,240'      // Neon accent
#define THEME_GOLD          C'240,190,86'      // Gold accent
#define THEME_GREEN         C'48,196,140'      // Profit / buy
#define THEME_RED           C'224,72,90'       // Loss / sell
#define THEME_AMBER         C'196,124,32'      // Warning
#define THEME_VIOLET        C'129,102,220'     // Fibonacci map
#define THEME_IDLE          C'93,105,125'      // Disabled control
#define THEME_ZONE_DEMAND   C'21,72,63'        // Demand zone
#define THEME_ZONE_SUPPLY   C'82,34,48'        // Supply zone
#define THEME_ZONE_BULL_OB  C'19,64,78'        // Bullish order block
#define THEME_ZONE_BEAR_OB  C'75,37,69'        // Bearish order block
#define THEME_ZONE_BULL_FVG C'24,58,52'        // Bullish fair value gap
#define THEME_ZONE_BEAR_FVG C'66,32,44'        // Bearish fair value gap
#define THEME_SWING_HIGH    C'255,191,79'      // Swing high level
#define THEME_SWING_LOW     C'96,165,250'      // Swing low level

//+------------------------------------------------------------------+
//| CONFIG - METRICS (every pixel dimension is defined here)         |
//+------------------------------------------------------------------+
#define UI_FONT             "Segoe UI"
#define UI_FONT_BOLD        "Segoe UI Semibold"
#define UI_FONT_SIZE        9
#define UI_FONT_SIZE_TITLE  11
#define UI_PANEL_W          336
#define UI_PANEL_H          392
#define UI_PAD              12
#define UI_ROW_H            19
#define UI_ROW_TOP          40
#define UI_BTN_H            26
#define UI_BTN_W_HALF       152
#define UI_BTN_W_FULL       312
#define UI_BTN_W_QUARTER    72
#define UI_ZONE_BARS        150

//+------------------------------------------------------------------+
//| CONFIG - engine constants                                        |
//+------------------------------------------------------------------+
#define GF_TICK_BUFFER      256                 // Micro-structure ring buffer size
#define GF_STATE_VERSION    3                   // Persisted state layout version
#define GF_NOTIFY_QUEUE     16                  // Outbound message queue depth
#define GF_HTTP_TIMEOUT     5000                // WebRequest timeout (ms)
#define GF_NEWS_REFRESH_SEC 300                 // Calendar refresh interval
#define GF_BOOK_STALE_SEC   5                   // DOM snapshot lifetime

//+------------------------------------------------------------------+
//| STATE - runtime state, grouped so the global namespace stays thin|
//+------------------------------------------------------------------+
struct SRuntime
  {
   ENUM_GF_PROFILE   profile;             // Live profile (seeded from the input, then owned here)
   bool              autoEnabled;         // Automated entries armed
   bool              pauseNewEntries;     // Management continues, entries are held
   datetime          lastStructureBar;    // Last processed structure bar
   datetime          nextEntryTime;       // Cooldown barrier
   datetime          lastEntryTime;       // Throttle reference
   int               gridLevel;           // Level of the deepest filled grid order
   double            lastEntryPrice;      // Fill price of the last grid order
   double            trailPeakProfit;     // High-water mark of the basket profit
   string            panelStatus;         // Human readable status line
  };

struct SStructureState
  {
   double            swingHigh;           // Last confirmed swing high
   double            swingLow;            // Last confirmed swing low
   datetime          swingHighTime;
   datetime          swingLowTime;
   bool              highBroken;          // Swing high already used for a break
   bool              lowBroken;           // Swing low already used for a break
   int               trend;               // 1 bullish, -1 bearish, 0 unknown
   int               htfTrend;            // Higher timeframe bias
   string            lastEvent;           // Last BOS/CHOCH description
   double            bullOBLow;           // Bullish order block
   double            bullOBHigh;
   datetime          bullOBTime;
   double            bearOBLow;           // Bearish order block
   double            bearOBHigh;
   datetime          bearOBTime;
   double            demandLow;           // Demand zone around the swing low
   double            demandHigh;
   double            supplyLow;           // Supply zone around the swing high
   double            supplyHigh;
   double            bullFVGLow;          // Bullish fair value gap
   double            bullFVGHigh;
   datetime          bullFVGTime;
   double            bearFVGLow;          // Bearish fair value gap
   double            bearFVGHigh;
   datetime          bearFVGTime;
   int               sweepDirection;      // Liquidity sweep bias, 0 = none
   datetime          sweepTime;
   int               confluenceScore;     // Score of the last evaluated setup
   string            confluenceText;      // Which factors contributed
  };

struct SMicroState
  {
   bool              bookSubscribed;      // MarketBookAdd succeeded
   bool              domValid;            // A usable DOM snapshot exists
   double            domImbalance;        // (bidVol - askVol) / (bidVol + askVol)
   double            bidVolume;           // Aggregated bid side volume
   double            askVolume;           // Aggregated ask side volume
   datetime          bookTime;            // Time of the DOM snapshot
   double            mid[GF_TICK_BUFFER]; // Ring buffer of mid prices
   datetime          ts[GF_TICK_BUFFER];  // Ring buffer of tick times
   int               head;                // Newest slot in the ring buffer
   int               count;               // Filled slots
   double            impulse;             // Signed micro impulse over the window
   int               impulseDirection;    // Direction of the last micro impulse
   double            ticksPerSecond;      // Observed tick rate
   datetime          lastSignalTime;      // Last micro signal, for throttling
  };

struct SRiskState
  {
   bool              locked;              // Trading halted for the day
   string            reason;              // Why it is halted
   int               dayId;               // yyyymmdd of the current trading day
   double            peakEquity;          // Intraday equity high-water mark
   double            dayStartBalance;     // Balance at the start of the day
   bool              profitLocked;        // Daily profit target reached
   bool              newsBlocked;         // Inside a news window
   string            newsEvent;           // Event that blocks trading
   datetime          newsUntil;           // End of the blocking window
   datetime          newsRefreshed;       // Last calendar refresh
  };

struct SStatsState
  {
   int               baskets;             // Closed baskets counted this session
   int               wins;
   int               losses;
   double            grossProfit;
   double            grossLoss;
   double            bestBasket;
   double            worstBasket;
   double            lastBasketProfit;
  };

struct SPendingSetup
  {
   int               direction;           // 1 long, -1 short, 0 idle
   int               kind;                // 1 BOS, 2 CHOCH, 3 micro impulse
   bool              usesZone;            // Waiting inside a Fibonacci zone
   double            zoneLow;
   double            zoneHigh;
   datetime          expiry;
  };

// Persisted snapshot. Plain data only - no strings, no dynamic arrays.
struct SPersistState
  {
   int               version;
   int               gridLevel;
   int               profile;
   int               dayId;
   double            lastEntryPrice;
   double            peakEquity;
   double            dayStartBalance;
   double            trailPeakProfit;
  };

CTrade          trade;
SRuntime        g_rt;
SStructureState g_str;
SMicroState     g_micro;
SRiskState      g_risk;
SStatsState     g_stats;
SPendingSetup   g_pending;

int      g_atrHandle=INVALID_HANDLE;      // ATR on the active profile timeframe
int      g_htfFastHandle=INVALID_HANDLE;  // Higher timeframe fast EMA
int      g_htfSlowHandle=INVALID_HANDLE;  // Higher timeframe slow EMA
string   g_prefix="GFBC_";                // Chart object namespace
string   g_stateFile="";                  // Persisted state file name
string   g_journalFile="";                // CSV journal file name
string   g_newsCurrencies[];              // Parsed news currency filter
ulong    g_partialDone[];                 // Tickets that already took a partial profit
string   g_notifyQueue[GF_NOTIFY_QUEUE];  // Outbound Telegram queue
int      g_notifyCount=0;
double   g_dailyProfitCache=0.0;          // Cached daily result of this EA
ulong    g_dailyProfitStamp=0;            // GetTickCount64 stamp of that cache

//+------------------------------------------------------------------+
//| CORE - small utilities                                           |
//+------------------------------------------------------------------+
datetime ServerNow()
  {
   datetime t=TimeTradeServer();
   if(t<=0) t=TimeCurrent();
   return t;
  }

int DateId(const datetime when)
  {
   MqlDateTime dt;
   TimeToStruct(when,dt);
   return(dt.year*10000+dt.mon*100+dt.day);
  }

datetime StartOfDay(const datetime when)
  {
   MqlDateTime dt;
   TimeToStruct(when,dt);
   dt.hour=0;
   dt.min=0;
   dt.sec=0;
   return StructToTime(dt);
  }

string DirectionText(const int direction)
  {
   if(direction>0) return "BUY";
   if(direction<0) return "SELL";
   return "FLAT";
  }

string TrendText(const int trend)
  {
   if(trend>0) return "Bullish";
   if(trend<0) return "Bearish";
   return "Neutral";
  }

string ProfileText(const ENUM_GF_PROFILE profile)
  {
   if(profile==GF_PROFILE_HFT) return "HFT SCALP";
   if(profile==GF_PROFILE_AGGRESSIVE) return "AGGRESSIVE";
   if(profile==GF_PROFILE_INSANE) return "INSANE SNIPER";
   return "NORMAL";
  }

double Clamp(const double value,const double min_value,const double max_value)
  {
   return MathMax(min_value,MathMin(max_value,value));
  }

//--- Iterative Fibonacci: used for both lot and spacing progressions.
int Fibonacci(const int n)
  {
   if(n<=2) return 1;
   int a=1,b=1;
   for(int i=3;i<=n;i++)
     {
      int c=a+b;
      a=b;
      b=c;
     }
   return b;
  }

double FullFibRatio(const int index)
  {
   if(index<=0) return 0.236;
   if(index==1) return 0.382;
   if(index==2) return 0.500;
   if(index==3) return 0.618;
   if(index==4) return 0.786;
   if(index==5) return 1.000;
   if(index==6) return 1.272;
   return 1.618;
  }

int VolumeDigits(const double step)
  {
   for(int digits=0;digits<=8;digits++)
     {
      double scaled=step*MathPow(10.0,digits);
      if(MathAbs(scaled-MathRound(scaled))<1e-8)
         return digits;
     }
   return 8;
  }

//--- Floor to the volume step so the result never risks more than requested.
double NormalizeVolume(const double requested)
  {
   double min_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=min_lot;
   if(step<=0.0) return 0.0;

   double capped=MathMin(requested,MathMin(max_lot,InpMaxLotPerOrder));
   double lots=MathFloor((capped+1e-12)/step)*step;
   if(lots<min_lot-1e-12) return 0.0;
   return NormalizeDouble(lots,VolumeDigits(step));
  }

//--- Rounding to tick size, not to digits: gold ticks are not always 1 point.
double NormalizePriceToTick(const double price)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0) tick=_Point;
   if(tick<=0.0) return price;
   return NormalizeDouble(MathRound(price/tick)*tick,_Digits);
  }

//--- Minimum legal distance between the market and a protective level.
double MinStopDistance()
  {
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long points=MathMax(stops,freeze);
   if(points<=0) points=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*3;
   return (double)points*_Point;
  }

//--- A modify request that changes nothing is rejected with 10025.
bool LevelsDiffer(const double a,const double b)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0) tick=_Point;
   return(MathAbs(a-b)>=tick/2.0);
  }

bool IsGoldSymbol()
  {
   string name=_Symbol;
   StringToUpper(name);
   return(StringFind(name,"XAU")>=0 || StringFind(name,"GOLD")>=0);
  }

bool IsHedgingAccount()
  {
   return((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==
          ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

bool IsTradeRetcodeSuccessful()
  {
   uint code=trade.ResultRetcode();
   return(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL ||
          code==TRADE_RETCODE_PLACED);
  }

void LogTradeFailure(const string action)
  {
   PrintFormat("%s failed: retcode=%u (%s), broker=%s, error=%d",
               action,trade.ResultRetcode(),trade.ResultRetcodeDescription(),
               trade.ResultComment(),GetLastError());
  }

//+------------------------------------------------------------------+
//| CORE - profile accessors                                         |
//| Every runtime decision reads these, never the raw input, so the   |
//| panel can switch profiles while the EA is running.                |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ActiveStructureTF()
  {
   if(g_rt.profile==GF_PROFILE_HFT || g_rt.profile==GF_PROFILE_INSANE) return PERIOD_M1;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return PERIOD_M5;
   return InpStructureTF;
  }

ENUM_TIMEFRAMES ActiveATRTF()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return PERIOD_M1;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return PERIOD_M5;
   if(g_rt.profile==GF_PROFILE_INSANE) return PERIOD_M5;
   return InpATRTF;
  }

int ActiveATRPeriod()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return 7;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return 10;
   return InpATRPeriod;
  }

int ActiveMaxGridLevels()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return MathMin(InpMaxGridLevels,4);
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpMaxGridLevels;
   if(g_rt.profile==GF_PROFILE_INSANE) return MathMin(InpMaxGridLevels,2);
   return MathMin(InpMaxGridLevels,5);
  }

double ActiveLotFactor()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return InpHFTLotFactor;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpAggressiveLotFactor;
   if(g_rt.profile==GF_PROFILE_INSANE) return InpInsaneLotFactor;
   return 1.0;
  }

ENUM_GF_LOT_MODE ActiveLotMode()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return GF_LOT_FIXED;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE || g_rt.profile==GF_PROFILE_INSANE)
      return GF_LOT_GEOMETRIC;
   return InpLotMode;
  }

double ActiveMartingaleMultiplier()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return MathMax(1.10,InpMartingaleMultiplier);
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return MathMax(1.65,InpMartingaleMultiplier);
   if(g_rt.profile==GF_PROFILE_INSANE) return MathMax(1.80,InpMartingaleMultiplier);
   return InpMartingaleMultiplier;
  }

double ActiveTargetMoney()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return InpBasketTakeProfitMoney*InpHFTTargetFactor;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpBasketTakeProfitMoney*InpAggressiveTargetFactor;
   if(g_rt.profile==GF_PROFILE_INSANE) return InpBasketTakeProfitMoney*InpInsaneTargetFactor;
   return InpBasketTakeProfitMoney;
  }

double ActiveStopMoney()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return InpBasketStopLossMoney*0.35;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpBasketStopLossMoney*1.25;
   if(g_rt.profile==GF_PROFILE_INSANE) return InpBasketStopLossMoney*2.00;
   return InpBasketStopLossMoney;
  }

double ActiveTrailStartMoney()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return InpTrailStartMoney*0.25;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpTrailStartMoney*0.75;
   if(g_rt.profile==GF_PROFILE_INSANE) return InpTrailStartMoney*3.00;
   return InpTrailStartMoney;
  }

double ActiveTrailGivebackMoney()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return InpTrailGivebackMoney*0.25;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpTrailGivebackMoney*0.75;
   if(g_rt.profile==GF_PROFILE_INSANE) return InpTrailGivebackMoney*2.00;
   return InpTrailGivebackMoney;
  }

double ActiveDistanceFactor()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return InpHFTDistanceFactor;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return InpAggressiveDistanceFactor;
   if(g_rt.profile==GF_PROFILE_INSANE) return InpInsaneDistanceFactor;
   return 1.0;
  }

int ActiveEntryThrottleSeconds()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return 1;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return 10;
   if(g_rt.profile==GF_PROFILE_INSANE) return 5;
   return InpMinSecondsBetweenEntries;
  }

int ActiveCooldownSeconds()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return 5;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return 60;
   if(g_rt.profile==GF_PROFILE_INSANE) return 30;
   return InpCooldownAfterBasketSeconds;
  }

//--- Time stop in minutes. The profile floor wins when the input is off (0).
int ActiveMaxBasketMinutes()
  {
   int profile_minutes=0;
   if(g_rt.profile==GF_PROFILE_HFT) profile_minutes=5;
   else if(g_rt.profile==GF_PROFILE_AGGRESSIVE) profile_minutes=30;
   else if(g_rt.profile==GF_PROFILE_INSANE) profile_minutes=20;

   if(InpMaxBasketMinutes<=0) return profile_minutes;
   if(profile_minutes<=0) return InpMaxBasketMinutes;
   return MathMin(InpMaxBasketMinutes,profile_minutes);
  }

int ActiveRequiredConfluence()
  {
   if(g_rt.profile==GF_PROFILE_INSANE) return 4;
   if(g_rt.profile==GF_PROFILE_NORMAL) return 2;
   return 1;
  }

//--- HFT and aggressive profiles chase the break; the others may wait for a pullback.
bool ActiveUsesFibRetracement()
  {
   if(g_rt.profile==GF_PROFILE_HFT || g_rt.profile==GF_PROFILE_AGGRESSIVE) return false;
   if(g_rt.profile==GF_PROFILE_INSANE) return true;
   return InpUseFibRetracement;
  }

double ActiveFibShallow()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return 0.236;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return 0.236;
   if(g_rt.profile==GF_PROFILE_INSANE) return 0.618;
   return InpFibRetraceShallow;
  }

double ActiveFibDeep()
  {
   if(g_rt.profile==GF_PROFILE_HFT) return 0.500;
   if(g_rt.profile==GF_PROFILE_AGGRESSIVE) return 0.382;
   if(g_rt.profile==GF_PROFILE_INSANE) return 0.786;
   return InpFibRetraceDeep;
  }

//--- Micro-structure entries only make sense on the fast profiles.
bool ActiveUsesMicroSignals()
  {
   return(g_rt.profile==GF_PROFILE_HFT || g_rt.profile==GF_PROFILE_INSANE);
  }

//+------------------------------------------------------------------+
//| CORE - notifications (terminal, push, Telegram)                  |
//| WebRequest blocks, so Telegram messages are queued here and sent  |
//| from OnTimer, never from the tick path.                           |
//+------------------------------------------------------------------+
string UrlEncode(const string text)
  {
   string out="";
   int length=StringLen(text);
   for(int i=0;i<length;i++)
     {
      ushort ch=StringGetCharacter(text,i);
      if((ch>='A' && ch<='Z') || (ch>='a' && ch<='z') || (ch>='0' && ch<='9') ||
         ch=='-' || ch=='_' || ch=='.' || ch=='~')
         out+=ShortToString(ch);
      else if(ch==' ')
         out+="%20";
      else
        {
         // Encode the character as UTF-8 bytes, then percent-escape each byte.
         string single=ShortToString(ch);
         uchar bytes[];
         int written=StringToCharArray(single,bytes,0,WHOLE_ARRAY,CP_UTF8);
         for(int b=0;b<written;b++)
           {
            if(bytes[b]==0) continue;
            out+=StringFormat("%%%02X",bytes[b]);
           }
        }
     }
   return out;
  }

void QueueTelegram(const string message)
  {
   if(!InpUseTelegram) return;
   if(StringLen(InpTelegramToken)==0 || StringLen(InpTelegramChatId)==0) return;
   if(g_notifyCount>=GF_NOTIFY_QUEUE)
     {
      // Drop the oldest message rather than growing without bound.
      for(int i=1;i<GF_NOTIFY_QUEUE;i++) g_notifyQueue[i-1]=g_notifyQueue[i];
      g_notifyCount=GF_NOTIFY_QUEUE-1;
     }
   g_notifyQueue[g_notifyCount]=message;
   g_notifyCount++;
  }

bool SendTelegramNow(const string message)
  {
   string url=StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",
                           InpTelegramToken,UrlEncode(InpTelegramChatId),UrlEncode(message));
   char post[];
   char result[];
   string headers="";
   ResetLastError();
   int code=WebRequest("GET",url,"",GF_HTTP_TIMEOUT,post,result,headers);
   if(code==-1)
     {
      int error=GetLastError();
      if(error==4014 || error==5203)
         Print("Telegram blocked: allow https://api.telegram.org in Tools > Options > Expert Advisors.");
      else
         PrintFormat("Telegram WebRequest error %d",error);
      return false;
     }
   if(code!=200)
     {
      PrintFormat("Telegram HTTP %d",code);
      return false;
     }
   return true;
  }

//--- Drains one queued message per timer tick so a slow endpoint never stalls the EA.
void FlushNotifications()
  {
   if(g_notifyCount<=0) return;
   if(MQLInfoInteger(MQL_TESTER)!=0)
     {
      g_notifyCount=0;
      return;
     }
   string message=g_notifyQueue[0];
   for(int i=1;i<g_notifyCount;i++) g_notifyQueue[i-1]=g_notifyQueue[i];
   g_notifyCount--;
   SendTelegramNow(message);
  }

//--- Single routing point for every outbound event.
void NotifyEvent(const string title,const string body,const bool important)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)!=0) return;   // Logging dominates optimization runtime.
   string message=StringFormat("[%s %s] %s: %s",_Symbol,ProfileText(g_rt.profile),title,body);
   Print(message);
   if(InpUseTerminalAlerts && important && MQLInfoInteger(MQL_TESTER)==0)
      Alert(message);
   if(InpUsePushNotifications && MQLInfoInteger(MQL_TESTER)==0)
      SendNotification(message);
   QueueTelegram(message);
  }

//+------------------------------------------------------------------+
//| CORE - economic calendar news filter                             |
//| The calendar is unavailable in the Strategy Tester, so the filter |
//| is skipped there instead of silently blocking every backtest bar. |
//+------------------------------------------------------------------+
void ParseNewsCurrencies()
  {
   ArrayResize(g_newsCurrencies,0);
   string parts[];
   int count=StringSplit(InpNewsCurrencies,StringGetCharacter(",",0),parts);
   for(int i=0;i<count;i++)
     {
      string token=parts[i];
      StringTrimLeft(token);          // Modifies in place and returns a count.
      StringTrimRight(token);
      StringToUpper(token);
      if(StringLen(token)==0) continue;
      int size=ArraySize(g_newsCurrencies);
      ArrayResize(g_newsCurrencies,size+1);
      g_newsCurrencies[size]=token;
     }
  }

bool NewsImportanceBlocks(const ENUM_CALENDAR_EVENT_IMPORTANCE importance)
  {
   if(InpNewsFilterLevel==GF_NEWS_ALL) return true;
   if(InpNewsFilterLevel==GF_NEWS_MODERATE)
      return(importance==CALENDAR_IMPORTANCE_MODERATE || importance==CALENDAR_IMPORTANCE_HIGH);
   if(InpNewsFilterLevel==GF_NEWS_HIGH)
      return(importance==CALENDAR_IMPORTANCE_HIGH);
   return false;
  }

//--- Refreshed on the timer, never per tick: the calendar query is not cheap.
void RefreshNewsWindow()
  {
   if(InpNewsFilterLevel==GF_NEWS_OFF || MQLInfoInteger(MQL_TESTER)!=0)
     {
      g_risk.newsBlocked=false;
      g_risk.newsEvent="";
      g_risk.newsUntil=0;
      return;
     }

   datetime now=ServerNow();
   if(g_risk.newsRefreshed>0 && now-g_risk.newsRefreshed<GF_NEWS_REFRESH_SEC)
     {
      // Between refreshes, only let an expired window lapse.
      if(g_risk.newsBlocked && now>g_risk.newsUntil)
        {
         g_risk.newsBlocked=false;
         g_risk.newsEvent="";
        }
      return;
     }
   g_risk.newsRefreshed=now;
   g_risk.newsBlocked=false;
   g_risk.newsEvent="";
   g_risk.newsUntil=0;

   datetime from=now-(datetime)(InpNewsMinutesAfter*60+3600);
   datetime to=now+(datetime)(InpNewsMinutesBefore*60+3600);
   int currencies=ArraySize(g_newsCurrencies);
   if(currencies<=0) return;

   for(int c=0;c<currencies;c++)
     {
      MqlCalendarValue values[];
      if(!CalendarValueHistory(values,from,to,NULL,g_newsCurrencies[c]))
         continue;
      int total=ArraySize(values);
      for(int i=0;i<total;i++)
        {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id,event)) continue;
         if(!NewsImportanceBlocks(event.importance)) continue;

         datetime start=values[i].time-(datetime)(InpNewsMinutesBefore*60);
         datetime end=values[i].time+(datetime)(InpNewsMinutesAfter*60);
         if(now<start || now>end) continue;

         g_risk.newsBlocked=true;
         g_risk.newsEvent=event.name;
         if(end>g_risk.newsUntil) g_risk.newsUntil=end;
        }
     }

   if(g_risk.newsBlocked)
      NotifyEvent("News filter",StringFormat("Trading held for %s until %s",
                  g_risk.newsEvent,TimeToString(g_risk.newsUntil,TIME_MINUTES)),false);
  }

//+------------------------------------------------------------------+
//| CORE - tick and depth-of-market micro structure                  |
//+------------------------------------------------------------------+
int MicroWindow()
  {
   return (int)Clamp((double)InpHFTTickWindow,3.0,(double)(GF_TICK_BUFFER-1));
  }

void MicroSubscribe()
  {
   if(!InpUseHFTDepthOfMarket || g_micro.bookSubscribed) return;
   if(MQLInfoInteger(MQL_TESTER)!=0) return;      // No book events in the tester.
   ResetLastError();
   if(MarketBookAdd(_Symbol))
      g_micro.bookSubscribed=true;
   else
      PrintFormat("Depth of market unavailable on %s (error %d) - running on ticks only.",
                  _Symbol,GetLastError());
  }

void MicroRelease()
  {
   if(!g_micro.bookSubscribed) return;
   MarketBookRelease(_Symbol);
   g_micro.bookSubscribed=false;
  }

//--- Aggregate the visible ladder into one signed imbalance in [-1, 1].
void MicroReadBook()
  {
   MqlBookInfo book[];
   if(!MarketBookGet(_Symbol,book))
     {
      g_micro.domValid=false;
      return;
     }
   int total=ArraySize(book);
   if(total<=0)
     {
      g_micro.domValid=false;
      return;
     }

   double bid_volume=0.0,ask_volume=0.0;
   for(int i=0;i<total;i++)
     {
      double volume=(book[i].volume_real>0.0 ? book[i].volume_real : (double)book[i].volume);
      if(book[i].type==BOOK_TYPE_BUY || book[i].type==BOOK_TYPE_BUY_MARKET)
         bid_volume+=volume;
      else if(book[i].type==BOOK_TYPE_SELL || book[i].type==BOOK_TYPE_SELL_MARKET)
         ask_volume+=volume;
     }

   double sum=bid_volume+ask_volume;
   g_micro.bidVolume=bid_volume;
   g_micro.askVolume=ask_volume;
   g_micro.bookTime=ServerNow();
   if(sum<=0.0)
     {
      g_micro.domValid=false;
      g_micro.domImbalance=0.0;
      return;
     }
   g_micro.domImbalance=(bid_volume-ask_volume)/sum;
   g_micro.domValid=true;
  }

//--- Push one tick into the ring buffer and recompute the micro impulse.
void MicroPushTick(const MqlTick &tick)
  {
   double mid=(tick.bid+tick.ask)/2.0;
   if(mid<=0.0) return;

   g_micro.head=(g_micro.head+1)%GF_TICK_BUFFER;
   g_micro.mid[g_micro.head]=mid;
   g_micro.ts[g_micro.head]=tick.time;
   if(g_micro.count<GF_TICK_BUFFER) g_micro.count++;

   int window=MathMin(MicroWindow(),g_micro.count);
   if(window<3)
     {
      g_micro.impulse=0.0;
      g_micro.impulseDirection=0;
      return;
     }

   int oldest=(g_micro.head-(window-1)+GF_TICK_BUFFER)%GF_TICK_BUFFER;
   g_micro.impulse=mid-g_micro.mid[oldest];

   int elapsed=(int)(g_micro.ts[g_micro.head]-g_micro.ts[oldest]);
   g_micro.ticksPerSecond=(elapsed>0 ? (double)window/(double)elapsed : (double)window);

   double threshold=MathMax(InpHFTImpulsePrice,_Point);
   if(g_micro.impulse>=threshold) g_micro.impulseDirection=1;
   else if(g_micro.impulse<=-threshold) g_micro.impulseDirection=-1;
   else g_micro.impulseDirection=0;

   // A DOM snapshot older than a few seconds is not evidence any more.
   if(g_micro.domValid && ServerNow()-g_micro.bookTime>GF_BOOK_STALE_SEC)
      g_micro.domValid=false;
  }

bool MicroDomAgrees(const int direction)
  {
   if(!g_micro.domValid) return false;
   if(direction>0) return(g_micro.domImbalance>=InpHFTDOMThreshold);
   if(direction<0) return(g_micro.domImbalance<=-InpHFTDOMThreshold);
   return false;
  }

//--- Micro impulse signal: a burst of same-direction ticks, DOM-confirmed when available.
int MicroSignal()
  {
   if(!ActiveUsesMicroSignals()) return 0;
   if(g_micro.impulseDirection==0) return 0;
   if(ServerNow()-g_micro.lastSignalTime<MathMax(1,InpHFTMinSignalGapSeconds)) return 0;
   if(InpUseHFTDepthOfMarket && g_micro.domValid && !MicroDomAgrees(g_micro.impulseDirection))
      return 0;
   return g_micro.impulseDirection;
  }

//+------------------------------------------------------------------+
//| CORE - position and basket accounting                            |
//+------------------------------------------------------------------+
struct SBasket
  {
   int               positions;      // Count of this EA's positions on this symbol
   int               direction;      // Net direction of the basket
   double            lots;           // Total volume
   double            profit;         // Floating profit including swap
   double            weightedOpen;   // Volume weighted average entry
   datetime          firstOpen;      // Oldest entry, for the time stop
  };

bool SelectOurPositionAt(const int index,ulong &ticket)
  {
   ticket=PositionGetTicket(index);
   if(ticket==0) return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) return false;
   return true;
  }

void BasketStats(SBasket &basket)
  {
   basket.positions=0;
   basket.direction=0;
   basket.lots=0.0;
   basket.profit=0.0;
   basket.weightedOpen=0.0;
   basket.firstOpen=0;
   double signed_lots=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      if(!SelectOurPositionAt(i,ticket)) continue;
      double volume=PositionGetDouble(POSITION_VOLUME);
      double open_price=PositionGetDouble(POSITION_PRICE_OPEN);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int sign=(type==POSITION_TYPE_BUY ? 1 : -1);

      basket.positions++;
      basket.lots+=volume;
      signed_lots+=sign*volume;
      basket.profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      basket.weightedOpen+=open_price*volume;
      if(basket.firstOpen==0 || opened<basket.firstOpen) basket.firstOpen=opened;
     }

   if(basket.lots>0.0) basket.weightedOpen/=basket.lots;
   if(signed_lots>1e-10) basket.direction=1;
   else if(signed_lots<-1e-10) basket.direction=-1;
  }

int BasketPositions()
  {
   SBasket basket;
   BasketStats(basket);
   return basket.positions;
  }

int BasketDirection()
  {
   SBasket basket;
   BasketStats(basket);
   return basket.direction;
  }

double LatestBasketEntryPrice()
  {
   long latest_msc=-1;
   double price=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      if(!SelectOurPositionAt(i,ticket)) continue;
      long opened_msc=PositionGetInteger(POSITION_TIME_MSC);
      if(opened_msc>latest_msc)
        {
         latest_msc=opened_msc;
         price=PositionGetDouble(POSITION_PRICE_OPEN);
        }
     }
   return price;
  }

//--- On a netting account another EA's position would be merged with ours.
bool HasForeignNettingPosition()
  {
   if(IsHedgingAccount()) return false;
   if(!PositionSelect(_Symbol)) return false;
   return((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic);
  }

//+------------------------------------------------------------------+
//| CORE - ticket registry for one-shot per-position actions         |
//+------------------------------------------------------------------+
bool TicketFlagged(const ulong ticket)
  {
   int total=ArraySize(g_partialDone);
   for(int i=0;i<total;i++)
      if(g_partialDone[i]==ticket) return true;
   return false;
  }

void FlagTicket(const ulong ticket)
  {
   if(TicketFlagged(ticket)) return;
   int size=ArraySize(g_partialDone);
   ArrayResize(g_partialDone,size+1);
   g_partialDone[size]=ticket;
  }

void ClearTicketFlags()
  {
   ArrayResize(g_partialDone,0);
  }

//+------------------------------------------------------------------+
//| CORE - persisted state                                           |
//| Survives restarts, timeframe changes and terminal crashes so a    |
//| half-built grid is never restarted from level one.                |
//+------------------------------------------------------------------+
void SaveState()
  {
   SPersistState state;
   state.version=GF_STATE_VERSION;
   state.gridLevel=g_rt.gridLevel;
   state.profile=(int)g_rt.profile;
   state.dayId=g_risk.dayId;
   state.lastEntryPrice=g_rt.lastEntryPrice;
   state.peakEquity=g_risk.peakEquity;
   state.dayStartBalance=g_risk.dayStartBalance;
   state.trailPeakProfit=g_rt.trailPeakProfit;

   int handle=FileOpen(g_stateFile,FILE_WRITE|FILE_BIN);
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("Could not write state file %s (error %d)",g_stateFile,GetLastError());
      return;
     }
   FileWriteStruct(handle,state);
   FileClose(handle);
  }

bool LoadState(SPersistState &state)
  {
   if(!FileIsExist(g_stateFile)) return false;
   int handle=FileOpen(g_stateFile,FILE_READ|FILE_BIN);
   if(handle==INVALID_HANDLE) return false;
   uint read=FileReadStruct(handle,state);
   FileClose(handle);
   if(read!=(uint)sizeof(state)) return false;
   return(state.version==GF_STATE_VERSION);
  }

void ResetGridState()
  {
   g_rt.gridLevel=0;
   g_rt.lastEntryPrice=0.0;
   g_rt.trailPeakProfit=0.0;
   ClearTicketFlags();
   SaveState();
  }

//--- Reconcile the saved snapshot with what the broker actually holds.
void RecoverGridState()
  {
   SBasket basket;
   BasketStats(basket);
   if(basket.positions<=0)
     {
      ResetGridState();
      return;
     }

   SPersistState state;
   if(LoadState(state))
     {
      g_rt.gridLevel=state.gridLevel;
      g_rt.lastEntryPrice=state.lastEntryPrice;
      g_rt.trailPeakProfit=state.trailPeakProfit;
     }
   if(g_rt.gridLevel<=0) g_rt.gridLevel=MathMax(1,basket.positions);
   if(g_rt.lastEntryPrice<=0.0) g_rt.lastEntryPrice=LatestBasketEntryPrice();

   g_rt.gridLevel=MathMax(1,MathMin(ActiveMaxGridLevels(),g_rt.gridLevel));
   SaveState();
   PrintFormat("Recovered an open basket: %d position(s), level %d, last entry %.*f",
               basket.positions,g_rt.gridLevel,_Digits,g_rt.lastEntryPrice);
  }

//+------------------------------------------------------------------+
//| CORE - CSV journal and session statistics                        |
//+------------------------------------------------------------------+
void JournalWrite(const string event,const string detail,const double money)
  {
   if(!InpWriteCsvJournal) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)!=0) return;   // Never write files per optimization pass.
   bool fresh=!FileIsExist(g_journalFile);
   int handle=FileOpen(g_journalFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(handle==INVALID_HANDLE) return;
   if(fresh)
      FileWrite(handle,"time","symbol","profile","event","detail","money","equity");
   FileSeek(handle,0,SEEK_END);
   FileWrite(handle,
             TimeToString(ServerNow(),TIME_DATE|TIME_SECONDS),
             _Symbol,
             ProfileText(g_rt.profile),
             event,
             detail,
             DoubleToString(money,2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
   FileClose(handle);
  }

void RegisterBasketResult(const double money)
  {
   g_stats.baskets++;
   g_stats.lastBasketProfit=money;
   if(money>=0.0)
     {
      g_stats.wins++;
      g_stats.grossProfit+=money;
      if(money>g_stats.bestBasket) g_stats.bestBasket=money;
     }
   else
     {
      g_stats.losses++;
      g_stats.grossLoss+=-money;
      if(money<g_stats.worstBasket) g_stats.worstBasket=money;
     }
  }

double SessionProfitFactor()
  {
   if(g_stats.grossLoss<=0.0)
      return(g_stats.grossProfit>0.0 ? 99.99 : 0.0);
   return g_stats.grossProfit/g_stats.grossLoss;
  }

double SessionWinRate()
  {
   int closed=g_stats.wins+g_stats.losses;
   if(closed<=0) return 0.0;
   return (double)g_stats.wins/(double)closed*100.0;
  }

//+------------------------------------------------------------------+
//| CORE - account protection                                        |
//+------------------------------------------------------------------+
//--- History scans are not free and this is read on every tick and every
//--- panel refresh, so the result is cached for a second and invalidated
//--- immediately by OnTradeTransaction whenever a deal lands.
void InvalidateDailyProfitCache()
  {
   g_dailyProfitStamp=0;
  }

double DailyEAProfit()
  {
   ulong now_ms=GetTickCount64();
   if(g_dailyProfitStamp>0 && now_ms-g_dailyProfitStamp<1000)
      return g_dailyProfitCache;

   datetime now=ServerNow();
   if(!HistorySelect(StartOfDay(now),now)) return 0.0;
   double result=0.0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagic) continue;
      result+=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      result+=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
      result+=HistoryDealGetDouble(ticket,DEAL_SWAP);
      result+=HistoryDealGetDouble(ticket,DEAL_FEE);
     }

   g_dailyProfitCache=result;
   g_dailyProfitStamp=now_ms;
   return result;
  }

void RefreshDayState()
  {
   int today=DateId(ServerNow());
   if(today==g_risk.dayId) return;

   g_risk.dayId=today;
   g_risk.locked=false;
   g_risk.profitLocked=false;
   g_risk.reason="None";
   g_risk.peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_risk.dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   SaveState();
  }

void UpdateRiskLock()
  {
   RefreshDayState();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>g_risk.peakEquity) g_risk.peakEquity=equity;

   double daily=DailyEAProfit();
   double reference=g_risk.dayStartBalance;
   if(reference<=0.0) reference=AccountInfoDouble(ACCOUNT_BALANCE)-daily;

   double daily_loss_pct=0.0;
   if(reference>0.0 && daily<0.0) daily_loss_pct=(-daily/reference)*100.0;
   double daily_profit_pct=0.0;
   if(reference>0.0 && daily>0.0) daily_profit_pct=(daily/reference)*100.0;

   double equity_dd_pct=0.0;
   if(g_risk.peakEquity>0.0)
      equity_dd_pct=(g_risk.peakEquity-equity)/g_risk.peakEquity*100.0;

   bool was_locked=g_risk.locked;

   if(InpMaxDailyLossPct>0.0 && daily_loss_pct>=InpMaxDailyLossPct)
     {
      g_risk.locked=true;
      g_risk.reason=StringFormat("Daily loss %.2f%%",daily_loss_pct);
     }
   if(InpMaxIntradayEquityDDPct>0.0 && equity_dd_pct>=InpMaxIntradayEquityDDPct)
     {
      g_risk.locked=true;
      g_risk.reason=StringFormat("Equity DD %.2f%%",equity_dd_pct);
     }
   if(InpMaxDailyProfitPct>0.0 && daily_profit_pct>=InpMaxDailyProfitPct)
     {
      // A profit lock stops new entries but leaves management running.
      g_risk.profitLocked=true;
     }

   if(g_risk.locked && !was_locked)
      NotifyEvent("Risk lock",g_risk.reason,true);
  }

bool IsSessionOpen()
  {
   if(InpSessionStartHour==InpSessionEndHour) return true;
   MqlDateTime dt;
   TimeToStruct(ServerNow(),dt);
   if(InpSessionStartHour<InpSessionEndHour)
      return(dt.hour>=InpSessionStartHour && dt.hour<InpSessionEndHour);
   return(dt.hour>=InpSessionStartHour || dt.hour<InpSessionEndHour);
  }

//--- Every entry passes through here. Manual panel entries skip only the
//--- automation switch, never a protective check.
bool BasicTradeGate(const int direction,const bool manual,string &reason)
  {
   reason="";
   UpdateRiskLock();

   if(g_risk.locked)                        { reason=g_risk.reason; return false; }
   if(g_risk.profitLocked)                  { reason="Daily profit target reached"; return false; }
   if(g_risk.newsBlocked)                   { reason="News window: "+g_risk.newsEvent; return false; }
   if(g_rt.pauseNewEntries)                 { reason="New entries paused"; return false; }
   if(!manual && !g_rt.autoEnabled)         { reason="Auto mode disabled"; return false; }
   if(direction>0 && !InpAllowLong)         { reason="Long entries disabled"; return false; }
   if(direction<0 && !InpAllowShort)        { reason="Short entries disabled"; return false; }
   if(ServerNow()<g_rt.nextEntryTime)       { reason="Basket cooldown"; return false; }
   if(ServerNow()-g_rt.lastEntryTime<ActiveEntryThrottleSeconds())
                                            { reason="Entry throttle"; return false; }
   if(!IsSessionOpen())                     { reason="Outside session"; return false; }
   if(HasForeignNettingPosition())          { reason="Foreign netting position"; return false; }
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)==0 ||
      MQLInfoInteger(MQL_TRADE_ALLOWED)==0 ||
      AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)==0)
                                            { reason="Trading permission off"; return false; }

   ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY)
                                            { reason="Symbol not open for trading"; return false; }
   if(direction>0 && mode==SYMBOL_TRADE_MODE_SHORTONLY)
                                            { reason="Symbol is short-only"; return false; }
   if(direction<0 && mode==SYMBOL_TRADE_MODE_LONGONLY)
                                            { reason="Symbol is long-only"; return false; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))        { reason="No market tick"; return false; }
   if(InpMaxSpreadPrice>0.0 && tick.ask-tick.bid>InpMaxSpreadPrice)
                                            { reason="Spread too wide"; return false; }

   double margin_level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(AccountInfoDouble(ACCOUNT_MARGIN)>0.0 && InpMinMarginLevelPct>0.0 &&
      margin_level<InpMinMarginLevelPct)    { reason="Margin level guard"; return false; }
   return true;
  }

bool CanAfford(const int direction,const double lots,string &reason)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
     {
      reason="No tick for margin check";
      return false;
     }
   double price=(direction>0 ? tick.ask : tick.bid);
   double margin=0.0;
   ENUM_ORDER_TYPE type=(direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcMargin(type,_Symbol,lots,price,margin))
     {
      reason=StringFormat("OrderCalcMargin error %d",GetLastError());
      return false;
     }
   double free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double remaining=free_margin-margin;
   if(remaining<0.0 || (equity>0.0 && remaining/equity*100.0<InpMinFreeMarginPct))
     {
      reason="Projected free margin guard";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| CORE - volatility, grid distance and lot progression             |
//+------------------------------------------------------------------+
bool ReadATR(double &current,double &average)
  {
   current=0.0;
   average=0.0;
   if(g_atrHandle==INVALID_HANDLE) return false;
   int required=MathMax(2,InpATRRegimeLookback+1);
   double values[];
   ArraySetAsSeries(values,true);
   int copied=CopyBuffer(g_atrHandle,0,1,required,values);
   if(copied<2) return false;
   current=values[0];
   int n=MathMin(copied-1,InpATRRegimeLookback);
   if(n<1) return false;
   for(int i=1;i<=n;i++) average+=values[i];
   average/=(double)n;
   return(current>0.0 && average>0.0);
  }

double CurrentATR()
  {
   double current=0.0,average=0.0;
   if(!ReadATR(current,average)) return 0.0;
   return current;
  }

double BaseGridDistance()
  {
   if(InpDistanceMode==GF_DISTANCE_FIXED)
      return Clamp(InpFixedDistancePrice,InpMinDistancePrice,InpMaxDistancePrice);

   double current=0.0,average=0.0;
   if(!ReadATR(current,average))
      return Clamp(InpFixedDistancePrice,InpMinDistancePrice,InpMaxDistancePrice);

   double distance=current*InpATRDistanceMultiplier;
   if(InpDistanceMode==GF_DISTANCE_AUTO_SWITCH)
     {
      double ratio=current/average;
      if(ratio<InpAutoLowRatio) distance*=InpAutoLowMultiplier;
      else if(ratio>InpAutoHighRatio) distance*=InpAutoHighMultiplier;
      else distance*=InpAutoNormalMultiplier;
     }
   return Clamp(distance,InpMinDistancePrice,InpMaxDistancePrice);
  }

//--- Spacing widens with depth so a runaway trend cannot fill the ladder at once.
double NextGridDistance()
  {
   double distance=BaseGridDistance()*ActiveDistanceFactor();
   if(g_rt.profile==GF_PROFILE_HFT)
     {
      int index=MathMax(0,MathMin(7,g_rt.gridLevel-1));
      distance*=0.75+FullFibRatio(index);
     }
   else if(g_rt.profile==GF_PROFILE_INSANE)
     {
      int index=MathMax(0,MathMin(7,g_rt.gridLevel+1));
      distance*=1.0+FullFibRatio(index);
     }
   else if(InpUseFibGridSpacing)
     {
      int spacing_index=MathMax(1,g_rt.gridLevel);
      distance*=Fibonacci(spacing_index);
     }

   double profile_min=InpMinDistancePrice;
   if(g_rt.profile==GF_PROFILE_HFT) profile_min*=0.25;
   else if(g_rt.profile==GF_PROFILE_AGGRESSIVE) profile_min*=0.50;
   else if(g_rt.profile==GF_PROFILE_INSANE) profile_min*=0.50;
   return Clamp(distance,profile_min,InpMaxDistancePrice*1.618);
  }

//--- Universal risk sizing: works in any account currency and on any tick size.
double LotsForRisk(const double risk_money,const double stop_distance)
  {
   double tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value<=0.0) tick_value=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0.0 || tick_value<=0.0 || stop_distance<=0.0 || risk_money<=0.0) return 0.0;

   double ticks=stop_distance/tick_size;
   if(ticks<=0.0) return 0.0;
   double loss_per_lot=ticks*tick_value;
   if(loss_per_lot<=0.0) return 0.0;
   return risk_money/loss_per_lot;
  }

double LevelLot(const int level)
  {
   ENUM_GF_LOT_MODE mode=ActiveLotMode();
   double raw=InpBaseLot*ActiveLotFactor();

   if(mode==GF_LOT_RISK_PERCENT)
     {
      double risk_money=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercentPerLevel/100.0;
      double stop_distance=(InpRiskStopPrice>0.0 ? InpRiskStopPrice : BaseGridDistance()*2.0);
      raw=LotsForRisk(risk_money,stop_distance)*ActiveLotFactor();
      if(raw<=0.0) raw=InpBaseLot*ActiveLotFactor();
     }
   else if(mode==GF_LOT_GEOMETRIC)
      raw*=MathPow(ActiveMartingaleMultiplier(),MathMax(0,level-1));
   else if(mode==GF_LOT_FIBONACCI)
      raw*=Fibonacci(MathMax(1,level));

   return NormalizeVolume(raw);
  }

//+------------------------------------------------------------------+
//| UI - chart drawing helpers (price/time anchored objects)         |
//+------------------------------------------------------------------+
void DrawZone(const string suffix,const datetime start_time,const double low,const double high,
              const color zone_color,const string tooltip)
  {
   if(!InpDrawStructure || start_time<=0 || low<=0.0 || high<=low) return;
   string name=g_prefix+suffix;
   int seconds=PeriodSeconds(ActiveStructureTF());
   if(seconds<=0) seconds=60;
   datetime end_time=ServerNow()+(datetime)(seconds*UI_ZONE_BARS);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,start_time,low,end_time,high);
   ObjectMove(0,name,0,start_time,low);
   ObjectMove(0,name,1,end_time,high);
   ObjectSetInteger(0,name,OBJPROP_COLOR,zone_color);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
  }

void DeleteObject(const string suffix)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
  }

void DrawLevel(const string suffix,const double price,const color line_color,const string tooltip)
  {
   if(!InpDrawStructure || price<=0.0) return;
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
  }

void DrawStructureMarker(const int direction,const int kind,const datetime when,const double price)
  {
   if(!InpDrawStructure) return;
   string event=(kind==2 ? "CHOCH" : "BOS");
   string name=g_prefix+event+"_"+IntegerToString((int)when);
   if(ObjectCreate(0,name,OBJ_ARROW,0,when,price))
     {
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,(direction>0 ? 233 : 234));
      ObjectSetInteger(0,name,OBJPROP_COLOR,(direction>0 ? THEME_GREEN : THEME_RED));
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,event+" "+DirectionText(direction));
     }
  }

void DrawFibonacciMap()
  {
   if(!InpDrawStructure || g_str.swingHigh<=g_str.swingLow) return;
   double ratios[9]={0.0,0.236,0.382,0.500,0.618,0.786,1.000,1.272,1.618};
   string labels[9]={"000","236","382","500","618","786","1000","1272","1618"};
   double range=g_str.swingHigh-g_str.swingLow;
   bool bearish=(g_str.trend<0);
   for(int i=0;i<9;i++)
     {
      double price=(bearish ? g_str.swingHigh-range*ratios[i] :
                              g_str.swingLow+range*ratios[i]);
      string name=g_prefix+"FIB_"+labels[i];
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      ObjectSetDouble(0,name,OBJPROP_PRICE,price);
      ObjectSetInteger(0,name,OBJPROP_COLOR,(i==4 || i==5 ? THEME_CYAN : THEME_VIOLET));
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,(i==4 || i==5 ? 2 : 1));
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"Fibonacci "+DoubleToString(ratios[i]*100.0,1)+"%");
     }
  }

//+------------------------------------------------------------------+
//| CORE - swing detection                                           |
//| Arrays are series indexed: a larger index is an older bar, so     |
//| "left" bars sit at index+left and "right" bars at index-right.    |
//+------------------------------------------------------------------+
bool IsPivotHigh(MqlRates &rates[],const int index,const int left,const int right)
  {
   int size=ArraySize(rates);
   if(index-right<1 || index+left>=size) return false;
   double value=rates[index].high;
   for(int i=1;i<=right;i++) if(value<=rates[index-i].high) return false;
   for(int i=1;i<=left;i++)  if(value<=rates[index+i].high) return false;
   return true;
  }

bool IsPivotLow(MqlRates &rates[],const int index,const int left,const int right)
  {
   int size=ArraySize(rates);
   if(index-right<1 || index+left>=size) return false;
   double value=rates[index].low;
   for(int i=1;i<=right;i++) if(value>=rates[index-i].low) return false;
   for(int i=1;i<=left;i++)  if(value>=rates[index+i].low) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| CORE - smart money context zones                                 |
//+------------------------------------------------------------------+
//--- Fair value gap: a three bar imbalance the market has not filled yet.
void DetectFairValueGaps(MqlRates &rates[])
  {
   g_str.bullFVGLow=0.0;
   g_str.bullFVGHigh=0.0;
   g_str.bearFVGLow=0.0;
   g_str.bearFVGHigh=0.0;
   g_str.bullFVGTime=0;
   g_str.bearFVGTime=0;
   if(!InpUseFVG) return;

   int size=ArraySize(rates);
   int scan=MathMin(size-3,60);
   for(int i=1;i<scan;i++)
     {
      // rates[i] is the middle bar; rates[i+1] is older, rates[i-1] newer.
      // A gap counts only while it is unmitigated: no later bar has traded
      // back into it, which is what makes it a level worth entering at.
      if(g_str.bullFVGLow<=0.0 && rates[i-1].low>rates[i+1].high)
        {
         double low=rates[i+1].high;
         double high=rates[i-1].low;
         bool mitigated=false;
         for(int k=i-2;k>=0 && !mitigated;k--)
            if(rates[k].low<=high) mitigated=true;
         if(!mitigated)
           {
            g_str.bullFVGLow=low;
            g_str.bullFVGHigh=high;
            g_str.bullFVGTime=rates[i].time;
           }
        }
      if(g_str.bearFVGLow<=0.0 && rates[i-1].high<rates[i+1].low)
        {
         double low=rates[i-1].high;
         double high=rates[i+1].low;
         bool mitigated=false;
         for(int k=i-2;k>=0 && !mitigated;k--)
            if(rates[k].high>=low) mitigated=true;
         if(!mitigated)
           {
            g_str.bearFVGLow=low;
            g_str.bearFVGHigh=high;
            g_str.bearFVGTime=rates[i].time;
           }
        }
      if(g_str.bullFVGLow>0.0 && g_str.bearFVGLow>0.0) break;
     }

   if(g_str.bullFVGLow>0.0)
      DrawZone("BULL_FVG",g_str.bullFVGTime,g_str.bullFVGLow,g_str.bullFVGHigh,
               THEME_ZONE_BULL_FVG,"Bullish fair value gap");
   else
      DeleteObject("BULL_FVG");
   if(g_str.bearFVGLow>0.0)
      DrawZone("BEAR_FVG",g_str.bearFVGTime,g_str.bearFVGLow,g_str.bearFVGHigh,
               THEME_ZONE_BEAR_FVG,"Bearish fair value gap");
   else
      DeleteObject("BEAR_FVG");
  }

//--- Liquidity sweep: the wick takes a swing out, the body closes back inside.
void DetectLiquiditySweep(MqlRates &rates[])
  {
   if(!InpUseLiquiditySweep) return;
   if(ArraySize(rates)<3) return;

   double buffer=MathMax(InpBreakBufferPrice*0.5,_Point);
   if(g_str.swingLow>0.0 && rates[1].low<g_str.swingLow-buffer &&
      rates[1].close>g_str.swingLow)
     {
      g_str.sweepDirection=1;                 // Sell-side liquidity taken: bullish intent.
      g_str.sweepTime=rates[1].time;
     }
   else if(g_str.swingHigh>0.0 && rates[1].high>g_str.swingHigh+buffer &&
           rates[1].close<g_str.swingHigh)
     {
      g_str.sweepDirection=-1;                // Buy-side liquidity taken: bearish intent.
      g_str.sweepTime=rates[1].time;
     }

   // A sweep is a short lived condition; expire it after a handful of bars.
   int seconds=PeriodSeconds(ActiveStructureTF());
   if(seconds<=0) seconds=60;
   if(g_str.sweepDirection!=0 && ServerNow()-g_str.sweepTime>seconds*5)
      g_str.sweepDirection=0;
  }

void DetectContextZones(MqlRates &rates[])
  {
   int size=ArraySize(rates);
   if(size<8) return;
   g_str.bullOBLow=0.0;
   g_str.bullOBHigh=0.0;
   g_str.bearOBLow=0.0;
   g_str.bearOBHigh=0.0;
   g_str.bullOBTime=0;
   g_str.bearOBTime=0;

   int scan=MathMin(size-2,60);
   for(int i=2;i<scan;i++)
     {
      // Last opposing candle before an impulse that closed beyond its range.
      if(g_str.bullOBLow<=0.0 && rates[i].close<rates[i].open &&
         rates[i-1].close>rates[i-1].open && rates[i-1].close>rates[i].high)
        {
         g_str.bullOBLow=rates[i].low;
         g_str.bullOBHigh=MathMax(rates[i].open,rates[i].close);
         g_str.bullOBTime=rates[i].time;
        }
      if(g_str.bearOBLow<=0.0 && rates[i].close>rates[i].open &&
         rates[i-1].close<rates[i-1].open && rates[i-1].close<rates[i].low)
        {
         g_str.bearOBLow=MathMin(rates[i].open,rates[i].close);
         g_str.bearOBHigh=rates[i].high;
         g_str.bearOBTime=rates[i].time;
        }
      if(g_str.bullOBLow>0.0 && g_str.bearOBLow>0.0) break;
     }

   double width=MathMax(CurrentATR()*0.25,20.0*_Point);
   if(g_str.swingLow>0.0)
     {
      g_str.demandLow=g_str.swingLow-width;
      g_str.demandHigh=g_str.swingLow+width;
      DrawZone("DEMAND",g_str.swingLowTime,g_str.demandLow,g_str.demandHigh,
               THEME_ZONE_DEMAND,"Demand zone from confirmed swing support");
     }
   if(g_str.swingHigh>0.0)
     {
      g_str.supplyLow=g_str.swingHigh-width;
      g_str.supplyHigh=g_str.swingHigh+width;
      DrawZone("SUPPLY",g_str.swingHighTime,g_str.supplyLow,g_str.supplyHigh,
               THEME_ZONE_SUPPLY,"Supply zone from confirmed swing resistance");
     }
   if(g_str.bullOBLow>0.0)
      DrawZone("BULL_OB",g_str.bullOBTime,g_str.bullOBLow,g_str.bullOBHigh,
               THEME_ZONE_BULL_OB,"Bullish order block");
   if(g_str.bearOBLow>0.0)
      DrawZone("BEAR_OB",g_str.bearOBTime,g_str.bearOBLow,g_str.bearOBHigh,
               THEME_ZONE_BEAR_OB,"Bearish order block");

   DetectFairValueGaps(rates);
   DetectLiquiditySweep(rates);
   DrawFibonacciMap();
  }

//+------------------------------------------------------------------+
//| CORE - higher timeframe confirmation                             |
//+------------------------------------------------------------------+
void UpdateHTFTrend()
  {
   g_str.htfTrend=0;
   if(!InpUseHTFConfirmation) return;
   if(g_htfFastHandle==INVALID_HANDLE || g_htfSlowHandle==INVALID_HANDLE) return;

   double fast[],slow[];
   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);
   if(CopyBuffer(g_htfFastHandle,0,1,2,fast)<2) return;
   if(CopyBuffer(g_htfSlowHandle,0,1,2,slow)<2) return;
   if(fast[0]<=0.0 || slow[0]<=0.0) return;

   if(fast[0]>slow[0]) g_str.htfTrend=1;
   else if(fast[0]<slow[0]) g_str.htfTrend=-1;
  }

bool HTFAllows(const int direction)
  {
   if(!InpUseHTFConfirmation || !InpHTFBlocksCounterTrend) return true;
   if(g_str.htfTrend==0) return true;            // No reading yet: do not block.
   return(g_str.htfTrend==direction);
  }

//--- ICT premium/discount: buy the discount half of the range, sell the premium half.
bool DiscountPremiumAllows(const int direction,const double price)
  {
   if(!InpRequireDiscountPremium) return true;
   if(g_str.swingHigh<=g_str.swingLow) return true;
   double equilibrium=(g_str.swingHigh+g_str.swingLow)/2.0;
   if(direction>0) return(price<=equilibrium);
   if(direction<0) return(price>=equilibrium);
   return true;
  }

bool IsNearZone(const double price,const double low,const double high,const double tolerance)
  {
   if(low<=0.0 || high<=low) return false;
   return(price>=low-tolerance && price<=high+tolerance);
  }

//--- One score, one explanation string: the panel shows exactly why a setup passed.
int ConfluenceScore(const int direction,const int kind,const double price,string &details)
  {
   int score=0;
   details="";
   double tolerance=MathMax(CurrentATR()*0.15,InpBreakBufferPrice*2.0);

   if(g_str.trend==direction)
     {
      score++;
      details="Trend";
     }
   if(InpUseHTFConfirmation && g_str.htfTrend==direction)
     {
      score++;
      details+=(StringLen(details)>0 ? "+HTF" : "HTF");
     }
   if(kind==3)
     {
      score++;
      details+=(StringLen(details)>0 ? "+Tick" : "Tick");
     }

   bool snr=(direction>0 ? (g_str.swingHigh>0.0 && price>=g_str.swingHigh-tolerance) :
                           (g_str.swingLow>0.0 && price<=g_str.swingLow+tolerance));
   if(snr)
     {
      score++;
      details+=(StringLen(details)>0 ? "+SNR" : "SNR");
     }

   bool ob=(direction>0 ? IsNearZone(price,g_str.bullOBLow,g_str.bullOBHigh,tolerance) :
                          IsNearZone(price,g_str.bearOBLow,g_str.bearOBHigh,tolerance));
   if(ob)
     {
      score++;
      details+=(StringLen(details)>0 ? "+OB" : "OB");
     }

   bool snd=(direction>0 ? IsNearZone(price,g_str.demandLow,g_str.demandHigh,tolerance) :
                           IsNearZone(price,g_str.supplyLow,g_str.supplyHigh,tolerance));
   if(snd)
     {
      score++;
      details+=(StringLen(details)>0 ? "+SND" : "SND");
     }

   bool fvg=(direction>0 ? IsNearZone(price,g_str.bullFVGLow,g_str.bullFVGHigh,tolerance) :
                           IsNearZone(price,g_str.bearFVGLow,g_str.bearFVGHigh,tolerance));
   if(fvg)
     {
      score++;
      details+=(StringLen(details)>0 ? "+FVG" : "FVG");
     }

   if(InpUseLiquiditySweep && g_str.sweepDirection==direction)
     {
      score++;
      details+=(StringLen(details)>0 ? "+SWEEP" : "SWEEP");
     }

   if(g_pending.usesZone && price>=g_pending.zoneLow-tolerance &&
      price<=g_pending.zoneHigh+tolerance)
     {
      score++;
      details+=(StringLen(details)>0 ? "+FIB" : "FIB");
     }

   if(MicroDomAgrees(direction))
     {
      score++;
      details+=(StringLen(details)>0 ? "+DOM" : "DOM");
     }

   if(StringLen(details)==0) details="No confluence";
   return score;
  }

//+------------------------------------------------------------------+
//| CORE - structure warm-up and BOS / CHOCH detection               |
//+------------------------------------------------------------------+
void WarmUpStructure()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int count=CopyRates(_Symbol,ActiveStructureTF(),0,InpStructureLookback,rates);
   if(count<InpPivotLeft+InpPivotRight+10)
     {
      Print("Structure warm-up postponed: history is still loading.");
      return;
     }

   g_str.swingHigh=0.0;
   g_str.swingLow=0.0;
   for(int i=InpPivotRight+1;i<count-InpPivotLeft;i++)
     {
      if(g_str.swingHigh<=0.0 && IsPivotHigh(rates,i,InpPivotLeft,InpPivotRight))
        {
         g_str.swingHigh=rates[i].high;
         g_str.swingHighTime=rates[i].time;
        }
      if(g_str.swingLow<=0.0 && IsPivotLow(rates,i,InpPivotLeft,InpPivotRight))
        {
         g_str.swingLow=rates[i].low;
         g_str.swingLowTime=rates[i].time;
        }
      if(g_str.swingHigh>0.0 && g_str.swingLow>0.0) break;
     }

   UpdateHTFTrend();
   DetectContextZones(rates);
   DrawLevel("SWING_HIGH",g_str.swingHigh,THEME_SWING_HIGH,"Confirmed swing high");
   DrawLevel("SWING_LOW",g_str.swingLow,THEME_SWING_LOW,"Confirmed swing low");
  }

bool SignalModeAccepts(const int kind)
  {
   if(kind==3) return true;                       // Micro impulses bypass the structure mode.
   if(InpSignalMode==GF_SIGNAL_BOS_AND_CHOCH) return true;
   if(InpSignalMode==GF_SIGNAL_BOS_ONLY) return(kind==1);
   return(kind==2);
  }

//--- Called once per closed structure bar. Returns true on a fresh BOS/CHOCH.
bool UpdateStructure(int &direction,int &kind,double &origin,double &extreme)
  {
   direction=0;
   kind=0;
   origin=0.0;
   extreme=0.0;

   int needed=MathMax(70,InpPivotLeft+InpPivotRight+10);
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied=CopyRates(_Symbol,ActiveStructureTF(),0,needed,rates);
   if(copied<needed) return false;

   int candidate=InpPivotRight+1;
   if(IsPivotHigh(rates,candidate,InpPivotLeft,InpPivotRight))
     {
      if(rates[candidate].time!=g_str.swingHighTime)
        {
         g_str.swingHigh=rates[candidate].high;
         g_str.swingHighTime=rates[candidate].time;
         g_str.highBroken=false;
         DrawLevel("SWING_HIGH",g_str.swingHigh,THEME_SWING_HIGH,"Confirmed swing high");
        }
     }
   if(IsPivotLow(rates,candidate,InpPivotLeft,InpPivotRight))
     {
      if(rates[candidate].time!=g_str.swingLowTime)
        {
         g_str.swingLow=rates[candidate].low;
         g_str.swingLowTime=rates[candidate].time;
         g_str.lowBroken=false;
         DrawLevel("SWING_LOW",g_str.swingLow,THEME_SWING_LOW,"Confirmed swing low");
        }
     }

   UpdateHTFTrend();
   DetectContextZones(rates);

   double current_close=rates[1].close;
   double previous_close=rates[2].close;
   bool bullish=(g_str.swingHigh>0.0 && !g_str.highBroken &&
                 previous_close<=g_str.swingHigh+InpBreakBufferPrice &&
                 current_close>g_str.swingHigh+InpBreakBufferPrice);
   bool bearish=(g_str.swingLow>0.0 && !g_str.lowBroken &&
                 previous_close>=g_str.swingLow-InpBreakBufferPrice &&
                 current_close<g_str.swingLow-InpBreakBufferPrice);

   if(bullish)
     {
      direction=1;
      kind=(g_str.trend<0 ? 2 : 1);              // A break against the trend is a CHOCH.
      origin=g_str.swingLow;
      extreme=MathMax(current_close,rates[1].high);
      g_str.trend=1;
      g_str.highBroken=true;
     }
   else if(bearish)
     {
      direction=-1;
      kind=(g_str.trend>0 ? 2 : 1);
      origin=g_str.swingHigh;
      extreme=MathMin(current_close,rates[1].low);
      g_str.trend=-1;
      g_str.lowBroken=true;
     }

   if(direction!=0)
     {
      string event=(kind==2 ? "CHOCH" : "BOS");
      g_str.lastEvent=event+" "+DirectionText(direction)+" @ "+
                      DoubleToString(current_close,_Digits);
      DrawStructureMarker(direction,kind,rates[1].time,current_close);
      NotifyEvent("Structure",g_str.lastEvent,false);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| TRADE - entries, pending retracements and the grid               |
//+------------------------------------------------------------------+
double EmergencyStopPrice(const int direction,const MqlTick &tick)
  {
   if(InpEmergencySLPrice<=0.0) return 0.0;
   double distance=MathMax(InpEmergencySLPrice,MinStopDistance()+2.0*_Point);
   double stop=(direction>0 ? tick.ask-distance : tick.bid+distance);
   return NormalizePriceToTick(stop);
  }

bool OpenLevel(const int direction,const int level,const bool manual,const string reason_tag)
  {
   string reason="";
   if(!BasicTradeGate(direction,manual,reason))
     {
      g_rt.panelStatus="Blocked: "+reason;
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double entry_price=(direction>0 ? tick.ask : tick.bid);

   // Level one is the decision point: the deeper levels are recovery orders
   // for a basket whose direction was already decided here.
   if(level==1 && !manual)
     {
      if(!HTFAllows(direction))
        {
         g_rt.panelStatus="Setup held: against the "+TrendText(g_str.htfTrend)+" HTF trend";
         return false;
        }
      if(!DiscountPremiumAllows(direction,entry_price))
        {
         g_rt.panelStatus="Setup held: wrong side of equilibrium";
         return false;
        }

      string details="";
      int score=ConfluenceScore(direction,g_pending.kind,entry_price,details);
      g_str.confluenceScore=score;
      g_str.confluenceText=details;
      bool has_market_context=(StringFind(details,"OB")>=0 ||
                               StringFind(details,"SNR")>=0 ||
                               StringFind(details,"SND")>=0 ||
                               StringFind(details,"FVG")>=0);
      if(score<ActiveRequiredConfluence() ||
         (g_rt.profile==GF_PROFILE_NORMAL && !has_market_context))
        {
         g_rt.panelStatus=StringFormat("Setup held: confluence %d/%d (%s)",
                                       score,ActiveRequiredConfluence(),details);
         return false;
        }
     }
   else if(level==1 && manual)
     {
      g_str.confluenceScore=0;
      g_str.confluenceText="Protected manual entry";
     }

   if(level>ActiveMaxGridLevels())
     {
      g_rt.panelStatus="Blocked: max grid levels";
      return false;
     }

   SBasket basket;
   BasketStats(basket);

   double lots=LevelLot(level);
   if(lots<=0.0)
     {
      g_rt.panelStatus="Blocked: lot below broker minimum";
      return false;
     }
   if(InpMaxBasketLots>0.0 && basket.lots+lots>InpMaxBasketLots+1e-10)
     {
      g_rt.panelStatus="Blocked: basket lot cap";
      return false;
     }
   if(!CanAfford(direction,lots,reason))
     {
      g_rt.panelStatus="Blocked: "+reason;
      Print("Entry blocked: ",reason);
      return false;
     }

   double sl=EmergencyStopPrice(direction,tick);
   string comment=StringFormat("GFBC L%d %s",level,reason_tag);
   ResetLastError();
   bool submitted=(direction>0 ? trade.Buy(lots,_Symbol,0.0,sl,0.0,comment) :
                                 trade.Sell(lots,_Symbol,0.0,sl,0.0,comment));
   if(!submitted || !IsTradeRetcodeSuccessful())
     {
      LogTradeFailure("Open "+DirectionText(direction));
      g_rt.panelStatus="Order rejected: "+trade.ResultRetcodeDescription();
      return false;
     }

   double filled=trade.ResultPrice();
   if(filled<=0.0) filled=entry_price;
   g_rt.gridLevel=level;
   g_rt.lastEntryPrice=filled;
   g_rt.lastEntryTime=ServerNow();
   g_rt.trailPeakProfit=0.0;
   if(g_pending.kind==3) g_micro.lastSignalTime=ServerNow();
   SaveState();

   g_pending.direction=0;
   g_pending.kind=0;
   g_pending.usesZone=false;
   g_pending.expiry=0;

   g_rt.panelStatus=StringFormat("Opened %s L%d %.2f",DirectionText(direction),level,lots);
   string detail=StringFormat("%s level %d, %.2f lots at %.*f (%s)",
                              DirectionText(direction),level,lots,_Digits,filled,reason_tag);
   NotifyEvent("Entry",detail,level==1);
   JournalWrite("ENTRY",detail,0.0);
   return true;
  }

//--- Turns a structure or micro event into either an immediate or a pending setup.
void ArmSignal(const int direction,const int kind,const double origin,const double extreme)
  {
   if(!SignalModeAccepts(kind))
     {
      g_rt.panelStatus="Structure signal filtered by mode";
      return;
     }
   if(!HTFAllows(direction))
     {
      g_rt.panelStatus="Signal dropped: against the HTF trend";
      return;
     }

   int seconds=PeriodSeconds(ActiveStructureTF());
   if(seconds<=0) seconds=60;

   if(!ActiveUsesFibRetracement() || kind==3)
     {
      g_pending.direction=direction;
      g_pending.kind=kind;
      g_pending.usesZone=false;
      g_pending.expiry=ServerNow()+(datetime)(seconds*InpFibEntryExpiryBars);
      g_rt.panelStatus=(kind==3 ? "Micro impulse armed" : "Structure entry armed");
      return;
     }

   double range=MathAbs(extreme-origin);
   if(range<=10.0*_Point)
     {
      g_rt.panelStatus="Fib signal ignored: impulse too small";
      return;
     }

   double shallow=Clamp(ActiveFibShallow(),0.0,1.0);
   double deep=Clamp(ActiveFibDeep(),0.0,1.0);
   if(shallow>deep)
     {
      double swap=shallow;
      shallow=deep;
      deep=swap;
     }

   if(direction>0)
     {
      g_pending.zoneLow=extreme-deep*range;
      g_pending.zoneHigh=extreme-shallow*range;
     }
   else
     {
      g_pending.zoneLow=extreme+shallow*range;
      g_pending.zoneHigh=extreme+deep*range;
     }

   g_pending.direction=direction;
   g_pending.kind=kind;
   g_pending.usesZone=true;
   g_pending.expiry=ServerNow()+(datetime)(seconds*InpFibEntryExpiryBars);
   g_rt.panelStatus=StringFormat("Waiting Fib %.2f - %.2f",g_pending.zoneLow,g_pending.zoneHigh);
  }

void ClearPendingSetup(const string status)
  {
   g_pending.direction=0;
   g_pending.kind=0;
   g_pending.usesZone=false;
   g_pending.zoneLow=0.0;
   g_pending.zoneHigh=0.0;
   g_pending.expiry=0;
   if(StringLen(status)>0) g_rt.panelStatus=status;
  }

void ProcessPendingEntry()
  {
   if(g_pending.direction==0 || BasketPositions()>0) return;
   if(ServerNow()>g_pending.expiry)
     {
      ClearPendingSetup("Setup expired; scanning again");
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double price=(g_pending.direction>0 ? tick.ask : tick.bid);
   if(!g_pending.usesZone || (price>=g_pending.zoneLow && price<=g_pending.zoneHigh))
     {
      string tag=(g_pending.kind==3 ? "HFT" : (g_pending.kind==2 ? "CHOCH" : "BOS"));
      if(g_pending.usesZone) tag+="-FIB";
      OpenLevel(g_pending.direction,1,false,tag);
     }
  }

//--- Recovery ladder: one order per adverse step, never more than the cap.
void ProcessGrid()
  {
   SBasket basket;
   BasketStats(basket);
   if(basket.positions<=0 || basket.direction==0) return;
   if(g_rt.gridLevel<=0) RecoverGridState();
   if(g_rt.gridLevel>=ActiveMaxGridLevels()) return;
   if(g_rt.lastEntryPrice<=0.0) g_rt.lastEntryPrice=basket.weightedOpen;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double distance=NextGridDistance();
   bool adverse=(basket.direction>0 ? tick.bid<=g_rt.lastEntryPrice-distance :
                                      tick.ask>=g_rt.lastEntryPrice+distance);
   if(adverse)
      OpenLevel(basket.direction,g_rt.gridLevel+1,false,"GRID");
  }

//+------------------------------------------------------------------+
//| TRADE - per-position protection (break-even, trail, partial)     |
//+------------------------------------------------------------------+
//--- Guarded modify: respects the stops level and never sends a no-op request.
bool ModifyStop(const ulong ticket,const double new_sl,const double take_profit)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double current_sl=PositionGetDouble(POSITION_SL);
   if(!LevelsDiffer(new_sl,current_sl)) return false;

   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double distance=MinStopDistance();
   if(type==POSITION_TYPE_BUY && new_sl>tick.bid-distance) return false;
   if(type==POSITION_TYPE_SELL && new_sl<tick.ask+distance) return false;

   ResetLastError();
   if(!trade.PositionModify(ticket,new_sl,take_profit) || !IsTradeRetcodeSuccessful())
     {
      LogTradeFailure("Modify stop on ticket "+(string)ticket);
      return false;
     }
   return true;
  }

void ApplyBreakEven(const ulong ticket,const ENUM_POSITION_TYPE type,const double open_price,
                    const MqlTick &tick)
  {
   if(!InpUseBreakEven || InpBreakEvenTriggerPrice<=0.0) return;
   double profit_price=(type==POSITION_TYPE_BUY ? tick.bid-open_price : open_price-tick.ask);
   if(profit_price<InpBreakEvenTriggerPrice) return;

   double target=(type==POSITION_TYPE_BUY ? open_price+InpBreakEvenOffsetPrice :
                                            open_price-InpBreakEvenOffsetPrice);
   target=NormalizePriceToTick(target);
   double current_sl=PositionGetDouble(POSITION_SL);

   // Only ever tighten: a break-even move must not loosen an existing stop.
   if(type==POSITION_TYPE_BUY && current_sl>0.0 && target<=current_sl) return;
   if(type==POSITION_TYPE_SELL && current_sl>0.0 && target>=current_sl) return;
   if(ModifyStop(ticket,target,PositionGetDouble(POSITION_TP)))
      JournalWrite("BREAKEVEN",StringFormat("ticket %I64u stop at %.*f",ticket,_Digits,target),0.0);
  }

void ApplyTrailingStop(const ulong ticket,const ENUM_POSITION_TYPE type,const double open_price,
                       const MqlTick &tick)
  {
   if(!InpUseTrailingStop || InpTrailATRMultiplier<=0.0) return;
   double atr=CurrentATR();
   if(atr<=0.0) return;
   double trail=atr*InpTrailATRMultiplier;
   double step=MathMax(InpTrailStepPrice,_Point);
   double current_sl=PositionGetDouble(POSITION_SL);

   if(type==POSITION_TYPE_BUY)
     {
      if(tick.bid-open_price<trail) return;                 // Never trail while under water.
      double candidate=NormalizePriceToTick(tick.bid-trail);
      if(current_sl>0.0 && candidate<current_sl+step) return;
      if(current_sl<=0.0 && candidate<open_price) return;
      ModifyStop(ticket,candidate,PositionGetDouble(POSITION_TP));
     }
   else
     {
      if(open_price-tick.ask<trail) return;
      double candidate=NormalizePriceToTick(tick.ask+trail);
      if(current_sl>0.0 && candidate>current_sl-step) return;
      if(current_sl<=0.0 && candidate>open_price) return;
      ModifyStop(ticket,candidate,PositionGetDouble(POSITION_TP));
     }
  }

void ApplyPartialClose(const ulong ticket,const ENUM_POSITION_TYPE type,const double open_price,
                       const double volume,const MqlTick &tick)
  {
   if(!InpUsePartialClose || InpPartialTriggerPrice<=0.0) return;
   if(TicketFlagged(ticket)) return;

   double profit_price=(type==POSITION_TYPE_BUY ? tick.bid-open_price : open_price-tick.ask);
   if(profit_price<InpPartialTriggerPrice) return;

   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double min_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(step<=0.0) step=min_lot;
   if(step<=0.0) return;

   double percent=Clamp(InpPartialClosePercent,1.0,99.0);
   double close_volume=MathFloor((volume*percent/100.0+1e-12)/step)*step;
   close_volume=NormalizeDouble(close_volume,VolumeDigits(step));
   // Both the closed slice and the remainder must be tradable volumes.
   if(close_volume<min_lot-1e-12 || volume-close_volume<min_lot-1e-12)
     {
      FlagTicket(ticket);                                   // Too small to split: never retry.
      return;
     }

   ResetLastError();
   if(trade.PositionClosePartial(ticket,close_volume,(ulong)InpDeviationPoints) &&
      IsTradeRetcodeSuccessful())
     {
      FlagTicket(ticket);
      string detail=StringFormat("ticket %I64u closed %.2f of %.2f lots",ticket,close_volume,volume);
      NotifyEvent("Partial close",detail,false);
      JournalWrite("PARTIAL",detail,0.0);
     }
   else
      LogTradeFailure("Partial close on ticket "+(string)ticket);
  }

//--- One pass over our own positions; each helper decides on its own whether to act.
void ManagePositions()
  {
   if(!InpUseBreakEven && !InpUseTrailingStop && !InpUsePartialClose) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      if(!SelectOurPositionAt(i,ticket)) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open_price=PositionGetDouble(POSITION_PRICE_OPEN);
      double volume=PositionGetDouble(POSITION_VOLUME);

      ApplyPartialClose(ticket,type,open_price,volume,tick);
      if(!PositionSelectByTicket(ticket)) continue;         // A partial close may have removed it.
      ApplyBreakEven(ticket,type,open_price,tick);
      if(!PositionSelectByTicket(ticket)) continue;
      ApplyTrailingStop(ticket,type,open_price,tick);
     }
  }

//+------------------------------------------------------------------+
//| TRADE - basket exits                                             |
//+------------------------------------------------------------------+
bool CloseBasket(const string reason)
  {
   SBasket before;
   BasketStats(before);
   if(before.positions<=0) return false;

   bool all_ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      if(!SelectOurPositionAt(i,ticket)) continue;
      ResetLastError();
      if(!trade.PositionClose(ticket,(ulong)InpDeviationPoints) || !IsTradeRetcodeSuccessful())
        {
         LogTradeFailure("Close basket ticket "+(string)ticket);
         all_ok=false;
        }
     }

   g_rt.panelStatus="Close: "+reason;
   g_rt.nextEntryTime=ServerNow()+(datetime)ActiveCooldownSeconds();

   string detail=StringFormat("%s | %d position(s), %.2f lots, P/L %.2f",
                              reason,before.positions,before.lots,before.profit);
   NotifyEvent("Basket closed",detail,true);
   JournalWrite("BASKET_CLOSE",reason,before.profit);
   RegisterBasketResult(before.profit);

   // Reset as soon as every close was accepted: the positions may still be
   // disappearing server-side, and OnTradeTransaction uses a standing grid
   // level to tell an outside flatten from this one.
   if(all_ok || BasketPositions()==0)
     {
      ResetGridState();
      ClearPendingSetup("");
     }
   return all_ok;
  }

//--- Returns true when the basket was closed on this pass.
bool ManageBasket()
  {
   SBasket basket;
   BasketStats(basket);
   if(basket.positions<=0)
     {
      if(g_rt.gridLevel!=0) ResetGridState();
      return false;
     }

   double target=ActiveTargetMoney();
   double hard_stop=ActiveStopMoney();
   if(hard_stop>0.0 && basket.profit<=-hard_stop)
      return CloseBasket("basket hard stop");
   if(target>0.0 && basket.profit>=target)
      return CloseBasket("basket target");

   if(InpUseBasketProfitTrail)
     {
      double trail_start=ActiveTrailStartMoney();
      double giveback=ActiveTrailGivebackMoney();
      if(trail_start>0.0 && basket.profit>=trail_start)
        {
         if(basket.profit>g_rt.trailPeakProfit) g_rt.trailPeakProfit=basket.profit;
         if(giveback>0.0 && g_rt.trailPeakProfit-basket.profit>=giveback)
            return CloseBasket("basket profit trail");
        }
     }

   int max_minutes=ActiveMaxBasketMinutes();
   if(max_minutes>0 && basket.firstOpen>0 &&
      ServerNow()-basket.firstOpen>=max_minutes*60)
     {
      // A time stop only fires in profit or at a small loss; a deep basket
      // keeps its recovery ladder rather than being crystallised by the clock.
      if(basket.profit>=0.0 || g_rt.gridLevel>=ActiveMaxGridLevels())
         return CloseBasket(StringFormat("basket time stop (%d min)",max_minutes));
     }

   if(InpNewsClosesBasket && g_risk.newsBlocked && basket.profit>=0.0)
      return CloseBasket("news window: "+g_risk.newsEvent);

   return false;
  }

//+------------------------------------------------------------------+
//| UI - dashboard factories (screen anchored objects)               |
//+------------------------------------------------------------------+
bool PanelEnabled()
  {
   return(InpShowPanel && MQLInfoInteger(MQL_OPTIMIZATION)==0);
  }

void UiPlace(const string name,const int x,const int y)
  {
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,InpPanelX+x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,InpPanelY+y);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void UiRect(const string suffix,const int x,const int y,const int width,const int height,
            const color background,const color border)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   UiPlace(name,x,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
  }

void UiLabel(const string suffix,const string text,const int x,const int y,
             const int size,const color text_color,const string font)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   UiPlace(name,x,y);
   ObjectSetString(0,name,OBJPROP_FONT,font);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void UiButton(const string suffix,const string text,const int x,const int y,
              const int width,const color background,const string tooltip)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   UiPlace(name,x,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,UI_BTN_H);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,THEME_BORDER);
   ObjectSetInteger(0,name,OBJPROP_COLOR,THEME_TEXT);
   ObjectSetString(0,name,OBJPROP_FONT,UI_FONT_BOLD);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,UI_FONT_SIZE);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
  }

void SetPanelText(const string suffix,const string text,const color text_color)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
  }

void SetButtonState(const string suffix,const string text,const color background)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
  }

int PanelRowY(const int row)
  {
   return UI_ROW_TOP+row*UI_ROW_H;
  }

void CreatePanel()
  {
   if(!PanelEnabled()) return;

   UiRect("PANEL_BG",0,0,UI_PANEL_W,UI_PANEL_H,THEME_BG,THEME_BORDER);
   UiRect("PANEL_HEAD",0,0,UI_PANEL_W,32,THEME_SURFACE,THEME_BORDER);
   UiRect("PULSE",UI_PANEL_W-UI_PAD-10,11,10,10,THEME_CYAN,THEME_CYAN);

   UiLabel("TITLE","GOLD STRUCTURE GRID v3.00",UI_PAD,9,UI_FONT_SIZE_TITLE,THEME_GOLD,UI_FONT_BOLD);
   for(int row=0;row<9;row++)
      UiLabel("L"+IntegerToString(row+1),"",UI_PAD,PanelRowY(row),UI_FONT_SIZE,THEME_TEXT,UI_FONT);

   int profile_y=PanelRowY(9)+6;
   UiButton("BTN_P0","NORM",UI_PAD,profile_y,UI_BTN_W_QUARTER,THEME_IDLE,"Normal structure profile");
   UiButton("BTN_P1","HFT",UI_PAD+80,profile_y,UI_BTN_W_QUARTER,THEME_IDLE,"HFT-style micro scalp profile");
   UiButton("BTN_P2","AGGR",UI_PAD+160,profile_y,UI_BTN_W_QUARTER,THEME_IDLE,"Aggressive profile");
   UiButton("BTN_P3","INSN",UI_PAD+240,profile_y,UI_BTN_W_QUARTER,THEME_IDLE,"Insane sniper profile");

   int control_y=profile_y+34;
   UiButton("BTN_AUTO","AUTO",UI_PAD,control_y,UI_BTN_W_HALF,THEME_GREEN,
            "Enable or disable automated entries");
   UiButton("BTN_PAUSE","PAUSE",UI_PAD+160,control_y,UI_BTN_W_HALF,THEME_IDLE,
            "Pause all new entries while management continues");

   int trade_y=control_y+34;
   UiButton("BTN_BUY","BUY",UI_PAD,trade_y,UI_BTN_W_HALF,THEME_GREEN,
            "Open a protected manual buy basket");
   UiButton("BTN_SELL","SELL",UI_PAD+160,trade_y,UI_BTN_W_HALF,THEME_RED,
            "Open a protected manual sell basket");

   int close_y=trade_y+34;
   UiButton("BTN_CLOSE","CLOSE BASKET",UI_PAD,close_y,UI_BTN_W_FULL,THEME_AMBER,
            "Close only this EA's symbol and magic-number positions");

   UiLabel("FOOTER","",UI_PAD,close_y+32,UI_FONT_SIZE,THEME_MUTED,UI_FONT);
   ChartRedraw();
  }

//--- A slow blink proves the EA is alive even when nothing is trading.
void UpdatePulse()
  {
   static bool bright=false;
   bright=!bright;
   color tone=THEME_CYAN;
   if(g_risk.locked) tone=THEME_RED;
   else if(g_risk.newsBlocked || g_rt.pauseNewEntries || g_risk.profitLocked) tone=THEME_AMBER;
   else if(!g_rt.autoEnabled) tone=THEME_IDLE;
   string name=g_prefix+"PULSE";
   if(ObjectFind(0,name)<0) return;
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(bright ? tone : THEME_SURFACE_2));
   ObjectSetInteger(0,name,OBJPROP_COLOR,tone);
  }

void UpdateProfileButtons()
  {
   string suffixes[4]={"BTN_P0","BTN_P1","BTN_P2","BTN_P3"};
   string labels[4]={"NORM","HFT","AGGR","INSN"};
   for(int i=0;i<4;i++)
     {
      bool active=((int)g_rt.profile==i);
      color background=THEME_IDLE;
      if(active) background=(i==3 ? THEME_RED : (i==2 ? THEME_AMBER : THEME_CYAN));
      else if(!InpAllowDashboardProfileSwitch) background=THEME_SURFACE_2;
      SetButtonState(suffixes[i],labels[i],background);
     }
  }

void UpdatePanel()
  {
   if(!PanelEnabled()) return;
   if(ObjectFind(0,g_prefix+"PANEL_BG")<0) CreatePanel();

   SBasket basket;
   BasketStats(basket);
   double atr=CurrentATR();
   double daily=DailyEAProfit();
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   color status_color=THEME_GREEN;
   if(g_risk.locked) status_color=THEME_RED;
   else if(g_risk.newsBlocked || g_risk.profitLocked || g_rt.pauseNewEntries) status_color=THEME_AMBER;

   SetPanelText("L1",StringFormat("%s | %s | %s | spread %.2f",
                _Symbol,ProfileText(g_rt.profile),
                EnumToString(ActiveStructureTF()),tick.ask-tick.bid),THEME_CYAN);
   SetPanelText("L2",StringFormat("Structure: %s | %s",TrendText(g_str.trend),g_str.lastEvent),
                THEME_MUTED);
   SetPanelText("L3",StringFormat("HTF %s | Confluence %d/%d (%s)",
                TrendText(g_str.htfTrend),g_str.confluenceScore,ActiveRequiredConfluence(),
                g_str.confluenceText),THEME_MUTED);
   SetPanelText("L4",StringFormat("Basket: %s | L%d/%d | %.2f lots",
                DirectionText(basket.direction),g_rt.gridLevel,ActiveMaxGridLevels(),basket.lots),
                THEME_TEXT);
   SetPanelText("L5",StringFormat("P/L %.2f | Daily %.2f | Next dist %.2f",
                basket.profit,daily,NextGridDistance()),
                (basket.profit>=0.0 ? THEME_GREEN : THEME_RED));
   SetPanelText("L6",StringFormat("ATR %.2f | Weighted entry %.*f",atr,_Digits,basket.weightedOpen),
                THEME_MUTED);
   SetPanelText("L7",StringFormat("DOM %s | Impulse %.2f | %.1f ticks/s",
                (g_micro.domValid ? DoubleToString(g_micro.domImbalance,2) : "n/a"),
                g_micro.impulse,g_micro.ticksPerSecond),
                (g_micro.domValid ? THEME_CYAN : THEME_MUTED));
   SetPanelText("L8",StringFormat("Session: %d baskets | %.0f%% win | PF %.2f | last %.2f",
                g_stats.baskets,SessionWinRate(),SessionProfitFactor(),g_stats.lastBasketProfit),
                THEME_MUTED);

   string status=g_rt.panelStatus;
   if(g_risk.locked) status="LOCKED - "+g_risk.reason;
   else if(g_risk.newsBlocked) status="NEWS - "+g_risk.newsEvent;
   else if(g_risk.profitLocked) status="Daily profit target reached";
   SetPanelText("L9","Status: "+status,status_color);

   SetButtonState("BTN_AUTO",(g_rt.autoEnabled ? "AUTO ON" : "AUTO OFF"),
                  (g_rt.autoEnabled ? THEME_GREEN : THEME_IDLE));
   SetButtonState("BTN_PAUSE",(g_rt.pauseNewEntries ? "RESUME" : "PAUSE"),
                  (g_rt.pauseNewEntries ? THEME_AMBER : THEME_IDLE));
   SetPanelText("FOOTER",StringFormat("Magic %I64u | %s account | equity %.2f",
                InpMagic,(IsHedgingAccount() ? "hedging" : "netting"),
                AccountInfoDouble(ACCOUNT_EQUITY)),THEME_MUTED);

   UpdateProfileButtons();
   UpdatePulse();
   ChartRedraw();
  }

void ReleaseButton(const string suffix)
  {
   string name=g_prefix+suffix;
   if(ObjectFind(0,name)>=0) ObjectSetInteger(0,name,OBJPROP_STATE,false);
  }

//+------------------------------------------------------------------+
//| CORE - indicator handles and profile switching                   |
//+------------------------------------------------------------------+
void ReleaseHandles()
  {
   if(g_atrHandle!=INVALID_HANDLE)     { IndicatorRelease(g_atrHandle);     g_atrHandle=INVALID_HANDLE; }
   if(g_htfFastHandle!=INVALID_HANDLE) { IndicatorRelease(g_htfFastHandle); g_htfFastHandle=INVALID_HANDLE; }
   if(g_htfSlowHandle!=INVALID_HANDLE) { IndicatorRelease(g_htfSlowHandle); g_htfSlowHandle=INVALID_HANDLE; }
  }

//--- Handles follow the active profile, so switching profiles rebuilds them.
bool CreateHandles()
  {
   ReleaseHandles();
   g_atrHandle=iATR(_Symbol,ActiveATRTF(),ActiveATRPeriod());
   if(g_atrHandle==INVALID_HANDLE)
     {
      PrintFormat("Unable to create the ATR handle. Error %d",GetLastError());
      return false;
     }

   if(InpUseHTFConfirmation)
     {
      g_htfFastHandle=iMA(_Symbol,InpHTFTimeframe,InpHTFFastMA,0,MODE_EMA,PRICE_CLOSE);
      g_htfSlowHandle=iMA(_Symbol,InpHTFTimeframe,InpHTFSlowMA,0,MODE_EMA,PRICE_CLOSE);
      if(g_htfFastHandle==INVALID_HANDLE || g_htfSlowHandle==INVALID_HANDLE)
        {
         PrintFormat("Unable to create the higher timeframe handles. Error %d",GetLastError());
         return false;
        }
     }
   return true;
  }

void ApplyProfile(const ENUM_GF_PROFILE profile,const bool announce)
  {
   if(g_rt.profile==profile) return;
   g_rt.profile=profile;

   if(!CreateHandles())
      g_rt.panelStatus="Profile switch failed: indicator handles";
   else
     {
      g_rt.gridLevel=MathMin(g_rt.gridLevel,ActiveMaxGridLevels());
      g_rt.lastStructureBar=0;                  // Force a structure re-read on the new timeframe.
      WarmUpStructure();
      SaveState();
      g_rt.panelStatus="Profile: "+ProfileText(profile);
     }
   if(announce)
      NotifyEvent("Profile",ProfileText(profile)+" engaged",false);
  }

//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpMagic==0 || InpPivotLeft<1 || InpPivotRight<1 ||
      InpStructureLookback<50 || InpMaxGridLevels<1 || InpMaxGridLevels>12 ||
      InpBaseLot<=0.0 || InpMartingaleMultiplier<1.0 ||
      InpMinDistancePrice<=0.0 || InpMaxDistancePrice<InpMinDistancePrice ||
      InpATRPeriod<2 || InpATRRegimeLookback<2 ||
      InpSessionStartHour<0 || InpSessionStartHour>23 ||
      InpSessionEndHour<0 || InpSessionEndHour>23)
     {
      Print("Invalid input parameters. Check pivots, levels, lots, distances, ATR, magic, and session hours.");
      return false;
     }
   if(InpHTFFastMA<2 || InpHTFSlowMA<=InpHTFFastMA)
     {
      Print("Invalid higher timeframe periods: the slow EMA must be longer than the fast EMA.");
      return false;
     }
   if(InpPartialClosePercent<=0.0 || InpPartialClosePercent>=100.0)
     {
      Print("Invalid partial close percent: use a value between 1 and 99.");
      return false;
     }
   if(InpNewsMinutesBefore<0 || InpNewsMinutesAfter<0)
     {
      Print("Invalid news window: minutes cannot be negative.");
      return false;
     }
   if(InpHFTTickWindow<3)
     {
      Print("Invalid tick window: at least 3 ticks are needed for a micro impulse.");
      return false;
     }
   if(InpMaxLotPerOrder<=0.0 || InpBaseLot>InpMaxLotPerOrder)
     {
      Print("Invalid lot caps: the per-order cap must be positive and at least the base lot.");
      return false;
     }
   if(InpMaxBasketLots>0.0 && InpMaxBasketLots<InpMaxLotPerOrder)
     {
      Print("Invalid lot caps: the basket cap must not be smaller than the per-order cap.");
      return false;
     }
   return true;
  }

int OnInit()
  {
   if(InpRequireGoldSymbol && !IsGoldSymbol())
     {
      Print("Attach this EA to an XAU or GOLD symbol, or disable InpRequireGoldSymbol.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_prefix="GFBC_"+(string)InpMagic+"_";
   string account=(string)AccountInfoInteger(ACCOUNT_LOGIN);
   g_stateFile=StringFormat("GFBC_%s_%s_%I64u.bin",account,_Symbol,InpMagic);
   g_journalFile=StringFormat("GFBC_%s_%s_%I64u.csv",account,_Symbol,InpMagic);

   // STATE is seeded from CONFIG once; everything at runtime reads STATE.
   g_rt.profile=InpTradingProfile;
   g_rt.autoEnabled=true;
   g_rt.pauseNewEntries=false;
   g_rt.panelStatus="Initializing";
   g_rt.gridLevel=0;
   g_rt.lastEntryPrice=0.0;
   g_rt.trailPeakProfit=0.0;
   g_rt.lastEntryTime=0;
   g_rt.nextEntryTime=0;
   g_str.lastEvent="Scanning market structure";
   g_str.confluenceText="No setup";
   g_risk.reason="None";
   g_stats.bestBasket=0.0;
   g_stats.worstBasket=0.0;
   ClearPendingSetup("");
   ClearTicketFlags();
   ArrayInitialize(g_micro.mid,0.0);
   g_micro.head=GF_TICK_BUFFER-1;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
      Print("Warning: could not set the symbol filling mode. Error ",GetLastError());

   if(!CreateHandles())
      return INIT_FAILED;

   // Restore the day counters before the first risk evaluation.
   g_risk.dayId=DateId(ServerNow());
   g_risk.peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_risk.dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   SPersistState saved;
   if(LoadState(saved) && saved.dayId==g_risk.dayId)
     {
      g_risk.peakEquity=MathMax(saved.peakEquity,g_risk.peakEquity);
      if(saved.dayStartBalance>0.0) g_risk.dayStartBalance=saved.dayStartBalance;
     }

   ParseNewsCurrencies();
   WarmUpStructure();
   g_rt.lastStructureBar=iTime(_Symbol,ActiveStructureTF(),0);
   RecoverGridState();
   MicroSubscribe();
   CreatePanel();
   EventSetTimer(1);
   g_rt.panelStatus="Ready";
   UpdatePanel();

   if(!IsHedgingAccount())
      Print("NOTICE: netting account detected. Grid levels are tracked in a state file, not per ticket.");
   if(InpUseTelegram)
      Print("NOTICE: allow https://api.telegram.org in Tools > Options > Expert Advisors for Telegram messages.");
   PrintFormat("XAUUSD GridFib BOS/CHOCH v3.00 initialized on %s, profile %s.",
               _Symbol,ProfileText(g_rt.profile));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   SaveState();
   if(g_stats.baskets>0)
      JournalWrite("SESSION",StringFormat("%d baskets, %.0f%% win, PF %.2f, best %.2f, worst %.2f",
                   g_stats.baskets,SessionWinRate(),SessionProfitFactor(),
                   g_stats.bestBasket,g_stats.worstBasket),
                   g_stats.grossProfit-g_stats.grossLoss);
   EventKillTimer();
   MicroRelease();
   ReleaseHandles();
   ObjectsDeleteAll(0,g_prefix);
   ChartRedraw();
  }

void OnTick()
  {
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick))
      MicroPushTick(tick);

   UpdateRiskLock();
   if(g_risk.locked && BasketPositions()>0)
     {
      CloseBasket("account risk lock");
      return;
     }

   ManagePositions();
   if(ManageBasket()) return;

   datetime bar=iTime(_Symbol,ActiveStructureTF(),0);
   if(bar>0 && bar!=g_rt.lastStructureBar)
     {
      g_rt.lastStructureBar=bar;
      int direction=0,kind=0;
      double origin=0.0,extreme=0.0;
      if(UpdateStructure(direction,kind,origin,extreme))
        {
         int basket_direction=BasketDirection();
         if(basket_direction!=0 && basket_direction!=direction && InpCloseOnOppositeStructure)
            CloseBasket("opposite structure");
         if(BasketPositions()==0)
            ArmSignal(direction,kind,origin,extreme);
        }
     }

   // Micro impulses only arm a setup when nothing else is queued.
   if(BasketPositions()==0 && g_pending.direction==0)
     {
      int micro_direction=MicroSignal();
      if(micro_direction!=0)
         ArmSignal(micro_direction,3,0.0,0.0);
     }

   ProcessPendingEntry();
   ProcessGrid();
  }

void OnTimer()
  {
   UpdateRiskLock();
   RefreshNewsWindow();
   FlushNotifications();

   // Depth of market may only become available after the symbol warms up.
   static int retry_counter=0;
   if(InpUseHFTDepthOfMarket && !g_micro.bookSubscribed)
     {
      retry_counter++;
      if(retry_counter>=60)
        {
         retry_counter=0;
         MicroSubscribe();
        }
     }

   UpdatePanel();
  }

//--- Fired by the terminal on every depth-of-market change.
void OnBookEvent(const string &symbol)
  {
   if(symbol!=_Symbol) return;
   MicroReadBook();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   if(sparam==g_prefix+"BTN_AUTO")
     {
      g_rt.autoEnabled=!g_rt.autoEnabled;
      g_rt.panelStatus=(g_rt.autoEnabled ? "Automatic entries enabled" : "Automatic entries disabled");
      ReleaseButton("BTN_AUTO");
     }
   else if(sparam==g_prefix+"BTN_PAUSE")
     {
      g_rt.pauseNewEntries=!g_rt.pauseNewEntries;
      g_rt.panelStatus=(g_rt.pauseNewEntries ? "New entries paused" : "New entries resumed");
      ReleaseButton("BTN_PAUSE");
     }
   else if(sparam==g_prefix+"BTN_BUY")
     {
      if(BasketPositions()==0) OpenLevel(1,1,true,"PANEL");
      else g_rt.panelStatus="Manual buy blocked: basket exists";
      ReleaseButton("BTN_BUY");
     }
   else if(sparam==g_prefix+"BTN_SELL")
     {
      if(BasketPositions()==0) OpenLevel(-1,1,true,"PANEL");
      else g_rt.panelStatus="Manual sell blocked: basket exists";
      ReleaseButton("BTN_SELL");
     }
   else if(sparam==g_prefix+"BTN_CLOSE")
     {
      CloseBasket("panel command");
      ReleaseButton("BTN_CLOSE");
     }
   else if(StringFind(sparam,g_prefix+"BTN_P")==0)
     {
      string suffix=StringSubstr(sparam,StringLen(g_prefix+"BTN_P"));
      int index=(int)StringToInteger(suffix);
      if(!InpAllowDashboardProfileSwitch)
         g_rt.panelStatus="Profile switching is disabled in the inputs";
      else if(index>=0 && index<=3)
         ApplyProfile((ENUM_GF_PROFILE)index,true);
      ReleaseButton("BTN_P"+IntegerToString(index));
     }
   UpdatePanel();
  }

//--- Catches closes the EA did not request: broker stops, manual flattening.
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;

   InvalidateDailyProfitCache();

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) return;

   // Exit deals produced by the server can carry magic 0, so a stripped magic is
   // only accepted for the flatten check below, never for the journal.
   ulong magic=(ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   bool ours=(magic==InpMagic);
   bool maybe_ours=(ours || magic==0);
   if(!maybe_ours) return;

   double money=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+
                HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)+
                HistoryDealGetDouble(trans.deal,DEAL_FEE);
   long reason=HistoryDealGetInteger(trans.deal,DEAL_REASON);
   string reason_text="close";
   if(reason==DEAL_REASON_SL) reason_text="stop loss";
   else if(reason==DEAL_REASON_TP) reason_text="take profit";
   else if(reason==DEAL_REASON_SO) reason_text="stop out";
   if(ours) JournalWrite("DEAL_OUT",reason_text,money);

   // g_rt.gridLevel is cleared by CloseBasket, so a level still standing here
   // means the flatten came from outside the EA.
   if(g_rt.gridLevel>0 && BasketPositions()==0)
     {
      RegisterBasketResult(money);
      NotifyEvent("Basket flattened",StringFormat("%s, P/L %.2f",reason_text,money),true);
      g_rt.nextEntryTime=ServerNow()+(datetime)ActiveCooldownSeconds();
      ResetGridState();
      ClearPendingSetup("Basket closed externally");
     }
  }

//--- Optimization criterion: reward profit factor and depth, punish drawdown.
double OnTester()
  {
   double profit=TesterStatistics(STAT_PROFIT);
   double trades=TesterStatistics(STAT_TRADES);
   double factor=TesterStatistics(STAT_PROFIT_FACTOR);
   double drawdown=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(trades<10 || profit<=0.0) return 0.0;
   if(factor<=0.0) factor=0.01;
   double score=profit*MathMin(factor,5.0)*MathSqrt(trades);
   return score/(1.0+drawdown);
  }
//+------------------------------------------------------------------+
