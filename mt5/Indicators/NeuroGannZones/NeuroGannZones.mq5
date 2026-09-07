//+------------------------------------------------------------------+
//|                                              NeuroGannZones.mq5  |
//|            NEURO GANN ZONES - advanced W.D. Gann analysis suite   |
//|                                                                   |
//|  Three independent engines fused into one directional reading:    |
//|    * GANN GEOMETRY : nine ray fan, Square of Nine, eighths and    |
//|                      thirds, time cycles, confluence zones        |
//|    * MATHEMATICS   : least squares regression, R2, Kaufman        |
//|                      efficiency, z-score, Wilder RSI/ATR,         |
//|                      variance ratio, volatility regime,           |
//|                      normalised momentum, directional volume      |
//|    * NEURAL LAYER  : a multilayer perceptron trained by SGD on    |
//|                      closed historical bars only                  |
//|                                                                   |
//|  Output: a coloured trend line, two Gann 1x1 rails (UP / DOWN),   |
//|  buy/sell arrows, filled zones on the candles and a neon HUD.     |
//+------------------------------------------------------------------+
#property copyright "Neuro Gann Zones"
#property version   "1.00"
#property description "Gann geometry + mathematical models + neural network."
#property description "Draws directional zones and up/down lines on the chart."
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   5

//--- plot 1: fused trend line (colour index 0 flat, 1 up, 2 down)
#property indicator_label1  "NeuroGann Trend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrGray,clrLime,clrRed
#property indicator_width1  2

//--- plot 2: Gann 1x1 rail rising from the bull anchor  = the UP line
#property indicator_label2  "Gann UP line 1x1"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_width2  2

//--- plot 3: Gann 1x1 rail falling from the bear anchor = the DOWN line
#property indicator_label3  "Gann DOWN line 1x1"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_width3  2

//--- plot 4/5: confirmed signals
#property indicator_label4  "Buy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  3

#property indicator_label5  "Sell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  3

#include "NGZ_Config.mqh"
#include "NGZ_State.mqh"
#include "NGZ_Math.mqh"
#include "NGZ_Gann.mqh"
#include "NGZ_Neuro.mqh"
#include "NGZ_Draw.mqh"
#include "NGZ_Panel.mqh"

//+------------------------------------------------------------------+
//| BUFFERS                                                          |
//+------------------------------------------------------------------+
double g_trend[];      // 0  fused trend line (price space)
double g_trendClr[];   // 1  colour index of the trend line
double g_up[];         // 2  Gann 1x1 up rail
double g_dn[];         // 3  Gann 1x1 down rail
double g_buy[];        // 4  buy arrows
double g_sell[];       // 5  sell arrows
double g_atr[];        // 6  Wilder ATR          (calculation)
double g_rsi[];        // 7  Wilder RSI          (calculation)
double g_rsiU[];       // 8  RSI average gain    (calculation)
double g_rsiD[];       // 9  RSI average loss    (calculation)
double g_score[];      // 10 fused score [-1,+1] (calculation)

//--- normalised fusion weights
double g_wNeuro = 0.0, g_wMath = 0.0, g_wGann = 0.0;

//--- working copy of the calculation depth: an input can never be clamped
//--- in place, so the validated value lives here and only here is read
int    g_maxBars = 0;

#define NGZ_ARROW_BUY   233
#define NGZ_ARROW_SELL  234

//+------------------------------------------------------------------+
//| CORE - anchor management (non repainting by construction)         |
//+------------------------------------------------------------------+
void NgzSetAnchor(NgzAnchor &a, const bool isLow, const int bar, const datetime t,
                  const double price, const int confirmBar)
  {
   a.valid  = true;
   a.isLow  = isLow;
   a.bar    = bar;
   a.time   = t;
   a.price  = price;
   a.unit   = (g_atr[confirmBar] > 0.0) ? g_atr[confirmBar] * InpAtrFactor : g_s.unit;
   a.broken = false;
  }

