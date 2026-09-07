//+------------------------------------------------------------------+
//|                                                     NGZ_Gann.mqh |
//|              Neuro Gann Zones - W.D. Gann geometry engine          |
//|                                                                   |
//|  Implements: price/time unit (the 1x1 scale problem), the nine    |
//|  ray fan, the Square of Nine, Gann's eighths and thirds, the      |
//|  time cycles, and the numeric scores these produce.               |
//+------------------------------------------------------------------+
#ifndef __NGZ_GANN_MQH__
#define __NGZ_GANN_MQH__

#include "NGZ_Config.mqh"
#include "NGZ_State.mqh"
#include "NGZ_Math.mqh"

//+------------------------------------------------------------------+
//| The nine classical Gann ratios.                                   |
//| "1x8" = one price unit per eight time units (shallow),            |
//| "1x1" = perfect balance of price and time (45 degrees),           |
//| "8x1" = eight price units per time unit (near vertical).          |
//+------------------------------------------------------------------+
double g_fanRatio[NGZ_FAN_COUNT] = {0.125, 0.25, 0.3333333333, 0.5, 1.0, 2.0, 3.0, 4.0, 8.0};
string g_fanName [NGZ_FAN_COUNT] = {"1x8", "1x4", "1x3", "1x2", "1x1", "2x1", "3x1", "4x1", "8x1"};

//--- Gann's price divisions: eighths plus the two thirds
#define NGZ_DIV_COUNT 9
double g_divRatio[NGZ_DIV_COUNT] = {0.125, 0.25, 0.3333333333, 0.375, 0.5, 0.625, 0.6666666667, 0.75, 0.875};
string g_divName [NGZ_DIV_COUNT] = {"1/8", "2/8", "1/3", "3/8", "4/8", "5/8", "2/3", "6/8", "7/8"};

//+------------------------------------------------------------------+
//| Geometric angle of a ratio, in degrees, for labelling only.       |
//| Under the chosen unit a 1x1 ray IS 45 degrees by construction.    |
//+------------------------------------------------------------------+
double NgzFanAngle(const double ratio)
  {
   return MathArctan(ratio) * 180.0 / M_PI;
  }

//+------------------------------------------------------------------+
//| Chart-geometry unit: the price move that renders exactly as wide  |
//| as one bar on THIS chart, so the 1x1 ray is a visual 45 degrees.  |
//| Returns 0 when the chart is not measurable (tester without visual |
//| mode, chart not yet laid out).                                    |
//+------------------------------------------------------------------+
double NgzChartUnit(void)
  {
   long   wpx = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   long   hpx = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   long   vb  = ChartGetInteger(0, CHART_VISIBLE_BARS);
   double pmn = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double pmx = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   if(wpx <= 0 || hpx <= 0 || vb <= 0 || pmx <= pmn) return 0.0;

   double pxPerBar   = (double)wpx / (double)vb;
   double pricePerPx = (pmx - pmn) / (double)hpx;
   return pxPerBar * pricePerPx;
  }

//+------------------------------------------------------------------+
//| The price/time unit - how much price one bar of time is worth.    |
//| This single number decides the whole geometry; Gann called it     |
//| "the scale" and considered it the heart of the method.            |
//+------------------------------------------------------------------+
double NgzPriceUnit(const int rates_total, const double &high[], const double &low[],
                    const double &atr[])
  {
   double unit = 0.0;
   int    last = rates_total - 1;

   switch(InpScaleMode)
     {
      case NGZ_SCALE_MANUAL:
         unit = InpManualUnit * _Point;
         break;

      case NGZ_SCALE_RANGE:
        {
         int    look = NgzIMin(InpSwingLookback, rates_total - 1);
         if(look > 5)
           {
            int hb = NgzHighestBar(high, last, look);
            int lb = NgzLowestBar(low,  last, look);
            unit = (high[hb] - low[lb]) / (double)look;
           }
         break;
        }

      case NGZ_SCALE_CHART:
         unit = NgzChartUnit();
         break;

      case NGZ_SCALE_ATR:
      default:
         if(last >= 0 && atr[last] > 0.0) unit = atr[last] * InpAtrFactor;
         break;
     }

   //--- fallback chain: never return a unit of zero, the geometry would collapse
   if(unit <= 0.0 && last >= 0 && atr[last] > 0.0) unit = atr[last] * InpAtrFactor;
   if(unit <= 0.0) unit = 100.0 * _Point;
   return unit;
  }

