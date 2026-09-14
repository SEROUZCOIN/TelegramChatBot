//+------------------------------------------------------------------+
//|                                                CSI_Omega_Pro.mq5 |
//|   CSI-Omega signal system - arrows, levels, MTF, dashboard       |
//+------------------------------------------------------------------+
//
// The trading surface of the CSI-Omega model. The scoring itself lives in
// Include/CSIOmega.mqh and is shared with CSI_Omega.mq5, so the formula
// cannot drift between the two.
//
// What it adds over the reference indicator
// -----------------------------------------
//  * Buy / Sell arrows at each actionable verdict.
//  * Entry, stop and three targets derived from the leg's own structure.
//  * Multi-timeframe confluence - the same model run on up to three higher
//    timeframes, optionally required to agree before a signal is drawn.
//  * A dashboard showing the live leg, the sub-scores, the fusion, the last
//    signal and a running hit rate measured over the visible history.
//
// Repainting
// ----------
// A leg is scored only once its terminating swing is confirmed by an
// ATR-scaled retracement, so an arrow appears one confirmation behind the
// pivot it refers to. Nothing already drawn is ever moved or removed. The
// hit rate is measured on those same confirmed signals, so it reflects what
// the indicator actually printed, not hindsight.
//
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property strict
#property description "CSI-Omega Pro: candle-scored leg strength with entry arrows, structural levels, MTF confluence and a live dashboard"

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   2

#property indicator_label1  "CSI Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  C'0,230,160'
#property indicator_width1  2

#property indicator_label2  "CSI Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'255,84,112'
#property indicator_width2  2

#include <CSIOmega.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Leg detection ==="
input int              InpAtrPeriod        = 14;      // ATR period for the swing threshold
input double           InpDevMultiplier    = 2.0;     // Swing confirmed after N x ATR retrace
input int              InpMaxBars          = 4000;    // Bars to calculate (0 = all)

input group "=== Candle value (Vi) ==="
input double           InpBodyMarubozu     = 0.80;    // Body/range >= this is a marubozu
input double           InpBodyStrong       = 0.60;    // Body/range >= this is a strong body
input double           InpBodyStandard     = 0.40;    // Body/range >= this is a standard body
input double           InpBodyWeak         = 0.20;    // Body/range >= this is a weak body
input double           InpScoreMarubozu    = 4.0;     // Score: marubozu
input double           InpScoreStrong      = 3.0;     // Score: strong body
input double           InpScoreStandard    = 2.0;     // Score: standard body
input double           InpScoreWeak        = 1.0;     // Score: weak body
input double           InpWickThreshold    = 0.50;    // Wick/range for a rejection candle
input double           InpWickBonus        = 1.0;     // Bonus for a with-trend rejection wick
input bool             InpCounterNegative  = true;    // Counter-direction candles score negative

input group "=== Sub-scores and weights ==="
input double           InpCsAlpha          = 3.0;     // CS sigmoid gain
input double           InpCsMu             = 0.0;     // CS sigmoid midpoint (net score per bar)
input double           InpSpReference      = 0.60;    // Efficiency ratio that scores SP = 100
input double           InpNpAtrSpan        = 8.0;     // Leg displacement in ATR for NP saturation
input double           InpWeightCS         = 0.5;     // Weight on CS
input double           InpWeightSP         = 0.3;     // Weight on SP
input double           InpWeightNP         = 0.2;     // Weight on NP

input group "=== Decision ==="
input double           InpReversalRatio    = 1.10;    // CSI(new)/CSI(prev) >= this => reversal
input double           InpContinuationRatio= 0.75;    // CSI(new)/CSI(prev) <= this => continuation
input double           InpMinCD            = 45.0;    // Minimum fused CD to issue a verdict
input double           InpMinCSI           = 55.0;    // Minimum CSI on the new leg to signal

input group "=== Multi-timeframe confluence ==="
input bool             InpUseMtf           = true;              // Run the model on higher timeframes
input ENUM_TIMEFRAMES  InpMtf1             = PERIOD_H1;         // Confluence timeframe 1
input ENUM_TIMEFRAMES  InpMtf2             = PERIOD_H4;         // Confluence timeframe 2
input ENUM_TIMEFRAMES  InpMtf3             = PERIOD_D1;         // Confluence timeframe 3
input int              InpMtfBars          = 1500;              // Bars to scan per timeframe
input bool             InpRequireMtf       = false;             // Block signals without agreement
input int              InpMtfMinAgree      = 1;                 // Timeframes that must agree

