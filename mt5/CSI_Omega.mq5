//+------------------------------------------------------------------+
//|                                                    CSI_Omega.mq5 |
//|   CSI-Omega - candle-scored leg strength and reversal model      |
//+------------------------------------------------------------------+
//
// What this is
// ------------
// A formalisation of the "CSI" method: every candle inside a swing leg is
// awarded a pre-assigned score (not counted as one unit), those scores
// accumulate into a leg total (CNS), the leg total is resolved into three
// normalised sub-scores (CS, SP, NP), the sub-scores collapse into a single
// 0..100 leg strength (CSI), and two consecutive opposing legs are fused
// (CD) into a Continuation or Reversal verdict anchored at a reference
// price (RP).
//
//      Candle pattern -> Vi -> CNSn -> CS,SP,NP -> CSI -> CD
//                     -> Continuation / Reversal -> RP -> reset
//
// The full derivation, the calibration against the reference charts, and the
// two places where the source material was under-specified are documented in
// docs/CSI-MODEL.md. Read that before changing any default below.
//
// Repainting
// ----------
// A leg is scored only once its terminating swing has been confirmed by an
// ATR-scaled retracement. Confirmation lags the actual pivot by design; once
// written, a value is never revised. The live (still forming) leg is shown in
// the panel only, never in a buffer.
//
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property strict
#property description "CSI-Omega: per-candle scoring -> leg score (CNS) -> CS/SP/NP -> CSI -> two-leg fusion (CD) -> Continuation / Reversal"

#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   2
#property indicator_minimum 0
#property indicator_maximum 100

#property indicator_label1  "CSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'255,199,0'
#property indicator_width1  2

#property indicator_label2  "CD"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  C'0,212,255'
#property indicator_width2  2

//--- verdict codes, also written to a buffer for iCustom consumers
#define VERDICT_NONE          0
#define VERDICT_NEUTRAL       1
#define VERDICT_CONT_UP       2
#define VERDICT_CONT_DOWN     3
#define VERDICT_REVERSAL_UP   4
#define VERDICT_REVERSAL_DOWN 5

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Leg detection ==="
input int    InpAtrPeriod         = 14;    // ATR period for the swing threshold
input double InpDevMultiplier     = 2.0;   // Swing confirmed after N x ATR retrace
input int    InpMaxBars           = 5000;  // Bars to calculate (0 = all)

input group "=== Candle value (Vi) ==="
input double InpBodyMarubozu      = 0.80;  // Body/range >= this is a marubozu
input double InpBodyStrong        = 0.60;  // Body/range >= this is a strong body
input double InpBodyStandard      = 0.40;  // Body/range >= this is a standard body
input double InpBodyWeak          = 0.20;  // Body/range >= this is a weak body
input double InpScoreMarubozu     = 4.0;   // Score: marubozu
input double InpScoreStrong       = 3.0;   // Score: strong body
input double InpScoreStandard     = 2.0;   // Score: standard body
input double InpScoreWeak         = 1.0;   // Score: weak body
input double InpWickThreshold     = 0.50;  // Wick/range for a rejection candle
input double InpWickBonus         = 1.0;   // Bonus for a with-trend rejection wick
input bool   InpCounterNegative   = true;  // Counter-direction candles score negative

input group "=== Sub-scores (CS / SP / NP) ==="
input double InpCsAlpha           = 3.0;   // CS sigmoid gain
input double InpCsMu              = 0.0;   // CS sigmoid midpoint (net score per bar)
input double InpSpReference       = 0.60;  // Efficiency ratio that scores SP = 100
input double InpNpAtrSpan         = 8.0;   // Leg displacement in ATR for NP saturation

input group "=== CSI weights (must sum to 1) ==="
input double InpWeightCS          = 0.5;   // Weight on CS
input double InpWeightSP          = 0.3;   // Weight on SP
input double InpWeightNP          = 0.2;   // Weight on NP

input group "=== Decision (CD) ==="
input double InpReversalRatio     = 0.85;  // CSI(new)/CSI(prev) >= this => reversal
input double InpContinuationRatio = 0.55;  // CSI(new)/CSI(prev) <= this => continuation
input double InpMinCD             = 45.0;  // Minimum CD to act on a verdict