//+------------------------------------------------------------------+
//| Update the rolling anchors as they become knowable at bar i.      |
//| A pivot at bar p is only confirmed n bars later, so the anchor    |
//| never appears earlier than the market could have seen it.         |
//+------------------------------------------------------------------+
void NgzUpdateAnchors(const int i, const int rates_total, const datetime &time[],
                      const double &high[], const double &low[])
  {
   int n = NgzIMax(1, InpSwingBars);

   if(InpAnchorMode == NGZ_ANCHOR_MANUAL)
     {
      if(!g_s.bullAnchor.valid && time[i] >= InpManualAnchor)
        {
         NgzSetAnchor(g_s.bullAnchor, true,  i, time[i], low[i],  i);
         NgzSetAnchor(g_s.bearAnchor, false, i, time[i], high[i], i);
        }
      return;
     }

   if(InpAnchorMode == NGZ_ANCHOR_EXTREME)
     {
      int end = i - n;                                  // keep the tail unconfirmed
      if(end < NgzIMax(n, 2)) return;
      int lb = NgzLowestBar(low,  end, InpSwingLookback);
      int hb = NgzHighestBar(high, end, InpSwingLookback);
      if(lb > g_s.bullAnchor.bar) NgzSetAnchor(g_s.bullAnchor, true,  lb, time[lb], low[lb],  i);
      if(hb > g_s.bearAnchor.bar) NgzSetAnchor(g_s.bearAnchor, false, hb, time[hb], high[hb], i);
      return;
     }

   //--- NGZ_ANCHOR_SWING: fractal pivot confirmed n bars after it printed
   int p = i - n;
   if(p < n || p + n >= rates_total) return;

   if(p > g_s.bullAnchor.bar && NgzIsSwingLow(low, p, n, rates_total))
      NgzSetAnchor(g_s.bullAnchor, true, p, time[p], low[p], i);

   if(p > g_s.bearAnchor.bar && NgzIsSwingHigh(high, p, n, rates_total))
      NgzSetAnchor(g_s.bearAnchor, false, p, time[p], high[p], i);
  }

//+------------------------------------------------------------------+
//| CORE - the two 1x1 rails. A rail dies the moment price closes on  |
//| the wrong side of it, exactly as Gann described the 45 degree     |
//| line: while it holds the trend holds.                             |
//+------------------------------------------------------------------+
void NgzComputeRails(const int i, const double &close[], const bool allowBreak)
  {
   g_up[i] = EMPTY_VALUE;
   g_dn[i] = EMPTY_VALUE;

   if(g_s.bullAnchor.valid && !g_s.bullAnchor.broken && i > g_s.bullAnchor.bar &&
      (i - g_s.bullAnchor.bar) <= InpRailBars)
     {
      double v = NgzFanValue(g_s.bullAnchor, NgzAnchorUnit(g_s.bullAnchor), 1.0, i);
      g_up[i] = v;
      //--- an intrabar wick must never kill a rail: only closed bars decide
      if(allowBreak && close[i] < v) g_s.bullAnchor.broken = true;
     }

   if(g_s.bearAnchor.valid && !g_s.bearAnchor.broken && i > g_s.bearAnchor.bar &&
      (i - g_s.bearAnchor.bar) <= InpRailBars)
     {
      double v = NgzFanValue(g_s.bearAnchor, NgzAnchorUnit(g_s.bearAnchor), 1.0, i);
      g_dn[i] = v;
      if(allowBreak && close[i] > v) g_s.bearAnchor.broken = true;
     }
  }