//+------------------------------------------------------------------+
//| Unit that a given anchor must use.                                |
//| In ATR mode the anchor keeps the unit frozen at confirmation      |
//| time, which is what makes every derived rail non-repainting.      |
//+------------------------------------------------------------------+
double NgzAnchorUnit(const NgzAnchor &a)
  {
   if(InpScaleMode == NGZ_SCALE_ATR && a.unit > 0.0) return a.unit;
   return (g_s.unit > 0.0) ? g_s.unit : a.unit;
  }

//+------------------------------------------------------------------+
//| Price of a fan ray at a given bar index.                          |
//| Bull anchors project upward, bear anchors downward.               |
//+------------------------------------------------------------------+
double NgzFanValue(const NgzAnchor &a, const double unit, const double ratio, const int bar)
  {
   if(!a.valid || bar < a.bar) return 0.0;
   double travel = ratio * unit * (double)(bar - a.bar);
   return a.isLow ? (a.price + travel) : (a.price - travel);
  }

//--- same computation addressed by "bars ahead of the anchor"
double NgzFanValueAhead(const NgzAnchor &a, const double unit, const double ratio, const int barsAhead)
  {
   double travel = ratio * unit * (double)barsAhead;
   return a.isLow ? (a.price + travel) : (a.price - travel);
  }

//+------------------------------------------------------------------+
//| Fan position score in [-1, +1].                                   |
//| Counts how many of the nine rays price has conquered: holding     |
//| above 8x1 from a low is maximum strength, losing the 1x8 is       |
//| maximum weakness.                                                 |
//+------------------------------------------------------------------+
double NgzFanScore(const NgzAnchor &a, const int bar, const double price)
  {
   if(!a.valid || bar <= a.bar) return 0.0;
   double unit = NgzAnchorUnit(a);
   if(unit <= 0.0) return 0.0;

   int held = 0;
   for(int k = 0; k < NGZ_FAN_COUNT; k++)
     {
      double lvl = NgzFanValue(a, unit, g_fanRatio[k], bar);
      if(a.isLow) { if(price >= lvl) held++; }         // above the ray = still bullish
      else        { if(price <= lvl) held++; }         // below the ray = still bearish
     }

   double share = (double)held / (double)NGZ_FAN_COUNT;   // 0 .. 1
   double score = 2.0 * share - 1.0;                      // -1 .. +1
   return a.isLow ? score : -score;                       // bear fan inverts the sign
  }

//+------------------------------------------------------------------+
//| SQUARE OF NINE                                                    |
//| One full 360 degree turn of the wheel adds 'turn' to the square   |
//| root of the price (2.0 = classic wheel, 1.0 = intraday variant).  |
//| Raw FX prices are too small for the wheel, so the price is        |
//| scaled up before the root and scaled back afterwards.             |
//+------------------------------------------------------------------+
double NgzSq9Scale(void)
  {
   if(InpSq9ScaleMode == NGZ_SQ9_MANUAL)
      return (InpSq9ScaleManual > 0.0) ? InpSq9ScaleManual : 1.0;

   double s = MathPow(10.0, (double)_Digits);
   return (s > 0.0) ? s : 1.0;
  }

double NgzSq9Level(const double anchorPrice, const double degrees)
  {
   double scale = (g_s.sq9Scale > 0.0) ? g_s.sq9Scale : 1.0;
   double p     = anchorPrice * scale;
   if(p <= 0.0) return 0.0;

   double root = MathSqrt(p) + InpSq9Turn * (degrees / 360.0);
   if(root <= 0.0) return 0.0;

   return NgzNormPrice((root * root) / scale);
  }

//+------------------------------------------------------------------+
//| Nearest Square of 9 levels bracketing the current price           |
//+------------------------------------------------------------------+
void NgzSq9Nearest(const double anchorPrice, const double price, double &above, double &below)
  {
   above = 0.0;
   below = 0.0;
   if(anchorPrice <= 0.0) return;

   int n = NgzIMin(InpSq9Levels, NGZ_SQ9_MAX);
   for(int k = -n; k <= n; k++)
     {
      double lvl = NgzSq9Level(anchorPrice, InpSq9Step * (double)k);
      if(lvl <= 0.0) continue;
      if(lvl >= price && (above <= 0.0 || lvl < above)) above = lvl;
      if(lvl <= price && (below <= 0.0 || lvl > below)) below = lvl;
     }
  }

//+------------------------------------------------------------------+
//| Square of 9 pressure score in [-1, +1].                           |
//| Positive = far from resistance, close to support (room above).    |
//+------------------------------------------------------------------+
double NgzSq9Score(const double anchorPrice, const double price)
  {
   double above = 0.0, below = 0.0;
   NgzSq9Nearest(anchorPrice, price, above, below);
   if(above <= 0.0 || below <= 0.0) return 0.0;

   double dUp = above - price;
   double dDn = price - below;
   double sum = dUp + dDn;
   if(sum <= 1.0e-12) return 0.0;

   return NgzClamp((dUp - dDn) / sum, -1.0, 1.0);
  }