input group "=== Display and alerts ==="
input bool   InpShowPanel         = true;  // Draw the dashboard
input bool   InpShowPivotLabels   = true;  // Label each scored leg on the chart
input int    InpPanelX            = 12;    // Panel X offset
input int    InpPanelY            = 24;    // Panel Y offset
input bool   InpAlertOnSignal     = false; // Terminal alert on a new verdict
input bool   InpPushOnSignal      = false; // Push notification on a new verdict

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double BufCSI[];      // 0 - leg strength, 0..100
double BufCD[];       // 1 - two-leg fusion, 0..100
double BufCNS[];      // 2 - raw leg score (calculation buffer)
double BufVerdict[];  // 3 - VERDICT_* code
double BufDir[];      // 4 - direction of the last scored leg (+1 / -1)

//--- palette
#define COL_BG      C'10,14,23'
#define COL_EDGE    C'0,212,255'
#define COL_GOLD    C'255,199,0'
#define COL_TEXT    C'198,214,235'
#define COL_DIM     C'94,112,134'
#define COL_BULL    C'0,230,160'
#define COL_BEAR    C'255,84,112'
#define PANEL_PREFIX "CSIO_"

//--- indicator state
int    g_atrHandle   = INVALID_HANDLE;
double g_atr[];
int    g_atrCount    = 0;

//--- swing tracker
int    g_dir         = 0;      // +1 tracking a high, -1 tracking a low
double g_extPrice    = 0.0;
int    g_extIdx      = 0;
int    g_legStart    = 0;

//--- rolling leg results
double g_csiPrev     = 0.0;    // A - the previous (opposing) leg
double g_csiLast     = 0.0;    // B - the most recently closed leg
int    g_dirLast     = 0;
double g_cnsLast     = 0.0;
double g_csLast      = 0.0;
double g_spLast      = 0.0;
double g_npLast      = 0.0;
double g_cdLast      = 0.0;
double g_ratioLast   = 0.0;
int    g_verdictLast = VERDICT_NONE;
double g_rpLast      = 0.0;    // reference price of the verdict
double g_invalidLast = 0.0;    // level that invalidates it
int    g_legsScored  = 0;
datetime g_lastAlert = 0;

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void   ResetState();
double CandleValue(const double o, const double h, const double l, const double c, const int legDir);
double ScoreCS(const double cns, const int bars);
double ScoreSP(const double displacement, const double path);
double ScoreNP(const double displacement, const double atr);
double FuseCD(const double a, const double b);
void   CloseLeg(const int startIdx, const int endIdx, const int dir,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[]);
void   MaybeAlert(const int i, const int rates_total, const datetime barTime);
string VerdictText(const int v);
color  VerdictColor(const int v);
string TimeframeName();
void   DrawLegLabel(const datetime anchor, const double price, const int dir,
                    const double cns, const double csi);
void   PanelLabel(const string key, const int x, const int y, const string text,
                  const color clr, const int size, const string font);;
void   DrawPanel(const int rates_total);

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufCSI,     INDICATOR_DATA);
   SetIndexBuffer(1, BufCD,      INDICATOR_DATA);
   SetIndexBuffer(2, BufCNS,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufVerdict, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufDir,     INDICATOR_CALCULATIONS);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   const double wsum = InpWeightCS + InpWeightSP + InpWeightNP;
   if(MathAbs(wsum - 1.0) > 0.001)
      PrintFormat("CSI-Omega: weights sum to %.3f, not 1.0. CSI will not be on a 0..100 scale.", wsum);

   if(InpContinuationRatio >= InpReversalRatio)
     {
      Print("CSI-Omega: InpContinuationRatio must be below InpReversalRatio.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("CSI-Omega: could not create the ATR handle.");
      return(INIT_FAILED);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "CSI-Omega");
   IndicatorSetInteger(INDICATOR_DIGITS, 1);
   ResetState();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PANEL_PREFIX);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void ResetState()
  {
   g_dir = 0; g_extPrice = 0.0; g_extIdx = 0; g_legStart = 0;
   g_csiPrev = 0.0; g_csiLast = 0.0; g_dirLast = 0; g_cnsLast = 0.0;
   g_csLast = 0.0; g_spLast = 0.0; g_npLast = 0.0; g_cdLast = 0.0;
   g_ratioLast = 0.0; g_verdictLast = VERDICT_NONE;
   g_rpLast = 0.0; g_invalidLast = 0.0; g_legsScored = 0;
  }