//+------------------------------------------------------------------+
//| CORE - build the feature vector of bar i and cache it             |
//+------------------------------------------------------------------+
void NgzBuildFeatures(const int i, const double &high[], const double &low[],
                      const double &close[], const long &tick_volume[])
  {
   double atr = (g_atr[i] > 0.0) ? g_atr[i] : _Point;

   //--- 1. least squares regression: slope, quality, baseline
   double slope = 0.0, regVal = close[i], r2 = 0.0, sigma = 0.0;
   NgzLinReg(close, i, InpRegPeriod, slope, regVal, r2, sigma);

   double f0 = NgzTanh(slope * (double)InpRegPeriod / atr);          // trend slope
   double f1 = 2.0 * r2 - 1.0;                                       // trend quality
   double f2 = NgzEfficiency(close, i, InpEffPeriod);                // Kaufman ER
   double f3 = NgzTanh(NgzZScore(close, i, InpZPeriod) * 0.5);       // stretch
   double f4 = (g_rsi[i] - 50.0) / 50.0;                             // RSI momentum
   double f5 = NgzTanh(NgzDiv(atr, NgzMean(g_atr, i, InpAtrAvgPeriod), 1.0) - 1.0);
   double f6 = NgzTanh(NgzMomentum(close, g_atr, i, InpMomPeriod));  // normalised ROC
   double f7 = NgzTanh(NgzVarianceRatio(close, i, InpVrPeriod, InpVrLag));

   //--- 2. Gann geometry features
   double f8  = NgzFanScoreBoth(i, close[i]);
   double ref = NgzAnchorRefPrice();
   double f9  = (ref > 0.0) ? NgzSq9Score(ref, close[i]) : 0.0;

   //--- 3. master swing position (premium / discount)
   int    hb  = NgzHighestBar(high, i, InpSwingLookback);
   int    lb  = NgzLowestBar(low,  i, InpSwingLookback);
   double f10 = NgzRangePos(close[i], low[lb], high[hb]);

   //--- 4. directional volume pressure
   double f11 = 0.0;
   if(i >= InpVolPeriod)
     {
      double vSlope = 0.0, vMean = 0.0;
      if(NgzLinRegLong(tick_volume, i, InpVolPeriod, vSlope, vMean))
        {
         double dir = 0.0;
         if(close[i] > close[i - InpVolPeriod])      dir =  1.0;
         else if(close[i] < close[i - InpVolPeriod]) dir = -1.0;
         f11 = NgzTanh(NgzDiv(vSlope * (double)InpVolPeriod, vMean, 0.0)) * dir;
        }
     }

   int b = NgzF(i, 0);
   g_feat[b + 0]  = f0;  g_feat[b + 1]  = f1;  g_feat[b + 2]  = f2;
   g_feat[b + 3]  = f3;  g_feat[b + 4]  = f4;  g_feat[b + 5]  = f5;
   g_feat[b + 6]  = f6;  g_feat[b + 7]  = f7;  g_feat[b + 8]  = f8;
   g_feat[b + 9]  = f9;  g_feat[b + 10] = f10; g_feat[b + 11] = f11;

   //--- transparent mathematical consensus (no black box)
   double mathScore = NgzTanh((NGZ_W_SLOPE   * f0  + NGZ_W_R2      * f1  +
                               NGZ_W_EFF     * f2  + NGZ_W_ZSCORE  * f3  +
                               NGZ_W_RSI     * f4  + NGZ_W_VOLREG  * f5  +
                               NGZ_W_MOM     * f6  + NGZ_W_VR      * f7  +
                               NGZ_W_PREMIUM * f10 + NGZ_W_VOLUME  * f11)
                              / NGZ_W_MATH_NORM);

   g_feat[NgzF(i, NGZ_SLOT_BASE)] = regVal;
   g_feat[NgzF(i, NGZ_SLOT_GANN)] = NgzGannCombine(f8, f9);
   g_feat[NgzF(i, NGZ_SLOT_MATH)] = mathScore;

   //--- keep the master swing of the newest bar for the drawing layer
   g_s.swingLo     = low[lb];
   g_s.swingHi     = high[hb];
   g_s.swingLoBar  = lb;
   g_s.swingHiBar  = hb;
  }

//+------------------------------------------------------------------+
//| CORE - fuse the three engines into one score                      |
//+------------------------------------------------------------------+
double NgzFuse(const double neuro, const double maths, const double gann)
  {
   switch(InpMode)
     {
      case NGZ_MODE_NEURO: return NgzClamp(neuro, -1.0, 1.0);
      case NGZ_MODE_MATH:  return NgzClamp(maths, -1.0, 1.0);
      case NGZ_MODE_GANN:  return NgzClamp(gann,  -1.0, 1.0);
      default: break;
     }
   //--- a disabled or not-yet-trained network must not damp the score:
   //--- drop its weight and renormalise the two that remain
   double wn  = (InpUseNeuro && g_s.netReady) ? g_wNeuro : 0.0;
   double sum = wn + g_wMath + g_wGann;
   if(sum < 1.0e-9) return 0.0;

   return NgzClamp((wn * neuro + g_wMath * maths + g_wGann * gann) / sum, -1.0, 1.0);
  }

