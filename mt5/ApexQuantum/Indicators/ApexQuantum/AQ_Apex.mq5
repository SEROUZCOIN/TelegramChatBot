//+------------------------------------------------------------------+
//|                                                       AQ_Apex.mq5|
//|          APEX QUANTUM — Supply/Demand · Structure · Confluence   |
//|                                                                  |
//|  One engine built from four classic studies, rewritten in native |
//|  MQL5 and made to agree with each other:                         |
//|                                                                  |
//|    Shved Supply & Demand   -> graded S/D zones (AQ_Zones.mqh)    |
//|    Perfect Trend Line      -> dual trend rails (AQ_Structure)    |
//|    SHI Channel             -> premium/discount rails (AQ_Channel)|
//|    ZigZag on Parabolic     -> swings, BOS/CHoCH, Fibonacci       |
//|                                                                  |
//|  Plus: fair value gaps, higher-timeframe confirmation, a         |
//|  confluence score, non-repainting entry arrows, and an animated  |
//|  clickable dashboard. Timeframe-agnostic: every window is        |
//|  derived from the chart period, so M1 through MN1 all work.      |
//+------------------------------------------------------------------+
#property copyright "APEX QUANTUM"
#property version   "1.00"
#property description "Supply & Demand zones, trend rails, market structure (BOS/CHoCH),"
#property description "fair value gaps, channel, MTF confluence score and signal arrows,"
#property description "driven from an animated clickable dashboard. Works on all timeframes."

#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots   6

//--- plot 1: buy arrow
#property indicator_label1  "AQ Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrSpringGreen
#property indicator_width1  2
//--- plot 2: sell arrow
#property indicator_label2  "AQ Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_width2  2
//--- plot 3: trend rail while bullish
#property indicator_label3  "AQ Rail Up"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSpringGreen
#property indicator_width3  2
//--- plot 4: trend rail while bearish
#property indicator_label4  "AQ Rail Down"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrCrimson
#property indicator_width4  2
//--- plot 5: fast rail, coloured by trend
#property indicator_label5  "AQ Fast Rail"
#property indicator_type5   DRAW_COLOR_LINE
#property indicator_color5  clrDodgerBlue,clrOrchid
#property indicator_style5  STYLE_DOT
#property indicator_width5  1
//--- plot 6: swing zigzag
#property indicator_label6  "AQ Swing"
#property indicator_type6   DRAW_ZIGZAG
#property indicator_color6  clrGold
#property indicator_width6  1

#include "AQ_Core.mqh"
#include "AQ_Zones.mqh"
#include "AQ_Structure.mqh"
#include "AQ_Channel.mqh"
#include "AQ_Signal.mqh"
#include "AQ_Dashboard.mqh"

//+------------------------------------------------------------------+
//| CONFIG                                                           |
//|                                                                  |
//| The first block is the iCustom contract consumed by the EA:      |
//| its order and types must not change without updating the EA.     |
//+------------------------------------------------------------------+
input group "=== ENGINE CORE (iCustom contract - fixed order) ==="
input int                  InpLookback      = 600;            // Bars analysed
input double               InpFractalFast   = 3.0;            // Minor fractal factor
input double               InpFractalSlow   = 6.0;            // Major fractal factor
input double               InpZoneFuzz      = 0.75;           // Zone thickness (ATR factor)
input bool                 InpZoneMerge     = true;           // Merge overlapping zones
input bool                 InpZoneExtend    = true;           // Pad zone by the fuzz distance
input int                  InpFastLen       = 3;              // Trend rail: fast length
input int                  InpSlowLen       = 7;              // Trend rail: slow length
input double               InpSarStep       = 0.02;           // Swing engine: SAR step
input double               InpSarMax        = 0.20;           // Swing engine: SAR maximum
input int                  InpAtrPeriod     = 14;             // ATR period
input bool                 InpUseMtf        = true;           // Higher timeframe confirmation
input ENUM_TIMEFRAMES      InpMtf1          = PERIOD_CURRENT; // HTF 1 (CURRENT = auto x4)
input ENUM_TIMEFRAMES      InpMtf2          = PERIOD_CURRENT; // HTF 2 (CURRENT = auto x16)
input ENUM_AQ_SIGNAL_MODE  InpSigMode       = AQ_SIG_BOTH;    // Entry model
input int                  InpMinScore      = 55;             // Minimum confluence score
input int                  InpCooldownBars  = 3;              // Bars between signals
input bool                 InpConfirmCandle = true;           // Require a confirming candle