input group "=== Trade levels ==="
input bool             InpShowLevels       = true;    // Draw entry / stop / target lines
input double           InpSlAtrBuffer      = 0.5;     // Stop placed this many ATR beyond structure
input double           InpMinStopAtr       = 0.75;    // Never risk less than this many ATR
input double           InpTp1R             = 1.0;     // Target 1 in R
input double           InpTp2R             = 2.0;     // Target 2 in R
input double           InpTp3R             = 3.0;     // Target 3 in R

input group "=== Display ==="
input bool             InpShowPanel        = true;    // Draw the dashboard
input bool             InpShowLegLabels    = true;    // Label each scored leg
input int              InpPanelX           = 14;      // Panel X offset
input int              InpPanelY           = 26;      // Panel Y offset
input int              InpArrowGapAtr      = 1;       // Arrow offset from price, in ATR tenths

input group "=== Alerts ==="
input bool             InpAlertOnSignal    = false;   // Terminal alert on a new signal
input bool             InpPushOnSignal     = false;   // Push notification on a new signal

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double BufBuy[];      // 0 - buy arrow price
double BufSell[];     // 1 - sell arrow price
double BufCSI[];      // 2 - leg strength (iCustom)
double BufCD[];       // 3 - fused score (iCustom)
double BufVerdict[];  // 4 - verdict code (iCustom)

//--- palette
#define COL_BG      C'8,12,20'
#define COL_PANE    C'14,20,32'
#define COL_EDGE    C'0,212,255'
#define COL_GOLD    C'255,199,0'
#define COL_TEXT    C'205,219,238'
#define COL_DIM     C'92,110,132'
#define COL_BULL    C'0,230,160'
#define COL_BEAR    C'255,84,112'
#define PFX         "CSIP_"

//--- one higher timeframe's reading
struct MtfSlot
  {
   ENUM_TIMEFRAMES   tf;
   int               atrHandle;
   double            csi;
   double            cd;
   int               verdict;
   int               bias;
   datetime          lastBar;
   bool              valid;
  };

//--- a signal that has been drawn and is being tracked for its outcome
struct OpenSignal
  {
   int               dir;
   double            entry;
   double            sl;
   double            tp1;
   bool              active;
  };

CCSIEngine  g_engine;
CSISettings g_set;
int         g_atrHandle = INVALID_HANDLE;
double      g_atr[];
int         g_atrCount  = 0;

MtfSlot     g_mtf[3];
int         g_mtfCount  = 0;

OpenSignal  g_open[];
int         g_fed = -1;      // last bar index fed to the engine, never re-fed
int         g_signals = 0, g_buys = 0, g_sells = 0, g_wins = 0, g_losses = 0;

//--- last drawn signal, for the panel and the level lines
int         g_lastDir   = 0;
double      g_lastEntry = 0.0, g_lastSl = 0.0, g_lastTp1 = 0.0, g_lastTp2 = 0.0, g_lastTp3 = 0.0;
datetime    g_lastTime  = 0;
datetime    g_alertedAt = 0;

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void   BuildSettings();
void   ScanMtf(const int slot);
void   RefreshMtf();
int    MtfAgreement(const int bias);
void   EmitSignal(const int i, const int bias, const CSILeg &leg, const double atrHere,
                  const datetime &time[], const double &high[], const double &low[], const double &close[]);
void   TrackOutcomes(const int i, const double &high[], const double &low[]);
void   DrawLegLabel(const datetime anchor, const double price, const int dir,
                    const double cns, const double csi);