//+------------------------------------------------------------------+
//| CORE - train the network on cached features of closed bars        |
//| Target: the forward move over InpHorizon bars, squashed by ATR.   |
//| Only bars whose future is fully known are used, so the training   |
//| set never contains the forming bar.                               |
//+------------------------------------------------------------------+
void NgzTrainNetwork(const int rates_total, const double &close[])
  {
   g_s.netTried = true;

   int last  = rates_total - 2 - InpHorizon;
   int first = NgzIMax(g_s.featBase + g_s.warmup, last - InpTrainBars + 1);
   int n     = last - first + 1;
   if(n < InpMinSamples) return;

   int    offsets[];
   double targets[];
   ArrayResize(offsets, n);
   ArrayResize(targets, n);

   int cnt = 0;
   for(int i = first; i <= last; i++)
     {
      double atr = (g_atr[i] > 0.0) ? g_atr[i] : _Point;
      double fwd = close[i + InpHorizon] - close[i];
      offsets[cnt] = NgzF(i, 0);
      targets[cnt] = NgzTanh(fwd / (atr * InpTargetATR));
      cnt++;
     }

   NgzNetInit(g_net, NGZ_FEATURES, InpHidden, InpNetSeed);
   if(NgzNetTrain(g_net, g_feat, offsets, targets, cnt))
     {
      g_s.netReady = true;
      PrintFormat("NeuroGannZones: network trained on %d samples, loss %.5f, in-sample hit rate %.1f%%",
                  g_net.samples, g_net.loss, g_net.accuracy * 100.0);
     }
  }

//+------------------------------------------------------------------+
//| UI - refresh every chart drawing. Deliberately independent of     |
//| the OnCalculate arrays so a toggle click can redraw instantly.    |
//+------------------------------------------------------------------+
void NgzRefreshVisuals(void)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if(g_s.lastBar < 0 || g_s.lastBarTime == 0) return;

   NgzClearCategory(NGZ_CAT_FAN);
   NgzClearCategory(NGZ_CAT_SQ9);
   NgzClearCategory(NGZ_CAT_DIV);
   NgzClearCategory(NGZ_CAT_CYC);
   NgzClearCategory(NGZ_CAT_ZONE);
   NgzClearCategory(NGZ_CAT_ANC);

   datetime tEnd = NgzTimeAhead(g_s.lastBarTime, NgzIMax(10, InpProjectBars));
   datetime tSt  = g_s.lastBarTime;
   if(g_s.swingLoTime > 0 && g_s.swingHiTime > 0)
      tSt = (g_s.swingLoTime < g_s.swingHiTime) ? g_s.swingLoTime : g_s.swingHiTime;

   double ref = NgzAnchorRefPrice();

   //--- fans and their anchors
   if(g_s.showFan)
     {
      NgzDrawFan(g_s.bullAnchor, "B", g_s.lastBarTime);
      if(InpDualFan) NgzDrawFan(g_s.bearAnchor, "S", g_s.lastBarTime);
     }

   //--- zones
   if(g_s.showZones)
     {
      if(InpShowFanZones)
        {
         NgzDrawFanZones(g_s.bullAnchor, "B", g_s.lastBarTime);
         if(InpDualFan) NgzDrawFanZones(g_s.bearAnchor, "S", g_s.lastBarTime);
        }
      if(InpShowPremium)
         NgzDrawPremiumDiscount(g_s.swingLo, g_s.swingHi, tSt, tEnd);
      if(InpShowConfluence && ref > 0.0)
        {
         if(g_s.bullAnchor.valid &&
            (!g_s.bearAnchor.valid || g_s.bullAnchor.bar >= g_s.bearAnchor.bar))
            NgzDrawConfluence(g_s.bullAnchor, ref, g_s.lastBar, g_s.lastBarTime, g_s.atrNow);
         else
            if(g_s.bearAnchor.valid)
               NgzDrawConfluence(g_s.bearAnchor, ref, g_s.lastBar, g_s.lastBarTime, g_s.atrNow);
        }
      if(InpShowProjection)
         NgzDrawProjection(g_s.lastBarTime, g_s.lastClose, g_s.fused, g_s.unit);
     }

   //--- price geometry
   if(g_s.showSq9 && ref > 0.0)
      NgzDrawSq9(ref, tSt, tEnd);
   if(g_s.showRetrace)
      NgzDrawDivisions(g_s.swingLo, g_s.swingHi, tSt, tEnd);

   //--- time geometry
   if(g_s.showCycles)
     {
      int ahead = NgzIMax(30, InpProjectBars * 2);
      if(g_s.bullAnchor.valid &&
         (!g_s.bearAnchor.valid || g_s.bullAnchor.bar >= g_s.bearAnchor.bar))
         NgzDrawCycles(g_s.bullAnchor, g_s.swingLo, g_s.swingHi,
                       (g_s.lastBar - g_s.bullAnchor.bar) + ahead);
      else
         if(g_s.bearAnchor.valid)
            NgzDrawCycles(g_s.bearAnchor, g_s.swingLo, g_s.swingHi,
                          (g_s.lastBar - g_s.bearAnchor.bar) + ahead);
     }

   g_s.needRedraw  = false;
   g_s.lastDrawBar = g_s.lastBarTime;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| UI - alerting                                                     |