input group "=== ZONES ==="
input bool             InpShowZones     = true;           // Show supply/demand zones
input bool             InpZoneWeak      = false;          // Show weak zones
input bool             InpZoneFresh     = true;           // Show untested zones
input bool             InpZoneBroken    = true;           // Show flipped zones
input int              InpZoneMax       = 14;             // Max zones drawn
input bool             InpZoneSolid     = true;           // Fill zones
input int              InpZoneWidth     = 1;              // Zone border width
input ENUM_LINE_STYLE  InpZoneStyle     = STYLE_SOLID;    // Zone border style
input bool             InpZoneLabels    = true;           // Zone captions

input group "=== STRUCTURE & OVERLAYS ==="
input bool InpShowTrend   = true;                         // Show trend rails
input bool InpShowSwing   = true;                         // Show swings / BOS / CHoCH
input bool InpShowChannel = true;                         // Show channel
input bool InpShowFvg     = true;                         // Show fair value gaps
input bool InpShowFib     = true;                         // Show Fibonacci of the live leg
input int  InpMaxFvg      = 6;                            // Max imbalance boxes
input int  InpMaxBreaks   = 8;                            // Max BOS/CHoCH markers
input int  InpChanFractal = 0;                            // Channel fractal bars (0 = auto)
input int  InpChanWidth   = 2;                            // Channel line width

input group "=== SIGNALS & ALERTS ==="
input bool InpShowArrows   = true;                        // Show entry arrows
input bool InpAlerts       = false;                       // Enable alerts
input bool InpAlertPopup   = true;                        // Popup alert
input bool InpAlertSound   = true;                        // Sound alert
input bool InpAlertPush    = false;                       // Push notification
input bool InpAlertZone    = false;                       // Alert on zone entry too
input int  InpAlertSeconds = 300;                         // Minimum seconds between alerts
input string InpAlertWav   = "alert.wav";                 // Alert sound file

input group "=== DASHBOARD ==="
input bool           InpShowPanel = true;                 // Show dashboard
input ENUM_AQ_CORNER InpPanelCorner = AQ_CORNER_TL;       // Dashboard corner
input int            InpPanelX    = 12;                   // Dashboard offset X
input int            InpPanelY    = 22;                   // Dashboard offset Y
input bool           InpAnimate   = true;                 // Enable animations
input int            InpFrameMs   = 90;                   // Animation frame (ms)

//--- exported buffer map (also the EA's contract)
#define AQ_BUF_BUY        0
#define AQ_BUF_SELL       1
#define AQ_BUF_RAIL_UP    2
#define AQ_BUF_RAIL_DN    3
#define AQ_BUF_FAST       4
#define AQ_BUF_FAST_CLR   5
#define AQ_BUF_ZZ_HI      6
#define AQ_BUF_ZZ_LO      7
#define AQ_BUF_SIGNAL     8
#define AQ_BUF_SCORE      9
#define AQ_BUF_TREND     10
#define AQ_BUF_DEM_TOP   11
#define AQ_BUF_DEM_BOT   12
#define AQ_BUF_SUP_TOP   13
#define AQ_BUF_SUP_BOT   14
#define AQ_BUF_SLOW      15
#define AQ_BUF_EVENT     16
#define AQ_BUF_ATR       17

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
double BufBuy[],    BufSell[];
double BufRailUp[], BufRailDn[];
double BufFast[],   BufFastClr[];
double BufZzHi[],   BufZzLo[];
double BufSignal[], BufScore[],  BufTrend[];
double BufDemTop[], BufDemBot[], BufSupTop[], BufSupBot[];
double BufSlow[],   BufEvent[],  BufAtr[];

struct AQAppState
  {
   datetime          lastBar;         // last bar the heavy pass ran on
   int               lastEvalBar;     // last bar scored for signals
   int               lastDir;         // direction of the last emitted signal
   datetime          lastSignalTime;
   bool              forceRecalc;     // set by the RESCAN button
   bool              engineOk;        // all sub-engines produced data
   ulong             lastAlertMs;     // monotonic alert throttle
   int               liveScore;
   //--- validated working copies of the numeric inputs. Inputs are runtime
   //--- constants and an optimiser pass (or a hand-edited .set) can hand us a
   //--- zero or a negative, so nothing downstream ever reads the raw Inp* value.
   int               lookback;
   int               fastLen, slowLen;
   int               atrPeriod;
   int               minScore;
   ulong             alertMs;
  };
AQAppState g_st;

CAQZones     g_zones;
CAQStructure g_struct;
CAQChannel   g_chan;
CAQSignal    g_sig;
CAQDashboard g_dash;