void   DrawLevels();
void   DrawPanel(const int rates_total);
void   PanelRect(const string key, const int x, const int y, const int w, const int h, const color bg, const color edge);
void   PanelText(const string key, const int x, const int y, const string text, const color clr, const int size, const string font);
void   PanelGauge(const string key, const int x, const int y, const int w, const double pct, const color clr);
string TfName(const ENUM_TIMEFRAMES tf);
void   ClearObjects();

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBuy,     INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,    INDICATOR_DATA);
   SetIndexBuffer(2, BufCSI,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufCD,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufVerdict, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);   // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);   // down arrow
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   BuildSettings();

   const double wsum = InpWeightCS + InpWeightSP + InpWeightNP;
   if(MathAbs(wsum - 1.0) > 0.001)
      PrintFormat("CSI-Omega Pro: weights sum to %.3f, not 1.0. CSI will not be on a 0..100 scale.", wsum);

   if(InpContinuationRatio >= InpReversalRatio)
     {
      Print("CSI-Omega Pro: InpContinuationRatio must be below InpReversalRatio.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("CSI-Omega Pro: could not create the ATR handle.");
      return(INIT_FAILED);
     }

   // Higher timeframes are optional and each one is independent: a timeframe
   // whose handle fails is dropped rather than failing the whole indicator.
   g_mtfCount = 0;
   if(InpUseMtf)
     {
      ENUM_TIMEFRAMES wanted[3];
      wanted[0] = InpMtf1; wanted[1] = InpMtf2; wanted[2] = InpMtf3;
      for(int k = 0; k < 3; k++)
        {
         if(wanted[k] == PERIOD_CURRENT)
            continue;
         const int h = iATR(_Symbol, wanted[k], InpAtrPeriod);
         if(h == INVALID_HANDLE)
           {
            PrintFormat("CSI-Omega Pro: no ATR handle for %s, dropping it from confluence.", TfName(wanted[k]));
            continue;
           }
         g_mtf[g_mtfCount].tf        = wanted[k];
         g_mtf[g_mtfCount].atrHandle = h;
         g_mtf[g_mtfCount].csi       = 0.0;
         g_mtf[g_mtfCount].cd        = 0.0;
         g_mtf[g_mtfCount].verdict   = CSI_NONE;
         g_mtf[g_mtfCount].bias      = 0;
         g_mtf[g_mtfCount].lastBar   = 0;
         g_mtf[g_mtfCount].valid     = false;
         g_mtfCount++;
        }
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "CSI-Omega Pro");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearObjects();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   for(int k = 0; k < g_mtfCount; k++)
      if(g_mtf[k].atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_mtf[k].atrHandle);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void ClearObjects()
  {
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
void BuildSettings()
  {
   CSIDefaults(g_set);
   g_set.devMultiplier     = InpDevMultiplier;
   g_set.bodyMarubozu      = InpBodyMarubozu;
   g_set.bodyStrong        = InpBodyStrong;
   g_set.bodyStandard      = InpBodyStandard;
   g_set.bodyWeak          = InpBodyWeak;
   g_set.scoreMarubozu     = InpScoreMarubozu;
   g_set.scoreStrong       = InpScoreStrong;
   g_set.scoreStandard     = InpScoreStandard;
   g_set.scoreWeak         = InpScoreWeak;
   g_set.wickThreshold     = InpWickThreshold;
   g_set.wickBonus         = InpWickBonus;
   g_set.counterNegative   = InpCounterNegative;
   g_set.csAlpha           = InpCsAlpha;
   g_set.csMu              = InpCsMu;
   g_set.spReference       = InpSpReference;
   g_set.npAtrSpan         = InpNpAtrSpan;
   g_set.weightCS          = InpWeightCS;
   g_set.weightSP          = InpWeightSP;
   g_set.weightNP          = InpWeightNP;
   g_set.reversalRatio     = InpReversalRatio;
   g_set.continuationRatio = InpContinuationRatio;
   g_set.minCD             = InpMinCD;
   g_engine.Configure(g_set);
  }

//+------------------------------------------------------------------+
//| Run the whole model over one higher timeframe. Called only when  |
//| that timeframe prints a new bar, never per tick.                 |
//+------------------------------------------------------------------+
void ScanMtf(const int slot)
  {
   const ENUM_TIMEFRAMES tf = g_mtf[slot].tf;
   const int want = MathMax(200, InpMtfBars);

   datetime t[]; double o[], h[], l[], c[], a[];
   const int n = CopyClose(_Symbol, tf, 0, want, c);
   if(n < InpAtrPeriod + 30)
     {
      g_mtf[slot].valid = false;
      return;
     }
   if(CopyTime(_Symbol, tf, 0, n, t) < n || CopyOpen(_Symbol, tf, 0, n, o) < n ||
      CopyHigh(_Symbol, tf, 0, n, h) < n || CopyLow(_Symbol, tf, 0, n, l) < n ||
      CopyBuffer(g_mtf[slot].atrHandle, 0, 0, n, a) < n)
     {
      g_mtf[slot].valid = false;
      return;
     }

   CCSIEngine eng;
   eng.Configure(g_set);
   eng.Seed(InpAtrPeriod + 1, h[InpAtrPeriod + 1]);

   CSILeg leg;
   for(int i = InpAtrPeriod + 2; i < n; i++)
      eng.Feed(i, t, o, h, l, c, a, n, leg);

   g_mtf[slot].csi     = eng.CSILast();
   g_mtf[slot].cd      = eng.CD();
   g_mtf[slot].verdict = eng.Verdict();
   g_mtf[slot].bias    = CSIVerdictBias(eng.Verdict());
   g_mtf[slot].valid   = true;
  }

//+------------------------------------------------------------------+
void RefreshMtf()
  {
   for(int k = 0; k < g_mtfCount; k++)
     {
      const datetime bar = iTime(_Symbol, g_mtf[k].tf, 0);
      if(bar == 0 || bar == g_mtf[k].lastBar)
         continue;
      g_mtf[k].lastBar = bar;
      ScanMtf(k);
     }
  }

//+------------------------------------------------------------------+
//| How many higher timeframes currently read the same way.          |
//+------------------------------------------------------------------+
int MtfAgreement(const int bias)
  {
   int agree = 0;
   for(int k = 0; k < g_mtfCount; k++)
      if(g_mtf[k].valid && g_mtf[k].bias == bias && bias != 0)
         agree++;
   return(agree);
  }

//+------------------------------------------------------------------+
//| Draw a signal: arrow, levels, stats, alert.                      |
//+------------------------------------------------------------------+
void EmitSignal(const int i, const int bias, const CSILeg &leg, const double atrHere,
                const datetime &time[], const double &high[], const double &low[], const double &close[])
  {
   const double entry  = close[i];
   const double buffer = atrHere * InpSlAtrBuffer;

   // The stop sits beyond the structure the verdict actually rests on, and
   // which level that is depends on the verdict rather than the direction:
   // a reversal is invalidated by the leg's ORIGIN (price returning there
   // means the counter-leg never took control), a continuation by the PIVOT
   // the leg just failed at. Using the pivot for both puts a long's stop
   // above its entry, because confirmation only arrives after price has
   // already retraced away from that pivot.
   const bool isReversal = (leg.verdict == CSI_REVERSAL_UP || leg.verdict == CSI_REVERSAL_DOWN);
   const double structure = isReversal ? leg.invalidPrice : leg.pivotPrice;
   const double sl = (bias > 0) ? (structure - buffer) : (structure + buffer);

   // The stop must end up on the far side of entry. If it does not, the leg
   // geometry contradicts the verdict and nothing is drawn: a signal whose
   // risk cannot be stated is not a signal.
   if((bias > 0 && sl >= entry) || (bias < 0 && sl <= entry))
      return;

   // A structurally correct stop can still sit inside the noise when the
   // pivot is close to the confirmation bar. Widen it to a floor rather
   // than trading a stop the spread alone could take out. This only ever
   // moves the stop further away, never nearer.
   double stop = sl;
   const double minRisk = atrHere * InpMinStopAtr;
   if(MathAbs(entry - stop) < minRisk)
      stop = (bias > 0) ? (entry - minRisk) : (entry + minRisk);

   const double risk = MathAbs(entry - stop);
   if(risk <= 0.0)
      return;

   const double gap = atrHere * (InpArrowGapAtr / 10.0);
   if(bias > 0)
      BufBuy[i]  = low[i] - gap;
   else
      BufSell[i] = high[i] + gap;

   g_lastDir   = bias;
   g_lastEntry = entry;
   g_lastSl    = stop;
   g_lastTp1   = entry + bias * risk * InpTp1R;
   g_lastTp2   = entry + bias * risk * InpTp2R;
   g_lastTp3   = entry + bias * risk * InpTp3R;
   g_lastTime  = time[i];

   g_signals++;
   if(bias > 0) g_buys++; else g_sells++;

   // Track it so the panel's hit rate is measured, not assumed.
   const int n = ArraySize(g_open);
   ArrayResize(g_open, n + 1);
   g_open[n].dir    = bias;
   g_open[n].entry  = entry;
   g_open[n].sl     = stop;
   g_open[n].tp1    = g_lastTp1;
   g_open[n].active = true;

   if(InpShowLegLabels)
      DrawLegLabel(leg.endTime, leg.pivotPrice, leg.dir, leg.cns, leg.csi);

   if((InpAlertOnSignal || InpPushOnSignal) && g_alertedAt != time[i])
     {
      g_alertedAt = time[i];
      const string msg = StringFormat("%s %s  CSI-Omega %s  entry %s  SL %s  TP1 %s  (CSI %.1f  CD %.1f)",
                                      _Symbol, TfName((ENUM_TIMEFRAMES)_Period),
                                      bias > 0 ? "BUY" : "SELL",
                                      DoubleToString(entry, _Digits),
                                      DoubleToString(stop, _Digits),
                                      DoubleToString(g_lastTp1, _Digits),
                                      leg.csi, leg.cd);
      if(InpAlertOnSignal) Alert(msg);
      if(InpPushOnSignal)  SendNotification(msg);
     }
  }

//+------------------------------------------------------------------+
//| Resolve tracked signals against bar i: whichever of stop or      |
//| first target is touched decides it. A bar that spans both is     |
//| scored a loss, which is the conservative reading.                |
//+------------------------------------------------------------------+
void TrackOutcomes(const int i, const double &high[], const double &low[])
  {
   for(int k = 0; k < ArraySize(g_open); k++)
     {
      if(!g_open[k].active)
         continue;

      if(g_open[k].dir > 0)
        {
         if(low[i] <= g_open[k].sl)       { g_open[k].active = false; g_losses++; }
         else if(high[i] >= g_open[k].tp1) { g_open[k].active = false; g_wins++; }
        }
      else
        {
         if(high[i] >= g_open[k].sl)      { g_open[k].active = false; g_losses++; }
         else if(low[i] <= g_open[k].tp1)  { g_open[k].active = false; g_wins++; }
        }
     }
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
   if(rates_total < InpAtrPeriod + 40)
      return(0);

   if(g_atrCount != rates_total)
     {
      if(CopyBuffer(g_atrHandle, 0, 0, rates_total, g_atr) < rates_total)
         return(0);
      g_atrCount = rates_total;
     }

   RefreshMtf();

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufCSI, 0.0);
      ArrayInitialize(BufCD, 0.0);
      ArrayInitialize(BufVerdict, 0.0);
      ClearObjects();

      g_engine.Reset();
      g_engine.Configure(g_set);
      ArrayResize(g_open, 0);
      g_signals = 0; g_buys = 0; g_sells = 0; g_wins = 0; g_losses = 0;
      g_lastDir = 0; g_lastTime = 0;

      int seed = InpAtrPeriod + 1;
      if(InpMaxBars > 0 && rates_total - seed > InpMaxBars)
         seed = rates_total - InpMaxBars;

      g_engine.Seed(seed, high[seed]);
      g_fed = seed;
     }

   if(g_fed < 0)
      return(0);

   // The engine carries state across bars, so every bar is fed exactly once
   // and only after it has closed. The forming bar is never fed: MT5
   // re-delivers it on every tick, and feeding it twice would advance the
   // swing tracker twice on the same candle.
   const int lastClosed = rates_total - 2;

   CSILeg leg;
   for(int i = g_fed + 1; i <= lastClosed; i++)
     {
      BufBuy[i]  = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;

      TrackOutcomes(i, high, low);

      if(g_engine.Feed(i, time, open, high, low, close, g_atr, g_atrCount, leg))
        {
         const int bias = CSIVerdictBias(leg.verdict);
         const double atrHere = (i < g_atrCount) ? g_atr[i] : 0.0;

         bool allowed = (bias != 0 && leg.csi >= InpMinCSI && atrHere > 0.0);
         if(allowed && InpRequireMtf && g_mtfCount > 0)
            allowed = (MtfAgreement(bias) >= InpMtfMinAgree);

         if(allowed)
            EmitSignal(i, bias, leg, atrHere, time, high, low, close);
         else if(InpShowLegLabels)
            DrawLegLabel(leg.endTime, leg.pivotPrice, leg.dir, leg.cns, leg.csi);
        }

      BufCSI[i]     = g_engine.CSILast();
      BufCD[i]      = g_engine.CD();
      BufVerdict[i] = (double)g_engine.Verdict();
      g_fed = i;
     }

   // The forming bar mirrors the last confirmed reading rather than carrying
   // one of its own, so nothing on it can change retroactively.
   const int live = rates_total - 1;
   BufBuy[live]     = EMPTY_VALUE;
   BufSell[live]    = EMPTY_VALUE;
   BufCSI[live]     = g_engine.CSILast();
   BufCD[live]      = g_engine.CD();
   BufVerdict[live] = (double)g_engine.Verdict();

   if(InpShowLevels && g_lastDir != 0)
      DrawLevels();
   if(InpShowPanel)
      DrawPanel(rates_total);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Chart furniture                                                  |
//+------------------------------------------------------------------+
void DrawLegLabel(const datetime anchor, const double price, const int dir,
                  const double cns, const double csi)
  {
   if(anchor == 0)
      return;
   const string name = PFX + "leg_" + IntegerToString((long)anchor);
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
  }

//+------------------------------------------------------------------+
void LevelLine(const string key, const double price, const color clr,
               const ENUM_LINE_STYLE style, const string text)
  {
   const string name = PFX + key;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, text + "  " + DoubleToString(price, _Digits));
  }