//+------------------------------------------------------------------+
//| GANN DIVISIONS - eighths and thirds of the master swing           |
//+------------------------------------------------------------------+
double NgzDivisionLevel(const double lo, const double hi, const double ratio, const bool fromHigh)
  {
   double range = hi - lo;
   return fromHigh ? (hi - range * ratio) : (lo + range * ratio);
  }

//+------------------------------------------------------------------+
//| TIME CYCLES - parse the user's list of Gann numbers               |
//+------------------------------------------------------------------+
void NgzParseCycles(const string list)
  {
   ArrayResize(g_cycles, NGZ_CYCLE_MAX);
   g_cycleCount = 0;

   string parts[];
   int n = StringSplit(list, StringGetCharacter(",", 0), parts);
   for(int k = 0; k < n && g_cycleCount < NGZ_CYCLE_MAX; k++)
     {
      string one = parts[k];
      StringTrimLeft(one);                    // modifies in place, returns a count
      StringTrimRight(one);
      if(StringLen(one) == 0) continue;
      int v = (int)StringToInteger(one);
      if(v > 0) { g_cycles[g_cycleCount] = v; g_cycleCount++; }
     }

   ArrayResize(g_cycles, NgzIMax(g_cycleCount, 1));
   if(g_cycleCount == 0) { g_cycles[0] = 90; g_cycleCount = 1; }   // safe default
  }

//+------------------------------------------------------------------+
//| Distance in bars to the next Gann time cycle of the given anchor  |
//+------------------------------------------------------------------+
void NgzNextCycle(const NgzAnchor &a, const int bar, int &barsAway, int &cycleLen)
  {
   barsAway = -1;
   cycleLen = 0;
   if(!a.valid || g_cycleCount <= 0) return;

   int elapsed = bar - a.bar;
   if(elapsed < 0) return;

   for(int k = 0; k < g_cycleCount; k++)
     {
      int len = g_cycles[k];
      if(len <= 0) continue;
      //--- first multiple of this cycle that still lies ahead
      int mult = elapsed / len + 1;
      int away = mult * len - elapsed;
      if(barsAway < 0 || away < barsAway) { barsAway = away; cycleLen = len; }
     }
  }

//+------------------------------------------------------------------+
//| True when the bar sits inside a cycle band of the anchor          |
//+------------------------------------------------------------------+
bool NgzInCycleBand(const NgzAnchor &a, const int bar)
  {
   if(!a.valid || g_cycleCount <= 0) return false;
   int elapsed = bar - a.bar;
   if(elapsed <= 0) return false;

   int band = NgzIMax(0, InpCycleBand);
   for(int k = 0; k < g_cycleCount; k++)
     {
      int len = g_cycles[k];
      if(len <= 0) continue;
      int rem = elapsed % len;
      if(rem <= band || rem >= len - band) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Fan score of BOTH anchors averaged - the geometric consensus      |
//+------------------------------------------------------------------+
double NgzFanScoreBoth(const int bar, const double price)
  {
   double sum  = 0.0;
   int    used = 0;

   if(g_s.bullAnchor.valid && bar > g_s.bullAnchor.bar)
     { sum += NgzFanScore(g_s.bullAnchor, bar, price); used++; }
   if(g_s.bearAnchor.valid && bar > g_s.bearAnchor.bar)
     { sum += NgzFanScore(g_s.bearAnchor, bar, price); used++; }

   return (used > 0) ? (sum / (double)used) : 0.0;
  }

//+------------------------------------------------------------------+
//| Reference price for the Square of 9: the most recent anchor       |
//+------------------------------------------------------------------+
double NgzAnchorRefPrice(void)
  {
   if(g_s.bullAnchor.valid && g_s.bearAnchor.valid)
      return (g_s.bullAnchor.bar > g_s.bearAnchor.bar) ? g_s.bullAnchor.price : g_s.bearAnchor.price;
   if(g_s.bullAnchor.valid) return g_s.bullAnchor.price;
   if(g_s.bearAnchor.valid) return g_s.bearAnchor.price;
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Combine the two geometric readings into one score in [-1, +1]     |
//+------------------------------------------------------------------+
double NgzGannCombine(const double fanScore, const double sq9Score)
  {
   return NgzTanh((NGZ_W_GANN_FAN * fanScore + NGZ_W_GANN_SQ9 * sq9Score) / NGZ_W_GANN_NORM);
  }

#endif // __NGZ_GANN_MQH__
//+------------------------------------------------------------------+