//--- higher timeframe trend caches
ENUM_TIMEFRAMES g_tf1 = PERIOD_H1, g_tf2 = PERIOD_H4;
double          g_mtf1[], g_mtf2[];

//+------------------------------------------------------------------+
//| CORE — ATR (Wilder), incremental                                 |
//+------------------------------------------------------------------+
void AQ_CalcAtr(const int total, const int start, const int periodIn,
                const double &high[], const double &low[], const double &close[], double &atr[])
  {
   int period = (periodIn < 1) ? 1 : periodIn;
   int bars   = (int)MathMin(total, ArraySize(high));
   for(int i = (start < 0 ? 0 : start); i < bars; i++)
     {
      if(i == 0) { atr[0] = high[0] - low[0]; continue; }
      double tr = MathMax(high[i] - low[i],
                          MathMax(MathAbs(high[i] - close[i - 1]), MathAbs(low[i] - close[i - 1])));
      atr[i] = (i < period) ? (atr[i - 1] * i + tr) / (i + 1)          // warm-up: running mean
                            : (atr[i - 1] * (period - 1) + tr) / period; // Wilder smoothing
     }
  }

//+------------------------------------------------------------------+
//| CORE — higher timeframe trend, computed with the same recurrence |
//| as the chart rails so the vote means exactly what it looks like  |
//+------------------------------------------------------------------+
bool AQ_BuildMtfTrend(const ENUM_TIMEFRAMES tf, const int bars, double &trendOut[])
  {
   double h[], l[], c[];
   int n = CopyHigh(_Symbol, tf, 0, bars, h);
   if(n < 20) return(false);
   if(CopyLow (_Symbol, tf, 0, bars, l) != n) return(false);
   if(CopyClose(_Symbol, tf, 0, bars, c) != n) return(false);

   double fast[], slow[], up[], dn[], col[];
   ArrayResize(fast, n); ArrayResize(slow, n); ArrayResize(up, n);
   ArrayResize(dn,   n); ArrayResize(col,  n); ArrayResize(trendOut, n);
   AQ_CalcTrendLines(n, 0, g_st.fastLen, g_st.slowLen, h, l, c, fast, slow, trendOut, up, dn, col);
   return(true);
  }

//--- trend of 'tf' at the chart bar that closed at time t (no look-ahead)
int AQ_MtfAt(const ENUM_TIMEFRAMES tf, const double &trendArr[], const datetime t)
  {
   int n = ArraySize(trendArr);
   if(n <= 0) return(0);
   int shift = iBarShift(_Symbol, tf, t, false);
   if(shift < 0) return(0);
   int idx = n - 1 - shift;
   if(idx < 0 || idx >= n) return(0);
   return(trendArr[idx] > 0.0 ? 1 : -1);
  }

//+------------------------------------------------------------------+
//| CORE — score and (optionally) emit a signal for one closed bar   |
//+------------------------------------------------------------------+
int AQ_ScoreBar(const int i, const bool live, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[], int &scoreOut)
  {
   AQSigCtx c;
   c.bar       = i;
   c.open      = open[i];
   c.high      = high[i];
   c.low       = low[i];
   c.close     = close[i];
   c.atr       = BufAtr[i];
   c.fast      = BufFast[i];
   c.slow      = BufSlow[i];
   c.trend     = (int)BufTrend[i];
   c.trendPrev = (int)BufTrend[i - 1];
   c.event     = (int)BufEvent[i];
   c.structDir = g_struct.DirAt(i);
   c.fvgSide   = g_struct.FvgAt(i, close[i]);

   int grade = -1;
   c.zoneSide  = g_zones.Context(close[i], i, c.atr * 0.15, grade);
   c.zoneGrade = grade;

   double lo = 0.0, hi = 0.0;
   if(g_struct.LegAt(i, lo, hi)) { c.legLo = lo; c.legHi = hi; }
   else                          { c.legLo = 0.0; c.legHi = 0.0; }

   c.mtf1 = InpUseMtf ? AQ_MtfAt(g_tf1, g_mtf1, time[i]) : 0;
   c.mtf2 = InpUseMtf ? AQ_MtfAt(g_tf2, g_mtf2, time[i]) : 0;

   //--- the channel is a present-time construct: it votes only while the bar is
   //--- the live tail, never when back-filling history (that would be look-ahead)
   if(live)
     {
      c.chanPos   = g_chan.Position();
      c.chanSlope = g_chan.Slope();
     }
   else
     {
      c.chanPos   = -1.0;
      c.chanSlope = 0;
     }

   return(g_sig.Evaluate(c, scoreOut));
  }

