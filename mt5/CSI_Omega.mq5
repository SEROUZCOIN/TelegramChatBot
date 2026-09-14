//+------------------------------------------------------------------+
//|                                                    CSI_Omega.mq5 |
//|   CSI-Omega - the reference oscillator                           |
//+------------------------------------------------------------------+
//
// Plots the model's leg strength (CSI) and two-leg fusion (CD) in a
// subwindow, with a compact panel. This is the reading surface: for entry
// arrows, structural levels and multi-timeframe confluence use
// CSI_Omega_Pro.mq5, which drives the same engine.
//
// The scoring lives in Include/CSIOmega.mqh and is shared by both, so the
// formula cannot drift between them. The derivation and the calibration are
// in docs/CSI-MODEL.md.
//
// Repainting
// ----------
// A leg is scored only once its terminating swing has been confirmed by an
// ATR-scaled retracement. Confirmation lags the actual pivot by design; once
// written, a value is never revised. The live leg is shown in the panel
// only, never in a buffer.
//
#property copyright "Trading Signals Platform"
#property version   "1.10"
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

#include <CSIOmega.mqh>

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
input double InpReversalRatio     = 1.10;  // CSI(new)/CSI(prev) >= this => reversal
input double InpContinuationRatio = 0.75;  // CSI(new)/CSI(prev) <= this => continuation
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
double BufVerdict[];  // 3 - verdict code
double BufDir[];      // 4 - direction of the last scored leg

//--- palette
#define COL_BG      C'10,14,23'
#define COL_EDGE    C'0,212,255'
#define COL_GOLD    C'255,199,0'
#define COL_TEXT    C'198,214,235'
#define COL_DIM     C'94,112,134'
#define COL_BULL    C'0,230,160'
#define COL_BEAR    C'255,84,112'
#define PFX         "CSIO_"

CCSIEngine  g_engine;
CSISettings g_set;
int         g_atrHandle = INVALID_HANDLE;
double      g_atr[];
int         g_atrCount  = 0;
datetime    g_alertedAt = 0;
int         g_fed       = -1;  // last bar index fed to the engine, never re-fed

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void   BuildSettings();
void   MaybeAlert(const int i, const int rates_total, const datetime barTime);
color  VerdictColor(const int v);
string TfName();
void   DrawLegLabel(const datetime anchor, const double price, const int dir,
                    const double cns, const double csi);
void   PanelLabel(const string key, const int x, const int y, const string text,
                  const color clr, const int size, const string font);
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

   BuildSettings();

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
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   ChartRedraw();
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

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufCSI, 0.0);
      ArrayInitialize(BufCD, 0.0);
      ArrayInitialize(BufCNS, 0.0);
      ArrayInitialize(BufVerdict, 0.0);
      ArrayInitialize(BufDir, 0.0);
      ObjectsDeleteAll(0, PFX);

      g_engine.Reset();
      g_engine.Configure(g_set);

      int seed = InpAtrPeriod + 1;
      if(InpMaxBars > 0 && rates_total - seed > InpMaxBars)
         seed = rates_total - InpMaxBars;

      g_engine.Seed(seed, high[seed]);
      g_fed = seed;
     }

   if(g_fed < 0)
      return(0);

   // The engine carries state across bars, so every bar is fed exactly once
   // and only after it has closed. MT5 re-delivers the forming bar on every
   // tick; feeding it twice would advance the swing tracker twice.
   const int lastClosed = rates_total - 2;

   CSILeg leg;
   for(int i = g_fed + 1; i <= lastClosed; i++)
     {
      if(g_engine.Feed(i, time, open, high, low, close, g_atr, g_atrCount, leg))
        {
         if(InpShowPivotLabels)
            DrawLegLabel(leg.endTime, leg.pivotPrice, leg.dir, leg.cns, leg.csi);
         MaybeAlert(i, rates_total, time[i]);
        }

      // Step-hold the last confirmed values forward. Nothing already written
      // is ever revised, which is what makes the plot non-repainting.
      BufCSI[i]     = g_engine.CSILast();
      BufCD[i]      = g_engine.CD();
      BufCNS[i]     = g_engine.CNS();
      BufVerdict[i] = (double)g_engine.Verdict();
      BufDir[i]     = (double)g_engine.DirLast();
      g_fed = i;
     }

   const int live = rates_total - 1;
   BufCSI[live]     = g_engine.CSILast();
   BufCD[live]      = g_engine.CD();
   BufCNS[live]     = g_engine.CNS();
   BufVerdict[live] = (double)g_engine.Verdict();
   BufDir[live]     = (double)g_engine.DirLast();

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

   const int v = g_engine.Verdict();
   if(v == CSI_NONE || v == CSI_NEUTRAL)
      return;
   if(g_alertedAt == barTime)
      return;

   g_alertedAt = barTime;
   const string msg = StringFormat("%s %s  %s | CSI %.1f vs %.1f  CD %.1f  RP %s",
                                   _Symbol, TfName(), CSIVerdictText(v),
                                   g_engine.CSILast(), g_engine.CSIPrev(), g_engine.CD(),
                                   DoubleToString(g_engine.RP(), _Digits));
   if(InpAlertOnSignal)
      Alert(msg);
   if(InpPushOnSignal)
      SendNotification(msg);
  }

