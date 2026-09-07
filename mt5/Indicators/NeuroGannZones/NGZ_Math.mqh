//+------------------------------------------------------------------+
//|                                                     NGZ_Math.mqh |
//|            Neuro Gann Zones - mathematical methods library        |
//|                                                                   |
//|  Self-contained: no indicator handles, no CopyBuffer, no series   |
//|  alignment traps. Every routine works on the raw OnCalculate      |
//|  arrays with the default non-series indexing (0 = oldest bar).    |
//+------------------------------------------------------------------+
#ifndef __NGZ_MATH_MQH__
#define __NGZ_MATH_MQH__

//+------------------------------------------------------------------+
//| 1. Scalar helpers                                                 |
//+------------------------------------------------------------------+
int NgzIMax(const int a, const int b) { return (a > b) ? a : b; }
int NgzIMin(const int a, const int b) { return (a < b) ? a : b; }

double NgzClamp(const double v, const double lo, const double hi)
  {
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
  }

//--- protected division: never divides by (almost) zero
double NgzDiv(const double a, const double b, const double fallback = 0.0)
  {
   if(MathAbs(b) < 1.0e-12) return fallback;
   return a / b;
  }

//--- own hyperbolic tangent: squashes any real number into (-1, +1)
double NgzTanh(const double x)
  {
   double z = NgzClamp(x, -20.0, 20.0);
   double e = MathExp(2.0 * z);
   return (e - 1.0) / (e + 1.0);
  }

//--- derivative of tanh expressed through its own output
double NgzTanhD(const double y) { return 1.0 - y * y; }

//+------------------------------------------------------------------+
//| 2. Wilder ATR - incremental recurrence, one pass over history     |
//|    tr is computed inline; only the smoothed value is stored.      |
//+------------------------------------------------------------------+
void NgzCalcATR(const int rates_total, const int start, const int period,
                const double &high[], const double &low[], const double &close[],
                double &atr[])
  {
   if(period < 1 || rates_total < 2) return;

   int i = start;
   if(i < 1)
     {
      atr[0] = high[0] - low[0];
      i = 1;
     }

   for(; i < rates_total; i++)
     {
      double pc = close[i - 1];
      double tr = MathMax(high[i], pc) - MathMin(low[i], pc);

      if(i < period)                                   // warm-up: running sum
         atr[i] = atr[i - 1] + tr;
      else
         if(i == period)                               // seed: simple average
            atr[i] = (atr[i - 1] + tr) / (double)period;
         else                                          // Wilder smoothing
            atr[i] = (atr[i - 1] * (period - 1) + tr) / (double)period;
     }
  }

//+------------------------------------------------------------------+
//| 3. Wilder RSI - incremental recurrence with persistent averages   |
//+------------------------------------------------------------------+
void NgzCalcRSI(const int rates_total, const int start, const int period,
                const double &close[],
                double &avgU[], double &avgD[], double &rsi[])
  {
   if(period < 1 || rates_total < 2) return;

   int i = start;
   if(i < 1)
     {
      avgU[0] = 0.0;
      avgD[0] = 0.0;
      rsi[0]  = 50.0;
      i = 1;
     }

   for(; i < rates_total; i++)
     {
      double d  = close[i] - close[i - 1];
      double up = (d > 0.0) ?  d : 0.0;
      double dn = (d < 0.0) ? -d : 0.0;

      if(i < period)                                   // warm-up: running sums
        {
         avgU[i] = avgU[i - 1] + up;
         avgD[i] = avgD[i - 1] + dn;
         rsi[i]  = 50.0;
         continue;
        }

      if(i == period)                                  // seed: simple averages
        {
         avgU[i] = (avgU[i - 1] + up) / (double)period;
         avgD[i] = (avgD[i - 1] + dn) / (double)period;
        }
      else                                             // Wilder smoothing
        {
         avgU[i] = (avgU[i - 1] * (period - 1) + up) / (double)period;
         avgD[i] = (avgD[i - 1] * (period - 1) + dn) / (double)period;
        }

      if(avgD[i] <= 1.0e-12)
         rsi[i] = (avgU[i] <= 1.0e-12) ? 50.0 : 100.0;
      else
         rsi[i] = 100.0 - 100.0 / (1.0 + avgU[i] / avgD[i]);
     }
  }