//+------------------------------------------------------------------+
//| CORE — walk every not-yet-scored closed bar                      |
//+------------------------------------------------------------------+
void AQ_EvaluateSignals(const int total, const datetime &time[], const double &open[],
                        const double &high[], const double &low[], const double &close[])
  {
   int last = total - 2;                                     // last CLOSED bar
   if(last < 10) return;

   bool firstPass = (g_st.lastEvalBar < 0);
   int  from      = firstPass ? (int)MathMax(10, total - 1 - g_st.lookback) : g_st.lastEvalBar + 1;
   if(from > last) return;

   for(int i = from; i <= last; i++)
     {
      int score = 0;
      bool live = (!firstPass && i == last);
      int  dir  = AQ_ScoreBar(i, live, time, open, high, low, close, score);

      BufScore[i]  = (double)score;
      BufSignal[i] = (double)dir;
      BufBuy[i]    = EMPTY_VALUE;
      BufSell[i]   = EMPTY_VALUE;

      double off = BufAtr[i] * AQ_ARROW_ATR_OFF;
      if(dir > 0)      BufBuy[i]  = low[i]  - off;
      else if(dir < 0) BufSell[i] = high[i] + off;

      if(dir != 0)
        {
         g_st.lastDir        = dir;
         g_st.lastSignalTime = time[i];
        }
     }
   g_st.lastEvalBar = last;
  }

//+------------------------------------------------------------------+
//| CORE — heavy pass: everything that only changes on a new bar     |
//+------------------------------------------------------------------+
void AQ_HeavyPass(const int total, const datetime &time[], const double &high[],
                  const double &low[], const double &close[])
  {
   g_st.engineOk = true;

   //--- swing structure first: zones and signals both lean on it
   if(!g_struct.CalcZigZag(total, time, high, low, BufZzHi, BufZzLo))
      g_st.engineOk = false;
   else
     {
      g_struct.CalcBreaks(total, time, close, BufEvent);
      g_struct.CalcFvg(total, time, high, low);
     }

   if(!g_zones.Calculate(total, time, high, low, close, BufAtr))
      g_st.engineOk = false;

   g_chan.Calculate(total, high, low, close);

   //--- higher timeframe rails, rebuilt once per bar
   if(InpUseMtf)
     {
      long span  = (long)g_st.lookback * (long)PeriodSeconds();
      long need1 = span / (long)MathMax(1, PeriodSeconds(g_tf1));
      long need2 = span / (long)MathMax(1, PeriodSeconds(g_tf2));
      AQ_BuildMtfTrend(g_tf1, (int)AQ_Clamp(need1, (long)120, (long)5000), g_mtf1);
      AQ_BuildMtfTrend(g_tf2, (int)AQ_Clamp(need2, (long)120, (long)5000), g_mtf2);
     }
  }

//+------------------------------------------------------------------+
//| UI — plot visibility follows the dashboard toggles               |
//+------------------------------------------------------------------+
void AQ_ApplyPlotVisibility(void)
  {
   bool arrows = g_dash.Enabled(AQ_MOD_ARROW);
   bool rails  = g_dash.Enabled(AQ_MOD_TREND);
   bool swing  = g_dash.Enabled(AQ_MOD_ZZ);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, arrows ? DRAW_ARROW      : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, arrows ? DRAW_ARROW      : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, rails  ? DRAW_LINE       : DRAW_NONE);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, rails  ? DRAW_LINE       : DRAW_NONE);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, rails  ? DRAW_COLOR_LINE : DRAW_NONE);
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, swing  ? DRAW_ZIGZAG     : DRAW_NONE);
  }

//--- object modules: draw what is enabled, erase what is not
void AQ_RenderModules(const int total, const datetime &time[])
  {
   if(g_dash.Enabled(AQ_MOD_ZONES)) g_zones.Render(total, time);
   else                             g_zones.Erase();

   if(g_dash.Enabled(AQ_MOD_CHAN))  g_chan.Render(total, time);
   else                             g_chan.Erase();

   if(g_dash.Enabled(AQ_MOD_FVG))   g_struct.RenderFvg(total, time);
   else                             g_struct.EraseFvg();

   if(g_dash.Enabled(AQ_MOD_ZZ))  { g_struct.RenderBreaks(); g_struct.RenderFib(); }
   else                           { g_struct.EraseBreaks();  g_struct.EraseFib();  }

   AQ_ApplyPlotVisibility();
  }