//+------------------------------------------------------------------+
//| Vi - the score a single candle contributes to its leg.           |
//|                                                                  |
//| The score is assigned by candle class, not by counting the       |
//| candle as one unit. A candle that opposes the leg direction      |
//| subtracts, which is what keeps CNS a *net* score and is why a    |
//| 70-bar leg totals ~32 rather than ~70.                           |
//+------------------------------------------------------------------+
double CandleValue(const double o, const double h, const double l, const double c, const int legDir)
  {
   const double range = h - l;
   if(range <= 0.0)
      return(0.0);

   const double bodyRatio = MathAbs(c - o) / range;

   double magnitude = 0.0;
   if(bodyRatio >= InpBodyMarubozu)      magnitude = InpScoreMarubozu;
   else if(bodyRatio >= InpBodyStrong)   magnitude = InpScoreStrong;
   else if(bodyRatio >= InpBodyStandard) magnitude = InpScoreStandard;
   else if(bodyRatio >= InpBodyWeak)     magnitude = InpScoreWeak;
   // below InpBodyWeak the candle is a doji: indecision scores nothing.

   int candleDir = 0;
   if(c > o)      candleDir = 1;
   else if(c < o) candleDir = -1;

   double value = 0.0;
   if(candleDir == legDir)
      value = magnitude;
   else if(candleDir != 0)
      value = InpCounterNegative ? -magnitude : 0.0;

   // A long wick against the leg direction is a rejection *in favour* of it.
   const double bodyTop = MathMax(o, c);
   const double bodyBot = MathMin(o, c);
   const double lowerWick = (bodyBot - l) / range;
   const double upperWick = (h - bodyTop) / range;
   if(legDir > 0 && lowerWick >= InpWickThreshold)      value += InpWickBonus;
   else if(legDir < 0 && upperWick >= InpWickThreshold) value += InpWickBonus;

   return(value);
  }

//+------------------------------------------------------------------+
//| CS - candle strength. Net score per bar through a bounded        |
//| sigmoid, so a long limp leg cannot out-score a short decisive    |
//| one purely on bar count.                                         |
//+------------------------------------------------------------------+
double ScoreCS(const double cns, const int bars)
  {
   if(bars <= 0)
      return(0.0);
   const double perBar = cns / (double)bars;
   return(100.0 / (1.0 + MathExp(-InpCsAlpha * (perBar - InpCsMu))));
  }

//+------------------------------------------------------------------+
//| SP - structure purity. Kaufman efficiency ratio of the leg:      |
//| net displacement over the distance actually travelled. A leg     |
//| that grinds sideways to the same target scores lower.            |
//+------------------------------------------------------------------+
double ScoreSP(const double displacement, const double path)
  {
   if(path <= 0.0 || InpSpReference <= 0.0)
      return(0.0);
   const double er = MathAbs(displacement) / path;
   return(100.0 * MathMin(1.0, er / InpSpReference));
  }

//+------------------------------------------------------------------+
//| NP - net projection. Displacement in ATR units, saturating, so   |
//| the score is comparable across symbols and volatility regimes.   |
//+------------------------------------------------------------------+
double ScoreNP(const double displacement, const double atr)
  {
   if(atr <= 0.0 || InpNpAtrSpan <= 0.0)
      return(0.0);
   const double span = MathAbs(displacement) / (InpNpAtrSpan * atr);
   return(100.0 * (1.0 - MathExp(-span)));
  }