//+------------------------------------------------------------------+
//| 4. Least-squares linear regression over the window ending at i    |
//|    Returns slope (price per bar), the fitted value at bar i,      |
//|    the coefficient of determination R2 and the residual sigma.    |
//+------------------------------------------------------------------+
bool NgzLinReg(const double &src[], const int i, const int period,
               double &slope, double &value, double &r2, double &sigma)
  {
   slope = 0.0; value = 0.0; r2 = 0.0; sigma = 0.0;
   if(period < 3 || i < period - 1) return false;

   int    first = i - period + 1;
   double n     = (double)period;
   double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0;

   for(int k = 0; k < period; k++)
     {
      double x = (double)k;
      double y = src[first + k];
      sx  += x;
      sy  += y;
      sxx += x * x;
      sxy += x * y;
      syy += y * y;
     }

   double den = n * sxx - sx * sx;
   if(MathAbs(den) < 1.0e-12) return false;

   slope = (n * sxy - sx * sy) / den;
   double intercept = (sy - slope * sx) / n;
   value = intercept + slope * (n - 1.0);              // fitted value at bar i

   double ssRes = 0.0;
   for(int k = 0; k < period; k++)
     {
      double f = intercept + slope * (double)k;
      double e = src[first + k] - f;
      ssRes += e * e;
     }
   double ssTot = syy - sy * sy / n;

   r2    = (ssTot > 1.0e-12) ? NgzClamp(1.0 - ssRes / ssTot, 0.0, 1.0) : 0.0;
   sigma = MathSqrt(ssRes / n);
   return true;
  }

//--- regression on a long series (tick volume) without an extra copy
bool NgzLinRegLong(const long &src[], const int i, const int period, double &slope, double &mean)
  {
   slope = 0.0; mean = 0.0;
   if(period < 3 || i < period - 1) return false;

   int    first = i - period + 1;
   double n = (double)period;
   double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;

   for(int k = 0; k < period; k++)
     {
      double x = (double)k;
      double y = (double)src[first + k];
      sx += x; sy += y; sxx += x * x; sxy += x * y;
     }

   double den = n * sxx - sx * sx;
   if(MathAbs(den) < 1.0e-12) return false;

   slope = (n * sxy - sx * sy) / den;
   mean  = sy / n;
   return true;
  }

//+------------------------------------------------------------------+
//| 5. Kaufman efficiency ratio - signed, already inside [-1, +1]     |
//|    net directional travel divided by total path length            |
//+------------------------------------------------------------------+
double NgzEfficiency(const double &src[], const int i, const int period)
  {
   if(period < 2 || i < period) return 0.0;

   double net  = src[i] - src[i - period];
   double path = 0.0;
   for(int k = 0; k < period; k++)
      path += MathAbs(src[i - k] - src[i - k - 1]);

   return NgzClamp(NgzDiv(net, path, 0.0), -1.0, 1.0);
  }

//+------------------------------------------------------------------+
//| 6. Z-score of the last value against its own window               |
//+------------------------------------------------------------------+
double NgzZScore(const double &src[], const int i, const int period)
  {
   if(period < 3 || i < period - 1) return 0.0;

   int    first = i - period + 1;
   double n = (double)period;
   double sum = 0.0, sum2 = 0.0;

   for(int k = 0; k < period; k++)
     {
      double v = src[first + k];
      sum  += v;
      sum2 += v * v;
     }

   double mean = sum / n;
   double var  = sum2 / n - mean * mean;
   if(var <= 1.0e-14) return 0.0;

   return (src[i] - mean) / MathSqrt(var);
  }