//--- redraw the object modules outside OnCalculate (button clicks). The copied
//--- time array is bar-aligned with the OnCalculate arrays, so stored bar
//--- indices stay valid; if history is not fully loaded we settle for the plots.
void AQ_RenderNow(void)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   if(total < 80) return;
   datetime t[];
   ArraySetAsSeries(t, false);
   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, total, t) == total)
      AQ_RenderModules(total, t);
  }

//+------------------------------------------------------------------+
//| UI — publish the live state to the panel and the export buffers  |
//+------------------------------------------------------------------+
void AQ_PublishState(const int total, const datetime &time[], const double &close[])
  {
   int i = total - 1;
   double price = close[i];

   AQZone dem, sup;
   ZeroMemory(dem); ZeroMemory(sup);
   bool hasDem = g_zones.Nearest(AQ_ZONE_DEMAND, price, dem);
   bool hasSup = g_zones.Nearest(AQ_ZONE_SUPPLY, price, sup);

   BufDemTop[i] = hasDem ? dem.hi : 0.0;
   BufDemBot[i] = hasDem ? dem.lo : 0.0;
   BufSupTop[i] = hasSup ? sup.hi : 0.0;
   BufSupBot[i] = hasSup ? sup.lo : 0.0;

   if(!InpShowPanel || !g_dash.Created()) return;

   AQDashData d;
   d.symbol      = _Symbol;
   d.tf          = AQ_TfName((ENUM_TIMEFRAMES)Period());
   d.score       = g_st.liveScore;
   d.bias        = (d.score >= g_st.minScore) ? 1 : (d.score <= -g_st.minScore) ? -1 : 0;
   d.trend       = (int)BufTrend[i];
   d.structDir   = g_struct.Direction();
   d.eventName   = g_struct.EventName(g_struct.LastEvent());
   d.chanSlope   = g_chan.Slope();
   d.chanPos     = g_chan.Position();
   d.mtf1        = InpUseMtf ? AQ_MtfAt(g_tf1, g_mtf1, time[i]) : 0;
   d.mtf2        = InpUseMtf ? AQ_MtfAt(g_tf2, g_mtf2, time[i]) : 0;
   d.mtf1Name    = AQ_TfName(g_tf1);
   d.mtf2Name    = AQ_TfName(g_tf2);
   d.hasDemand   = hasDem;
   d.hasSupply   = hasSup;
   d.demTop      = hasDem ? dem.hi : 0.0;
   d.demBot      = hasDem ? dem.lo : 0.0;
   d.supTop      = hasSup ? sup.hi : 0.0;
   d.supBot      = hasSup ? sup.lo : 0.0;
   d.demGrade    = hasDem ? ("x" + (string)dem.hits) : "";
   d.supGrade    = hasSup ? ("x" + (string)sup.hits) : "";
   d.zoneCount   = g_zones.Count();
   d.atrPts      = AQ_ToPoints(_Symbol, BufAtr[i]);
   d.spreadPts   = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   d.session     = AQ_SessionName();
   d.lastSignal  = g_st.lastDir;
   d.lastSignalAt= (g_st.lastSignalTime > 0) ? TimeToString(g_st.lastSignalTime, TIME_DATE | TIME_MINUTES) : "";
   d.engineOk    = g_st.engineOk;

   g_dash.Update(d);
  }

//+------------------------------------------------------------------+
//| UI — alerts (throttled on the monotonic clock, never on ticks)   |
//+------------------------------------------------------------------+
void AQ_Notify(const string text)
  {
   ulong now = GetTickCount64();
   if(g_st.lastAlertMs != 0 && now - g_st.lastAlertMs < g_st.alertMs) return;
   g_st.lastAlertMs = now;

   if(InpAlertPopup) Alert(text);
   if(InpAlertSound) PlaySound(InpAlertWav);
   if(InpAlertPush)  SendNotification(text);
   PrintFormat("APEX QUANTUM: %s", text);
  }