//+------------------------------------------------------------------+
void DrawLevels()
  {
   LevelLine("lv_entry", g_lastEntry, COL_GOLD, STYLE_SOLID,  "CSI entry");
   LevelLine("lv_sl",    g_lastSl,    COL_BEAR, STYLE_DASH,   "CSI stop");
   LevelLine("lv_tp1",   g_lastTp1,   COL_BULL, STYLE_DOT,    "CSI TP1");
   LevelLine("lv_tp2",   g_lastTp2,   COL_BULL, STYLE_DOT,    "CSI TP2");
   LevelLine("lv_tp3",   g_lastTp3,   COL_BULL, STYLE_DOT,    "CSI TP3");
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void PanelRect(const string key, const int x, const int y, const int w, const int h,
               const color bg, const color edge)
  {
   const string name = PFX + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, edge);
  }

//+------------------------------------------------------------------+
void PanelText(const string key, const int x, const int y, const string text,
               const color clr, const int size, const string font)
  {
   const string name = PFX + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
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
//| A 0..100 bar. Track then fill, so an empty score still reads as  |
//| a bar rather than as nothing.                                    |
//+------------------------------------------------------------------+
void PanelGauge(const string key, const int x, const int y, const int w,
                const double pct, const color clr)
  {
   const double p = MathMax(0.0, MathMin(100.0, pct));
   PanelRect(key + "_bg", x, y, w, 7, C'26,34,50', C'26,34,50');
   const int fill = (int)MathRound(w * p / 100.0);
   if(fill > 0)
      PanelRect(key + "_fg", x, y, fill, 7, clr, clr);
   else
      PanelRect(key + "_fg", x, y, 1, 7, C'26,34,50', C'26,34,50');
  }

//+------------------------------------------------------------------+
string TfName(const ENUM_TIMEFRAMES tf)
  {
   const ENUM_TIMEFRAMES p = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : tf;
   return(StringSubstr(EnumToString(p), 7));
  }

//+------------------------------------------------------------------+
void DrawPanel(const int rates_total)
  {
   const int x = InpPanelX;
   const int W = 268;
   int y = InpPanelY;

   const int verdict = g_engine.Verdict();
   const int bias    = CSIVerdictBias(verdict);
   const color bcol  = (bias > 0) ? COL_BULL : (bias < 0 ? COL_BEAR : COL_DIM);

   PanelRect("shell", x - 10, y - 10, W, 312, COL_BG, COL_EDGE);

   PanelText("title", x, y, "CSI-OMEGA PRO", COL_EDGE, 11, "Consolas");
   PanelText("sym",   x + 150, y, _Symbol + " " + TfName(PERIOD_CURRENT), COL_TEXT, 9, "Consolas");
   y += 22;

   //--- multi-timeframe confluence
   PanelText("mtfh", x, y, "CONFLUENCE", COL_DIM, 8, "Consolas");
   y += 15;
   if(g_mtfCount == 0)
     {
      PanelText("mtf0", x, y, "higher timeframes off", COL_DIM, 9, "Consolas");
      y += 17;
     }
   else
     {
      for(int k = 0; k < g_mtfCount; k++)
        {
         const string tag = "mtf" + IntegerToString(k);
         if(!g_mtf[k].valid)
           {
            PanelText(tag, x, y, StringFormat("%-4s  loading", TfName(g_mtf[k].tf)), COL_DIM, 9, "Consolas");
           }
         else
           {
            const int b = g_mtf[k].bias;
            const color c = (b > 0) ? COL_BULL : (b < 0 ? COL_BEAR : COL_DIM);
            PanelText(tag, x, y, StringFormat("%-4s  %s  CSI %.1f",
                                              TfName(g_mtf[k].tf),
                                              b > 0 ? "UP  " : (b < 0 ? "DOWN" : "--  "),
                                              g_mtf[k].csi), c, 9, "Consolas");
           }
         y += 16;
        }
     }
   y += 6;

   //--- sub-scores
   PanelText("subh", x, y, "LEG COMPONENTS", COL_DIM, 8, "Consolas");
   y += 15;
   PanelText("csl", x, y, StringFormat("CS %3.0f", g_engine.CS()), COL_TEXT, 9, "Consolas");
   PanelGauge("csg", x + 62, y + 4, 172, g_engine.CS(), COL_EDGE);
   y += 17;
   PanelText("spl", x, y, StringFormat("SP %3.0f", g_engine.SP()), COL_TEXT, 9, "Consolas");
   PanelGauge("spg", x + 62, y + 4, 172, g_engine.SP(), COL_EDGE);
   y += 17;
   PanelText("npl", x, y, StringFormat("NP %3.0f", g_engine.NP()), COL_TEXT, 9, "Consolas");
   PanelGauge("npg", x + 62, y + 4, 172, g_engine.NP(), COL_EDGE);
   y += 22;

   //--- headline numbers
   PanelText("csi", x, y, StringFormat("CSI %5.1f", g_engine.CSILast()), COL_GOLD, 11, "Consolas");
   PanelText("cd",  x + 132, y, StringFormat("CD %5.1f", g_engine.CD()), COL_EDGE, 11, "Consolas");
   y += 19;
   PanelText("ratio", x, y, StringFormat("B/A %.3f", g_engine.Ratio()), COL_TEXT, 9, "Consolas");
   PanelText("cns",   x + 132, y, StringFormat("CNS %.0f", g_engine.CNS()), COL_TEXT, 9, "Consolas");
   y += 20;

   //--- verdict
   PanelRect("vbox", x - 4, y - 3, W - 12, 22, COL_PANE, bcol);
   PanelText("verdict", x, y, CSIVerdictText(verdict), bcol, 10, "Consolas");
   y += 28;

   //--- last signal
   PanelText("sigh", x, y, "LAST SIGNAL", COL_DIM, 8, "Consolas");
   y += 15;
   if(g_lastDir == 0)
     {
      PanelText("sig1", x, y, "none yet", COL_DIM, 9, "Consolas");
      y += 16;
      PanelText("sig2", x, y, "", COL_DIM, 9, "Consolas");
     }
   else
     {
      const color sc = (g_lastDir > 0) ? COL_BULL : COL_BEAR;
      PanelText("sig1", x, y, StringFormat("%-4s @ %s", g_lastDir > 0 ? "BUY" : "SELL",
                                           DoubleToString(g_lastEntry, _Digits)), sc, 10, "Consolas");
      y += 16;
      PanelText("sig2", x, y, StringFormat("SL %s  TP1 %s",
                                           DoubleToString(g_lastSl, _Digits),
                                           DoubleToString(g_lastTp1, _Digits)), COL_TEXT, 8, "Consolas");
     }
   y += 20;

   //--- measured stats over the calculated history
   const int resolved = g_wins + g_losses;
   const double hit = (resolved > 0) ? (100.0 * g_wins / resolved) : 0.0;
   PanelText("stats", x, y,
             StringFormat("%d signals  %dB/%dS", g_signals, g_buys, g_sells), COL_DIM, 8, "Consolas");
   y += 14;
   PanelText("hit", x, y,
             resolved > 0
             ? StringFormat("to TP1: %d/%d  %.0f%%", g_wins, resolved, hit)
             : "to TP1: no resolved signals yet",
             resolved > 0 ? (hit >= 50.0 ? COL_BULL : COL_BEAR) : COL_DIM, 8, "Consolas");

   ChartRedraw();
  }
//+------------------------------------------------------------------+