//+------------------------------------------------------------------+
//| 7. Variance ratio - Lo/MacKinlay style persistence measure        |
//|    VR > 1 trending (persistent), VR < 1 mean reverting.           |
//|    Returned already centred: VR - 1.                              |
//+------------------------------------------------------------------+
double NgzVarianceRatio(const double &src[], const int i, const int period, const int lag)
  {
   if(lag < 2 || period < lag * 3 || i < period + lag) return 0.0;

   //--- variance of 1-bar changes
   double s1 = 0.0, s1sq = 0.0;
   for(int k = 0; k < period; k++)
     {
      double d = src[i - k] - src[i - k - 1];
      s1 += d; s1sq += d * d;
     }
   double n1  = (double)period;
   double m1  = s1 / n1;
   double v1  = s1sq / n1 - m1 * m1;
   if(v1 <= 1.0e-16) return 0.0;

   //--- variance of lag-bar changes over the same span
   int    cnt = period / lag;
   if(cnt < 3) return 0.0;
   double sk = 0.0, sksq = 0.0;
   for(int k = 0; k < cnt; k++)
     {
      double d = src[i - k * lag] - src[i - (k + 1) * lag];
      sk += d; sksq += d * d;
     }
   double nk = (double)cnt;
   double mk = sk / nk;
   double vk = sksq / nk - mk * mk;

   double vr = NgzDiv(vk, v1 * (double)lag, 1.0);
   return NgzClamp(vr - 1.0, -1.0, 3.0);
  }

//+------------------------------------------------------------------+
//| 8. Momentum normalised by volatility (unit-free rate of change)   |
//+------------------------------------------------------------------+
double NgzMomentum(const double &src[], const double &atr[], const int i, const int period)
  {
   if(period < 1 || i < period) return 0.0;
   double scale = atr[i] * MathSqrt((double)period);
   return NgzDiv(src[i] - src[i - period], scale, 0.0);
  }

//+------------------------------------------------------------------+
//| 9. Simple mean of a window (used for the volatility regime)       |
//+------------------------------------------------------------------+
double NgzMean(const double &src[], const int i, const int period)
  {
   if(period < 1 || i < period - 1) return 0.0;
   double sum = 0.0;
   for(int k = 0; k < period; k++) sum += src[i - k];
   return sum / (double)period;
  }

//+------------------------------------------------------------------+
//| 10. Swing (fractal) pivot detection - N bars on each side         |
//|     A pivot at bar i is only knowable at bar i + N -> the caller  |
//|     must respect that delay to stay non-repainting.               |
//+------------------------------------------------------------------+
bool NgzIsSwingHigh(const double &high[], const int i, const int n, const int total)
  {
   if(n < 1 || i < n || i + n >= total) return false;
   double h = high[i];
   for(int k = i - n; k <= i + n; k++)
      if(k != i && high[k] >= h) return false;
   return true;
  }

bool NgzIsSwingLow(const double &low[], const int i, const int n, const int total)
  {
   if(n < 1 || i < n || i + n >= total) return false;
   double l = low[i];
   for(int k = i - n; k <= i + n; k++)
      if(k != i && low[k] <= l) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| 11. Highest / lowest of a backward window (index returned)        |
//+------------------------------------------------------------------+
int NgzHighestBar(const double &high[], const int i, const int period)
  {
   int first = NgzIMax(0, i - period + 1);
   int best  = first;
   for(int k = first; k <= i; k++)
      if(high[k] > high[best]) best = k;
   return best;
  }

int NgzLowestBar(const double &low[], const int i, const int period)
  {
   int first = NgzIMax(0, i - period + 1);
   int best  = first;
   for(int k = first; k <= i; k++)
      if(low[k] < low[best]) best = k;
   return best;
  }

//+------------------------------------------------------------------+
//| 12. Price normalisation helpers                                   |
//+------------------------------------------------------------------+
//--- round a price to the instrument tick size (NormalizeDouble is not
//--- enough where tick size differs from point, e.g. some indices)
double NgzNormPrice(const double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
  }

//--- position of 'price' inside [lo, hi] mapped to [-1, +1]
double NgzRangePos(const double price, const double lo, const double hi)
  {
   if(hi - lo <= 1.0e-12) return 0.0;
   return NgzClamp(2.0 * (price - lo) / (hi - lo) - 1.0, -1.0, 1.0);
  }

#endif // __NGZ_MATH_MQH__
//+------------------------------------------------------------------+