void AQ_CheckAlerts(const int total, const double &close[])
  {
   if(!g_dash.Enabled(AQ_MOD_ALERT)) return;

   string head = _Symbol + " " + AQ_TfName((ENUM_TIMEFRAMES)Period()) + ": ";

   //--- a signal that has just been confirmed on the last closed bar
   static datetime alerted = 0;
   int last = total - 2;
   if(last > 0 && BufSignal[last] != 0.0 && g_st.lastSignalTime != alerted)
     {
      alerted = g_st.lastSignalTime;
      AQ_Notify(head + (BufSignal[last] > 0 ? "BUY" : "SELL") +
                " signal, score " + (string)(int)BufScore[last]);
      return;
     }

   //--- price stepping into a graded zone
   if(InpAlertZone)
     {
      int grade = -1;
      int side  = g_zones.Context(close[total - 1], total - 1, 0.0, grade);
      if(side != 0 && grade >= AQ_GRADE_TESTED)
         AQ_Notify(head + (side > 0 ? "price entered a DEMAND zone" : "price entered a SUPPLY zone"));
     }
  }

//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   AQ_InitPrefix("A");

   SetIndexBuffer(AQ_BUF_BUY,      BufBuy,     INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_SELL,     BufSell,    INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_RAIL_UP,  BufRailUp,  INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_RAIL_DN,  BufRailDn,  INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_FAST,     BufFast,    INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_FAST_CLR, BufFastClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(AQ_BUF_ZZ_HI,    BufZzHi,    INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_ZZ_LO,    BufZzLo,    INDICATOR_DATA);
   SetIndexBuffer(AQ_BUF_SIGNAL,   BufSignal,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_SCORE,    BufScore,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_TREND,    BufTrend,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_DEM_TOP,  BufDemTop,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_DEM_BOT,  BufDemBot,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_SUP_TOP,  BufSupTop,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_SUP_BOT,  BufSupBot,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_SLOW,     BufSlow,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_EVENT,    BufEvent,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(AQ_BUF_ATR,      BufAtr,     INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT,  0);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  0);
   for(int p = 0; p < 5; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, 0.0);            // zigzag gaps are zeros

   //--- runtime colours keep the plots inside the THEME library
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, AQ_CLR_BULL);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, AQ_CLR_BEAR);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0, AQ_CLR_BULL);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, AQ_CLR_BEAR);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 0, AQ_CLR_NEON);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, 1, AQ_CLR_WARN);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, 0, AQ_CLR_GOLD);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   //--- validate every numeric input once; everything downstream reads these
   g_st.lookback  = AQ_Clamp(InpLookback,     60, 20000);
   g_st.fastLen   = AQ_Clamp(InpFastLen,       1,  1000);
   g_st.slowLen   = AQ_Clamp(InpSlowLen,       1,  2000);
   g_st.atrPeriod = AQ_Clamp(InpAtrPeriod,     1,  1000);
   g_st.minScore  = AQ_Clamp(InpMinScore,      1,   100);
   g_st.alertMs   = (ulong)AQ_Clamp(InpAlertSeconds, 0, 86400) * 1000;
   if(g_st.slowLen <= g_st.fastLen) g_st.slowLen = g_st.fastLen + 1;   // the rails must differ
   if(InpLookback != g_st.lookback || InpFastLen != g_st.fastLen ||
      InpSlowLen  != g_st.slowLen  || InpAtrPeriod != g_st.atrPeriod ||
      InpMinScore != g_st.minScore)
      PrintFormat("APEX QUANTUM: inputs clamped to lookback=%d fast=%d slow=%d atr=%d score=%d",
                  g_st.lookback, g_st.fastLen, g_st.slowLen, g_st.atrPeriod, g_st.minScore);

   //--- the label reports what the engine actually runs with, not what was typed
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("APEX QUANTUM (%d,%.1f/%.1f,%d)",
                                   g_st.lookback, InpFractalFast, InpFractalSlow, g_st.minScore));

   //--- higher timeframes: PERIOD_CURRENT means "pick them for me"
   g_tf1 = (InpMtf1 == PERIOD_CURRENT) ? AQ_HigherTf((ENUM_TIMEFRAMES)Period(), 1) : InpMtf1;
   g_tf2 = (InpMtf2 == PERIOD_CURRENT) ? AQ_HigherTf((ENUM_TIMEFRAMES)Period(), 2) : InpMtf2;

   //--- sub-engines
   AQZoneCfg zc;
   zc.lookback   = g_st.lookback;
   zc.fastFactor = AQ_Clamp(InpFractalFast, 0.5, 50.0);
   zc.slowFactor = AQ_Clamp(InpFractalSlow, 0.5, 100.0);
   zc.fuzz       = AQ_Clamp(InpZoneFuzz,   0.05, 10.0);
   zc.merge      = InpZoneMerge;
   zc.extend     = InpZoneExtend;
   zc.showWeak   = InpZoneWeak;
   zc.showFresh  = InpZoneFresh;
   zc.showBroken = InpZoneBroken;
   zc.maxDraw    = AQ_Clamp(InpZoneMax,   1, 200);
   zc.solid      = InpZoneSolid;
   zc.lineWidth  = AQ_Clamp(InpZoneWidth, 1, 5);
   zc.style      = InpZoneStyle;
   zc.labels     = InpZoneLabels;
   g_zones.Configure(zc);

   AQStructCfg sc;
   sc.lookback   = g_st.lookback;
   sc.sarStep    = AQ_Clamp(InpSarStep, 0.001, 0.5);
   sc.sarMax     = AQ_Clamp(InpSarMax,  0.01,  1.0);
   sc.showFib    = InpShowFib;
   sc.maxFvg     = AQ_Clamp(InpMaxFvg,    0, 100);
   sc.maxBreaks  = AQ_Clamp(InpMaxBreaks, 0, 100);
   if(!g_struct.Init(sc)) return(INIT_FAILED);

   AQChanCfg cc;
   cc.lookback    = g_st.lookback;
   cc.fractalBars = AQ_Clamp(InpChanFractal, 0, 500);
   cc.width       = AQ_Clamp(InpChanWidth,   1, 5);
   g_chan.Configure(cc);

   AQSigCfg gc;
   gc.mode          = InpSigMode;
   gc.minScore      = g_st.minScore;
   gc.cooldownBars  = AQ_Clamp(InpCooldownBars, 0, 5000);
   gc.confirmCandle = InpConfirmCandle;
   g_sig.Configure(gc);
   g_sig.Reset();

   //--- dashboard: inputs seed the runtime state, the state owns it afterwards
   g_dash.Configure((int)InpPanelCorner, InpPanelX, InpPanelY);
   g_dash.SetEnabled(AQ_MOD_ZONES, InpShowZones);
   g_dash.SetEnabled(AQ_MOD_TREND, InpShowTrend);
   g_dash.SetEnabled(AQ_MOD_CHAN,  InpShowChannel);
   g_dash.SetEnabled(AQ_MOD_ZZ,    InpShowSwing);
   g_dash.SetEnabled(AQ_MOD_FVG,   InpShowFvg);
   g_dash.SetEnabled(AQ_MOD_ARROW, InpShowArrows);
   g_dash.SetEnabled(AQ_MOD_ALERT, InpAlerts);
   if(InpShowPanel && !MQLInfoInteger(MQL_OPTIMIZATION)) g_dash.Create();
   AQ_ApplyPlotVisibility();

   //--- remaining state
   g_st.lastBar        = 0;
   g_st.lastEvalBar    = -1;
   g_st.lastDir        = 0;
   g_st.lastSignalTime = 0;
   g_st.forceRecalc    = false;
   g_st.engineOk       = false;
   g_st.lastAlertMs    = 0;
   g_st.liveScore      = 0;

   if(InpAnimate && InpShowPanel && !MQLInfoInteger(MQL_OPTIMIZATION))
      EventSetMillisecondTimer((int)MathMax(30, InpFrameMs));

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_struct.Release();
   AQ_DeleteAll();
   ChartRedraw(0);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 80) return(0);
   if(rates_total < prev_calculated) return(0);

   //--- one indexing convention for the whole system: 0 = oldest
   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(BufBuy,     EMPTY_VALUE);
      ArrayInitialize(BufSell,    EMPTY_VALUE);
      ArrayInitialize(BufRailUp,  EMPTY_VALUE);
      ArrayInitialize(BufRailDn,  EMPTY_VALUE);
      ArrayInitialize(BufFast,    EMPTY_VALUE);
      ArrayInitialize(BufZzHi,    0.0);
      ArrayInitialize(BufZzLo,    0.0);
      ArrayInitialize(BufSignal,  0.0);
      ArrayInitialize(BufScore,   0.0);
      ArrayInitialize(BufEvent,   0.0);
      ArrayInitialize(BufDemTop,  0.0);
      ArrayInitialize(BufDemBot,  0.0);
      ArrayInitialize(BufSupTop,  0.0);
      ArrayInitialize(BufSupBot,  0.0);
      g_st.lastEvalBar = -1;
      g_st.lastBar     = 0;
      g_sig.Reset();
      start = 0;
     }
   else
      start = prev_calculated - 1;                           // re-touch the forming bar

   //--- 1. per-bar series (cheap, every tick)
   AQ_CalcAtr(rates_total, start, g_st.atrPeriod, high, low, close, BufAtr);
   AQ_CalcTrendLines(rates_total, start, g_st.fastLen, g_st.slowLen, high, low, close,
                     BufFast, BufSlow, BufTrend, BufRailUp, BufRailDn, BufFastClr);

   //--- 2. heavy pass, only on a new bar (or when forced)
   bool newBar = (time[rates_total - 1] != g_st.lastBar);
   if(newBar || g_st.forceRecalc || prev_calculated == 0)
     {
      g_st.lastBar     = time[rates_total - 1];
      g_st.forceRecalc = false;
      AQ_HeavyPass(rates_total, time, high, low, close);
      //--- never score a bar while a sub-engine is still warming up: lastEvalBar
      //--- stays put, so those bars are evaluated properly once data is ready
      if(g_st.engineOk) AQ_EvaluateSignals(rates_total, time, open, high, low, close);
      if(!MQLInfoInteger(MQL_OPTIMIZATION))
        {
         AQ_RenderModules(rates_total, time);
         ChartRedraw(0);
        }
     }

   //--- 3. live score for the forming bar (display only — it never draws an arrow)
   if(g_st.engineOk && rates_total > 12)
     {
      AQSigCtx probe;
      int i = rates_total - 1;
      probe.bar = i; probe.open = open[i]; probe.high = high[i]; probe.low = low[i];
      probe.close = close[i]; probe.atr = BufAtr[i];
      probe.fast = BufFast[i]; probe.slow = BufSlow[i];
      probe.trend = (int)BufTrend[i]; probe.trendPrev = (int)BufTrend[i - 1];
      probe.event = (int)BufEvent[i];
      probe.structDir = g_struct.Direction();
      probe.fvgSide = g_struct.FvgAt(i, close[i]);
      int grade = -1;
      probe.zoneSide = g_zones.Context(close[i], i, BufAtr[i] * 0.15, grade);
      probe.zoneGrade = grade;
      probe.legLo = g_struct.LegLow();
      probe.legHi = g_struct.LegHigh();
      probe.mtf1 = InpUseMtf ? AQ_MtfAt(g_tf1, g_mtf1, time[i]) : 0;
      probe.mtf2 = InpUseMtf ? AQ_MtfAt(g_tf2, g_mtf2, time[i]) : 0;
      probe.chanPos = g_chan.Position();
      probe.chanSlope = g_chan.Slope();
      g_st.liveScore = g_sig.Score(probe);
      BufScore[i] = (double)g_st.liveScore;
     }

   //--- 4. publish + alerts
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
     {
      AQ_PublishState(rates_total, time, close);
      if(!InpAnimate) ChartRedraw(0);       // no animation frame to repaint for us
     }
   AQ_CheckAlerts(rates_total, close);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Animation tick                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(InpAnimate && InpShowPanel) g_dash.Animate();
  }