//+------------------------------------------------------------------+
//| CD - fusion of two consecutive opposing legs.                    |
//|                                                                  |
//| Geometric mean (both legs must be strong for CD to be high)      |
//| scaled by a quadratic divergence penalty. The penalty is taken   |
//| on the *relative* gap, which keeps CD inside 0..100 for every    |
//| input pair. See docs/CSI-MODEL.md for why the absolute-gap form  |
//| in the source material goes negative and unbounded.              |
//+------------------------------------------------------------------+
double FuseCD(const double a, const double b)
  {
   if(a <= 0.0 || b <= 0.0)
      return(0.0);
   const double rel = MathAbs(a - b) / (a + b);
   return(MathSqrt(a * b) * (1.0 - rel * rel));
  }

//+------------------------------------------------------------------+
//| Score one completed leg and fold it into the two-leg verdict.    |
//+------------------------------------------------------------------+
void CloseLeg(const int startIdx, const int endIdx, const int dir,
              const datetime &time[], const double &open[], const double &high[],
              const double &low[], const double &close[])
  {
   const int bars = endIdx - startIdx;
   if(bars < 2)
      return;

   double cns  = 0.0;
   double path = 0.0;
   for(int i = startIdx + 1; i <= endIdx; i++)
     {
      cns  += CandleValue(open[i], high[i], low[i], close[i], dir);
      path += MathAbs(close[i] - close[i - 1]);
     }

   const double displacement = close[endIdx] - close[startIdx];
   const double atr = (endIdx < g_atrCount && g_atr[endIdx] > 0.0) ? g_atr[endIdx] : 0.0;

   const double cs  = ScoreCS(cns, bars);
   const double sp  = ScoreSP(displacement, path);
   const double np  = ScoreNP(displacement, atr);
   const double csi = InpWeightCS * cs + InpWeightSP * sp + InpWeightNP * np;

   // Roll the window: the leg we just scored becomes B, the one before it A.
   g_csiPrev = g_csiLast;
   g_csiLast = csi;
   g_dirLast = dir;
   g_cnsLast = cns;
   g_csLast  = cs;
   g_spLast  = sp;
   g_npLast  = np;
   g_legsScored++;

   g_cdLast      = 0.0;
   g_ratioLast   = 0.0;
   g_verdictLast = VERDICT_NONE;

   if(g_legsScored >= 2 && g_csiPrev > 0.0)
     {
      g_cdLast    = FuseCD(g_csiPrev, g_csiLast);
      g_ratioLast = g_csiLast / g_csiPrev;

      // A counter-leg that nearly matches the impulse it is answering has
      // taken control: that is a reversal, even though it scores lower.
      // A counter-leg far below the impulse is only a pullback.
      if(g_ratioLast >= InpReversalRatio)
         g_verdictLast = (dir > 0) ? VERDICT_REVERSAL_UP : VERDICT_REVERSAL_DOWN;
      else if(g_ratioLast <= InpContinuationRatio)
         g_verdictLast = (dir > 0) ? VERDICT_CONT_DOWN : VERDICT_CONT_UP;
      else
         g_verdictLast = VERDICT_NEUTRAL;

      if(g_cdLast < InpMinCD)
         g_verdictLast = VERDICT_NEUTRAL;
     }

   // RP - the pivot that closed this leg, and the level that invalidates it.
   g_rpLast      = (dir > 0) ? high[endIdx] : low[endIdx];
   g_invalidLast = (dir > 0) ? low[startIdx] : high[startIdx];

   if(InpShowPivotLabels)
      DrawLegLabel(time[endIdx], g_rpLast, dir, cns, csi);
  }