//+------------------------------------------------------------------+
void NgzFireAlert(const int dir, const double price)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;

   bool inCycle = NgzInCycleBand(g_s.bullAnchor, g_s.lastBar) ||
                  NgzInCycleBand(g_s.bearAnchor, g_s.lastBar);

   string msg = StringFormat("NEURO GANN ZONES | %s %s | %s @ %s | score %.1f%% | neuro %.1f%% math %.1f%% gann %.1f%%%s",
                             _Symbol, NgzTfName(), (dir > 0 ? "BUY" : "SELL"),
                             DoubleToString(price, _Digits), g_s.fused * 100.0,
                             g_s.neuro * 100.0, g_s.maths * 100.0, g_s.gann * 100.0,
                             (inCycle ? " | GANN TIME CYCLE ACTIVE" : ""));

   Print(msg);
   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertMail)  SendMail("Neuro Gann Zones signal", msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
  }

//+------------------------------------------------------------------+
//| EVENTS - OnInit                                                   |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   //--- buffers: plotted first, calculations after
   SetIndexBuffer(0,  g_trend,    INDICATOR_DATA);
   SetIndexBuffer(1,  g_trendClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  g_up,       INDICATOR_DATA);
   SetIndexBuffer(3,  g_dn,       INDICATOR_DATA);
   SetIndexBuffer(4,  g_buy,      INDICATOR_DATA);
   SetIndexBuffer(5,  g_sell,     INDICATOR_DATA);
   SetIndexBuffer(6,  g_atr,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,  g_rsi,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  g_rsiU,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  g_rsiD,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, g_score,    INDICATOR_CALCULATIONS);

   //--- theme colours override the #property defaults
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, NGZ_CLR_FLAT);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, NGZ_CLR_UP);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 2, NGZ_CLR_DOWN);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, NGZ_CLR_UP);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, NGZ_CLR_DOWN);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, NGZ_CLR_UP);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, NGZ_CLR_DOWN);
   PlotIndexSetInteger(3, PLOT_ARROW, NGZ_ARROW_BUY);
   PlotIndexSetInteger(4, PLOT_ARROW, NGZ_ARROW_SELL);

   for(int p = 0; p < 5; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetString(0, PLOT_LABEL, "NeuroGann Trend");
   PlotIndexSetString(1, PLOT_LABEL, "Gann UP line 1x1");
   PlotIndexSetString(2, PLOT_LABEL, "Gann DOWN line 1x1");
   PlotIndexSetString(3, PLOT_LABEL, "Buy");
   PlotIndexSetString(4, PLOT_LABEL, "Sell");

   //--- warm-up: the longest window any model needs
   int w = NgzIMax(InpAtrPeriod, InpRsiPeriod);
   w = NgzIMax(w, InpRegPeriod);
   w = NgzIMax(w, InpEffPeriod);
   w = NgzIMax(w, InpZPeriod);
   w = NgzIMax(w, InpMomPeriod);
   w = NgzIMax(w, InpVolPeriod);
   w = NgzIMax(w, InpVrPeriod + InpVrLag);
   w = NgzIMax(w, InpAtrPeriod + InpAtrAvgPeriod);
   w = NgzIMax(w, InpSwingBars * 2);
   w = NgzIMax(w, InpSwingLookback);
   g_s.warmup = w + 5;

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, g_s.warmup);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, g_s.warmup);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, g_s.warmup);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("NeuroGannZones(%s,%d,%d)",
                                   EnumToString(InpMode), InpSwingBars, InpRegPeriod));

   //--- CONFIG -> STATE. Everything the user can toggle at runtime is
   //--- owned by STATE from here on; the inputs are never re-read.
   g_s.showFan     = InpShowFan;
   g_s.showSq9     = InpShowSq9;
   g_s.showZones   = InpShowZones;
   g_s.showCycles  = InpShowCycles;
   g_s.showRetrace = InpShowRetrace;
   g_s.showPanel   = InpShowPanel;
   g_s.collapsed   = false;
   g_s.needRedraw  = true;
   g_s.prefix      = "";
   g_s.dpi         = 0;
   g_s.lastAlertBar = 0;
   g_s.lastAlertDir = 0;
   NgzStateResetHistory();

   //--- fusion weights, normalised so they always sum to one
   double sum = MathAbs(InpWeightNeuro) + MathAbs(InpWeightMath) + MathAbs(InpWeightGann);
   if(sum < 1.0e-9)
     { g_wNeuro = 0.34; g_wMath = 0.33; g_wGann = 0.33; }
   else
     {
      g_wNeuro = MathAbs(InpWeightNeuro) / sum;
      g_wMath  = MathAbs(InpWeightMath)  / sum;
      g_wGann  = MathAbs(InpWeightGann)  / sum;
     }
   if(!InpUseNeuro)                                   // redistribute a disabled engine
     {
      double rest = g_wMath + g_wGann;
      if(rest > 1.0e-9) { g_wMath /= rest; g_wGann /= rest; }
      else              { g_wMath = 0.5;   g_wGann = 0.5;   }
      g_wNeuro = 0.0;
     }

   //--- a scoring window smaller than this cannot host the warm-up
   g_maxBars = (InpMaxBars > 0) ? NgzIMax(InpMaxBars, 200) : 0;

   //--- Gann configuration
   NgzParseCycles(InpCycleList);
   g_s.sq9Scale = NgzSq9Scale();
   NgzNetInit(g_net, NGZ_FEATURES, InpHidden, InpNetSeed);

   //--- optional warm start from a stored brain
   if(InpUseNeuro && InpPersistNet && NgzNetLoad(g_net))
     {
      g_s.netReady = true;
      g_s.netTried = true;
      Print("NeuroGannZones: weights restored from ", NgzNetFileName());
     }

   //--- dashboard
   if(g_s.showPanel)
     {
      NgzPanelCreate();
      ChartRedraw();
     }

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EVENTS - OnDeinit                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpUseNeuro && InpPersistNet && g_s.netReady && reason != REASON_PARAMETERS)
      NgzNetSave(g_net);

   NgzPanelDestroy();
   ObjectsDeleteAll(0, NgzPrefix());
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| EVENTS - OnCalculate                                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < g_s.warmup + InpHorizon + 10) return 0;
   if(rates_total < prev_calculated)              return 0;   // server history switch

   bool firstPass = (prev_calculated == 0);
   int  mathStart = 0;                                         // ATR / RSI recurrences
   int  loopStart = 0;                                         // feature + rail pass

   if(firstPass)
     {
      ArrayInitialize(g_trend,    EMPTY_VALUE);
      ArrayInitialize(g_trendClr, 0.0);
      ArrayInitialize(g_up,       EMPTY_VALUE);
      ArrayInitialize(g_dn,       EMPTY_VALUE);
      ArrayInitialize(g_buy,      EMPTY_VALUE);
      ArrayInitialize(g_sell,     EMPTY_VALUE);
      ArrayInitialize(g_score,    0.0);

      NgzStateResetHistory();

      //--- cache only the window we actually score, but keep its base bar
      //--- fixed for the whole session so cached indices never shift
      g_s.featBase = (g_maxBars > 0 && rates_total > g_maxBars + g_s.warmup)
                     ? rates_total - (g_maxBars + g_s.warmup) : 0;
      if(ArrayResize(g_feat, (rates_total - g_s.featBase) * NGZ_STRIDE,
                     2000 * NGZ_STRIDE) < 0)
         return 0;
      ArrayInitialize(g_feat, 0.0);

      mathStart = 0;
      loopStart = g_s.featBase + g_s.warmup;
     }
   else
     {
      int need = (rates_total - g_s.featBase) * NGZ_STRIDE;
      if(ArraySize(g_feat) < need &&
         ArrayResize(g_feat, need, 2000 * NGZ_STRIDE) < 0) return 0;

      mathStart = prev_calculated - 1;
      loopStart = NgzIMax(prev_calculated - 1, g_s.featBase + g_s.warmup);
     }

   //--- 1. mathematical series that need a recurrence over all history
   NgzCalcATR(rates_total, mathStart, InpAtrPeriod, high, low, close, g_atr);
   NgzCalcRSI(rates_total, mathStart, InpRsiPeriod, close, g_rsiU, g_rsiD, g_rsi);

   //--- 2. the Gann scale for this pass
   g_s.unit     = NgzPriceUnit(rates_total, high, low, g_atr);
   g_s.sq9Scale = NgzSq9Scale();

   //--- 3. pass A: anchors, features, rails (no network involved yet)
   for(int i = loopStart; i < rates_total && !IsStopped(); i++)
     {
      //--- the forming bar may not create anchors nor invalidate rails:
      //--- its high/low/close are still moving
      bool confirmed = (i < rates_total - 1);
      if(confirmed) NgzUpdateAnchors(i, rates_total, time, high, low);
      NgzBuildFeatures(i, high, low, close, tick_volume);
      NgzComputeRails(i, close, confirmed);
     }
   if(IsStopped()) return prev_calculated;

   //--- 4. train once per history, on closed bars only
   bool trainedNow = false;
   if(InpUseNeuro && !g_s.netReady && !g_s.netTried)
     {
      NgzTrainNetwork(rates_total, close);
      trainedNow = g_s.netReady;
     }

   //--- 5. pass B: inference, fusion, trend line, signals
   int scoreStart = trainedNow ? (g_s.featBase + g_s.warmup) : loopStart;
   double hid[NGZ_HIDDEN_MAX];

   for(int i = scoreStart; i < rates_total && !IsStopped(); i++)
     {
      double neuro = 0.0;
      if(InpUseNeuro && g_s.netReady)
         neuro = NgzNetForward(g_net, g_feat, NgzF(i, 0), hid);

      double maths = g_feat[NgzF(i, NGZ_SLOT_MATH)];
      double gann  = g_feat[NgzF(i, NGZ_SLOT_GANN)];
      double fused = NgzFuse(neuro, maths, gann);

      double prev = (i > 0) ? g_score[i - 1] : 0.0;
      g_score[i] = fused;

      //--- trend line: the regression baseline biased by the fused score
      double atr  = (g_atr[i] > 0.0) ? g_atr[i] : _Point;
      g_trend[i]    = g_feat[NgzF(i, NGZ_SLOT_BASE)] + fused * InpTrendAmp * atr;
      g_trendClr[i] = (fused >= InpExitLevel) ? 1.0 : ((fused <= -InpExitLevel) ? 2.0 : 0.0);

      //--- signals: confirmed bars only, never the forming one
      g_buy[i]  = EMPTY_VALUE;
      g_sell[i] = EMPTY_VALUE;
      if(i < rates_total - 1)
        {
         bool up = (fused >=  InpSignalLevel && prev <  InpSignalLevel);
         bool dn = (fused <= -InpSignalLevel && prev > -InpSignalLevel);

         if(InpRequireRail)
           {
            //--- price must sit on the correct side of the live 1x1 rail
            if(up && g_up[i] != EMPTY_VALUE && close[i] < g_up[i]) up = false;
            if(dn && g_dn[i] != EMPTY_VALUE && close[i] > g_dn[i]) dn = false;
           }

         double gap = atr * 0.6;
         if(up) g_buy[i]  = low[i]  - gap;
         if(dn) g_sell[i] = high[i] + gap;
        }
     }
   if(IsStopped()) return prev_calculated;

   //--- 6. publish the newest readings for the UI layers
   int cb = rates_total - 2;                       // last CLOSED bar
   if(cb < 0) cb = 0;

   g_s.lastBar     = rates_total - 1;
   g_s.lastBarTime = time[g_s.lastBar];
   g_s.lastClose   = close[g_s.lastBar];
   g_s.atrNow      = g_atr[g_s.lastBar];
   g_s.prevFused   = (cb > 0) ? g_score[cb - 1] : 0.0;
   g_s.fused       = g_score[cb];
   g_s.maths       = g_feat[NgzF(cb, NGZ_SLOT_MATH)];
   g_s.gann        = g_feat[NgzF(cb, NGZ_SLOT_GANN)];
   g_s.neuro       = (InpUseNeuro && g_s.netReady)
                     ? NgzNetForward(g_net, g_feat, NgzF(cb, 0), hid) : 0.0;
   g_s.bias        = (g_s.fused >= InpExitLevel) ? 1 : ((g_s.fused <= -InpExitLevel) ? -1 : 0);
   g_s.railUp      = (g_up[cb] != EMPTY_VALUE) ? g_up[cb] : 0.0;
   g_s.railDn      = (g_dn[cb] != EMPTY_VALUE) ? g_dn[cb] : 0.0;
   g_s.swingLoTime = (g_s.swingLoBar >= 0) ? time[g_s.swingLoBar] : 0;
   g_s.swingHiTime = (g_s.swingHiBar >= 0) ? time[g_s.swingHiBar] : 0;

   double ref = NgzAnchorRefPrice();
   double sq9Up = 0.0, sq9Dn = 0.0;
   if(ref > 0.0) NgzSq9Nearest(ref, close[cb], sq9Up, sq9Dn);
   g_s.sq9Above = sq9Up;
   g_s.sq9Below = sq9Dn;

   int cycBars = -1, cycLen = 0;
   if(g_s.bullAnchor.valid &&
      (!g_s.bearAnchor.valid || g_s.bullAnchor.bar >= g_s.bearAnchor.bar))
      NgzNextCycle(g_s.bullAnchor, g_s.lastBar, cycBars, cycLen);
   else
      if(g_s.bearAnchor.valid)
         NgzNextCycle(g_s.bearAnchor, g_s.lastBar, cycBars, cycLen);
   g_s.nextCycleBars = cycBars;
   g_s.nextCycleLen  = cycLen;

   //--- 7. alert on a fresh signal of the last closed bar
   if(time[cb] != g_s.lastAlertBar)
     {
      int dir = 0;
      if(g_buy[cb]  != EMPTY_VALUE) dir =  1;
      else
         if(g_sell[cb] != EMPTY_VALUE) dir = -1;

      if(dir != 0)
        {
         g_s.lastAlertBar = time[cb];
         g_s.lastAlertDir = dir;
         if(!firstPass) NgzFireAlert(dir, close[cb]);   // no alert storm on attach
        }
     }

   //--- 8. visuals: only on a new bar, a toggle, or a chart change
   if(g_s.needRedraw || g_s.lastDrawBar != g_s.lastBarTime)
      NgzRefreshVisuals();

   //--- the panel only shows closed-bar readings, so 2-3 refreshes per
   //--- second are plenty and keep the chart thread free
   static ulong lastPanelMs = 0;
   ulong nowMs = GetTickCount64();
   if(g_s.showPanel && (nowMs - lastPanelMs >= 400))
     {
      lastPanelMs = nowMs;
      NgzPanelUpdate(g_s.lastClose);
      ChartRedraw();
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
//| EVENTS - OnChartEvent                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   switch(id)
     {
      case CHARTEVENT_OBJECT_CLICK:
         if(NgzPanelClick(sparam))
           {
            NgzPanelCreate();
            NgzPanelUpdate(g_s.lastClose);
            NgzRefreshVisuals();
           }
         break;

      case CHARTEVENT_CHART_CHANGE:
        {
         //--- CHART_CHANGE also fires on every scroll. Rebuilding the whole
         //--- drawing set that often would be wasteful, so react only to a
         //--- real resize, or to zoom while the geometric scale is in use.
         static long lastW = 0, lastH = 0;
         long w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         long h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         bool resized = (w != lastW || h != lastH);
         lastW = w;
         lastH = h;

         if(InpScaleMode == NGZ_SCALE_CHART)
           {
            double u = NgzChartUnit();
            if(u > 0.0 && MathAbs(u - g_s.unit) > g_s.unit * 0.02)
              {
               g_s.unit = u;                     // zoom changed the 1x1 slope
               g_s.needRedraw = true;
              }
           }

         if(g_s.needRedraw) NgzRefreshVisuals();
         if(g_s.showPanel && resized)
           {
            NgzPanelCreate();                    // re-anchor to the new chart size
            NgzPanelUpdate(g_s.lastClose);
            ChartRedraw();
           }
         break;
        }

      default:
         break;
     }
  }
//+------------------------------------------------------------------+