//+------------------------------------------------------------------+
//| Dashboard interaction                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      //--- CHART_CHANGE also fires on every scroll and zoom; only an actual
      //--- resize moves the panel's origin, so only that rebuilds it
      static int lastW = 0, lastH = 0;
      int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if((w != lastW || h != lastH) && InpShowPanel && g_dash.Created())
        {
         lastW = w; lastH = h;
         g_dash.Rebuild();
        }
      return;
     }

   if(id != CHARTEVENT_OBJECT_CLICK) return;

   int param = 0;
   int act   = g_dash.OnClick(sparam, param);
   if(act == AQ_ACT_NONE) return;

   switch(act)
     {
      case AQ_ACT_TOGGLE:
         //--- switching a module off is instant; switching one back on redraws
         //--- straight away (works with no ticks arriving, e.g. at the weekend)
         if(!g_dash.Enabled(AQ_MOD_ZONES)) g_zones.Erase();
         if(!g_dash.Enabled(AQ_MOD_CHAN))  g_chan.Erase();
         if(!g_dash.Enabled(AQ_MOD_FVG))   g_struct.EraseFvg();
         if(!g_dash.Enabled(AQ_MOD_ZZ))  { g_struct.EraseBreaks(); g_struct.EraseFib(); }
         AQ_ApplyPlotVisibility();
         AQ_RenderNow();
         break;

      case AQ_ACT_TF:
         ChartSetSymbolPeriod(0, _Symbol, (ENUM_TIMEFRAMES)param);
         return;                                             // the chart reloads the indicator

      case AQ_ACT_RESCAN:
         //--- rebuild every engine from scratch on the next calculation
         g_st.forceRecalc = true;
         g_st.lastEvalBar = -1;
         g_st.lastBar     = 0;
         g_sig.Reset();
         break;
     }
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