//+------------------------------------------------------------------+
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
   if(rates_total < InpAtrPeriod + 10)
      return(0);

   // Refresh ATR only when a bar has been added, not on every tick.
   if(g_atrCount != rates_total)
     {
      if(CopyBuffer(g_atrHandle, 0, 0, rates_total, g_atr) < rates_total)
         return(0);
      g_atrCount = rates_total;
     }

   int start = prev_calculated - 1;
   if(prev_calculated == 0)
     {
      ResetState();
      ArrayInitialize(BufCSI, 0.0);
      ArrayInitialize(BufCD, 0.0);
      ArrayInitialize(BufCNS, 0.0);
      ArrayInitialize(BufVerdict, 0.0);
      ArrayInitialize(BufDir, 0.0);
      ObjectsDeleteAll(0, PANEL_PREFIX);

      start = InpAtrPeriod + 1;
      if(InpMaxBars > 0 && rates_total - start > InpMaxBars)
         start = rates_total - InpMaxBars;

      g_dir        = 1;
      g_extPrice   = high[start];
      g_extIdx     = start;
      g_legStart   = start;
     }
   if(start < 1)
      start = 1;

   for(int i = start; i < rates_total; i++)
     {
      const double dev = (i < g_atrCount ? g_atr[i] : 0.0) * InpDevMultiplier;

      if(dev > 0.0)
        {
         if(g_dir > 0)
           {
            if(high[i] > g_extPrice)
              {
               g_extPrice = high[i];
               g_extIdx   = i;
              }
            else if(g_extPrice - low[i] >= dev)
              {
               // Swing high at g_extIdx is now confirmed: score the leg into it.
               CloseLeg(g_legStart, g_extIdx, 1, time, open, high, low, close);
               MaybeAlert(i, rates_total, time[i]);
               g_legStart   = g_extIdx;
               g_dir        = -1;
               g_extPrice   = low[i];
               g_extIdx     = i;
              }
           }
         else
           {
            if(low[i] < g_extPrice)
              {
               g_extPrice = low[i];
               g_extIdx   = i;
              }
            else if(high[i] - g_extPrice >= dev)
              {
               CloseLeg(g_legStart, g_extIdx, -1, time, open, high, low, close);
               MaybeAlert(i, rates_total, time[i]);
               g_legStart   = g_extIdx;
               g_dir        = 1;
               g_extPrice   = high[i];
               g_extIdx     = i;
              }
           }
        }

      // Step-hold the last confirmed values forward. Nothing already written
      // is ever revised, which is what makes the plot non-repainting.
      BufCSI[i]     = g_csiLast;
      BufCD[i]      = g_cdLast;
      BufCNS[i]     = g_cnsLast;
      BufVerdict[i] = (double)g_verdictLast;
      BufDir[i]     = (double)g_dirLast;
     }

   if(InpShowPanel)
      DrawPanel(rates_total);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Alerts fire only for a verdict formed on the newest bars, never  |
//| while the indicator is walking back through history.             |
//+------------------------------------------------------------------+
void MaybeAlert(const int i, const int rates_total, const datetime barTime)
  {
   if(!InpAlertOnSignal && !InpPushOnSignal)
      return;
   if(i < rates_total - 2)
      return;
   if(g_verdictLast == VERDICT_NONE || g_verdictLast == VERDICT_NEUTRAL)
      return;
   if(g_lastAlert == barTime)
      return;

   g_lastAlert = barTime;
   const string msg = StringFormat("%s %s  %s | CSI %.1f vs %.1f  CD %.1f  RP %s",
                                   _Symbol, TimeframeName(),
                                   VerdictText(g_verdictLast),
                                   g_csiLast, g_csiPrev, g_cdLast,
                                   DoubleToString(g_rpLast, _Digits));
   if(InpAlertOnSignal)
      Alert(msg);
   if(InpPushOnSignal)
      SendNotification(msg);
  }

//+------------------------------------------------------------------+
string VerdictText(const int v)
  {
   switch(v)
     {
      case VERDICT_CONT_UP:        return("CONTINUATION UP");
      case VERDICT_CONT_DOWN:      return("CONTINUATION DOWN");
      case VERDICT_REVERSAL_UP:    return("REVERSAL UP");
      case VERDICT_REVERSAL_DOWN:  return("REVERSAL DOWN");
      case VERDICT_NEUTRAL:        return("NEUTRAL");
     }
   return("-");
  }

//+------------------------------------------------------------------+
color VerdictColor(const int v)
  {
   switch(v)
     {
      case VERDICT_CONT_UP:
      case VERDICT_REVERSAL_UP:    return(COL_BULL);
      case VERDICT_CONT_DOWN:
      case VERDICT_REVERSAL_DOWN:  return(COL_BEAR);
     }
   return(COL_DIM);
  }