//+------------------------------------------------------------------+
color VerdictColor(const int v)
  {
   const int b = CSIVerdictBias(v);
   if(b > 0) return(COL_BULL);
   if(b < 0) return(COL_BEAR);
   return(COL_DIM);
  }

//+------------------------------------------------------------------+
string TfName()
  {
   return(StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7));
  }

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
void PanelLabel(const string key, const int x, const int y, const string text,
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
void DrawPanel(const int rates_total)
  {
   const int x = InpPanelX;
   int y = InpPanelY;

   const string bg = PFX + "bg";
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
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 228);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 214);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, COL_BG);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, COL_EDGE);

   PanelLabel("title", x, y, "CSI-OMEGA  " + _Symbol + " " + TfName(), COL_EDGE, 10, "Consolas");
   y += 20;

   const int liveDir = g_engine.LiveDir();
   PanelLabel("live", x, y, StringFormat("live leg    %-5s  %d bars",
                                         liveDir > 0 ? "UP" : (liveDir < 0 ? "DOWN" : "-"),
                                         MathMax(0, rates_total - 1 - g_engine.LiveStart())),
              COL_DIM, 9, "Consolas");
   y += 16;
   PanelLabel("sep1", x, y, "-- last scored leg ------------", COL_DIM, 8, "Consolas");
   y += 16;

   const int dirLast = g_engine.DirLast();
   const color dirCol = (dirLast > 0) ? COL_BULL : (dirLast < 0 ? COL_BEAR : COL_DIM);
   PanelLabel("dir", x, y, StringFormat("direction   %s",
                                        dirLast > 0 ? "UP" : (dirLast < 0 ? "DOWN" : "-")),
              dirCol, 9, "Consolas");
   y += 16;
   PanelLabel("cns", x, y, StringFormat("CNS         %.1f", g_engine.CNS()), COL_GOLD, 9, "Consolas");
   y += 16;
   PanelLabel("sub", x, y, StringFormat("CS %.0f  SP %.0f  NP %.0f",
                                        g_engine.CS(), g_engine.SP(), g_engine.NP()),
              COL_TEXT, 9, "Consolas");
   y += 16;
   PanelLabel("csi", x, y, StringFormat("CSI (B)     %.1f", g_engine.CSILast()), COL_GOLD, 10, "Consolas");
   y += 18;
   PanelLabel("prev", x, y, StringFormat("CSI (A)     %.1f", g_engine.CSIPrev()), COL_TEXT, 9, "Consolas");
   y += 16;
   PanelLabel("sep2", x, y, "-- fusion ---------------------", COL_DIM, 8, "Consolas");
   y += 16;
   PanelLabel("ratio", x, y, StringFormat("B/A         %.3f", g_engine.Ratio()), COL_TEXT, 9, "Consolas");
   y += 16;
   PanelLabel("cd", x, y, StringFormat("CD          %.1f", g_engine.CD()), COL_EDGE, 10, "Consolas");
   y += 18;

   const int v = g_engine.Verdict();
   PanelLabel("verdict", x, y, CSIVerdictText(v), VerdictColor(v), 10, "Consolas");
   y += 18;
   PanelLabel("rp", x, y, StringFormat("RP  %s", DoubleToString(g_engine.RP(), _Digits)),
              COL_TEXT, 8, "Consolas");
   y += 14;
   PanelLabel("inv", x, y, StringFormat("inv %s", DoubleToString(g_engine.Invalid(), _Digits)),
              COL_DIM, 8, "Consolas");

   ChartRedraw();
  }
//+------------------------------------------------------------------+