//+------------------------------------------------------------------+
string TimeframeName()
  {
   return(StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7));
  }

//+------------------------------------------------------------------+
//| Chart label at each scored pivot: raw leg score over CSI.        |
//+------------------------------------------------------------------+
void DrawLegLabel(const datetime anchor, const double price, const int dir,
                  const double cns, const double csi)
  {
   if(anchor == 0)
      return;

   const string name = PANEL_PREFIX + "leg_" + IntegerToString((long)anchor);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, anchor, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, anchor);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetString(0, name, OBJPROP_TEXT, StringFormat("%.0f | %.1f", cns, csi));
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, COL_GOLD);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void PanelLabel(const string key, const int x, const int y, const string text,
                const color clr, const int size, const string font)
  {
   const string name = PANEL_PREFIX + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
void DrawPanel(const int rates_total)
  {
   const int x = InpPanelX;
   int y = InpPanelY;
   const int W = 228;
   const int H = 214;

   const string bg = PANEL_PREFIX + "bg";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x - 8);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y - 8);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, H);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, COL_BG);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, COL_EDGE);

   PanelLabel("title", x, y, "CSI-OMEGA  " + _Symbol + " " + TimeframeName(), COL_EDGE, 10, "Consolas");
   y += 20;

   // Live leg: what is accumulating right now, ahead of confirmation.
   const string legDirText = (g_dir > 0) ? "UP" : (g_dir < 0 ? "DOWN" : "-");
   PanelLabel("live", x, y, StringFormat("live leg    %-5s  %d bars", legDirText,
                                         MathMax(0, rates_total - 1 - g_legStart)), COL_DIM, 9, "Consolas");
   y += 16;

   PanelLabel("sep1", x, y, "-- last scored leg ------------", COL_DIM, 8, "Consolas");
   y += 16;

   const color dirCol = (g_dirLast > 0) ? COL_BULL : (g_dirLast < 0 ? COL_BEAR : COL_DIM);
   PanelLabel("dir", x, y, StringFormat("direction   %s", g_dirLast > 0 ? "UP" : (g_dirLast < 0 ? "DOWN" : "-")), dirCol, 9, "Consolas");
   y += 16;
   PanelLabel("cns", x, y, StringFormat("CNS         %.1f", g_cnsLast), COL_GOLD, 9, "Consolas");
   y += 16;
   PanelLabel("sub", x, y, StringFormat("CS %.0f  SP %.0f  NP %.0f", g_csLast, g_spLast, g_npLast), COL_TEXT, 9, "Consolas");
   y += 16;
   PanelLabel("csi", x, y, StringFormat("CSI (B)     %.1f", g_csiLast), COL_GOLD, 10, "Consolas");
   y += 18;
   PanelLabel("prev", x, y, StringFormat("CSI (A)     %.1f", g_csiPrev), COL_TEXT, 9, "Consolas");
   y += 16;

   PanelLabel("sep2", x, y, "-- fusion ---------------------", COL_DIM, 8, "Consolas");
   y += 16;
   PanelLabel("ratio", x, y, StringFormat("B/A         %.3f", g_ratioLast), COL_TEXT, 9, "Consolas");
   y += 16;
   PanelLabel("cd", x, y, StringFormat("CD          %.1f", g_cdLast), COL_EDGE, 10, "Consolas");
   y += 18;
   PanelLabel("verdict", x, y, VerdictText(g_verdictLast), VerdictColor(g_verdictLast), 10, "Consolas");
   y += 18;
   PanelLabel("rp", x, y, StringFormat("RP  %s", DoubleToString(g_rpLast, _Digits)), COL_TEXT, 8, "Consolas");
   y += 14;
   PanelLabel("inv", x, y, StringFormat("inv %s", DoubleToString(g_invalidLast, _Digits)), COL_DIM, 8, "Consolas");

   ChartRedraw();
  }
//+------------------------------------------------------------------+
