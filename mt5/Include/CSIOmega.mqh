//+------------------------------------------------------------------+
//|                                                     CSIOmega.mqh |
//|   CSI-Omega scoring engine - the single source of the formula    |
//+------------------------------------------------------------------+
//
// Every consumer of the model (the reference indicator, the signal system,
// any EA) includes this file. The formula is defined once here so a change
// to the scoring cannot silently apply to one surface and not another.
//
// The derivation and the calibration are in docs/CSI-MODEL.md.
//
//      Candle pattern -> Vi -> CNSn -> CS,SP,NP -> CSI -> CD -> verdict
//
#property copyright "Trading Signals Platform"
#property strict

#define CSI_NONE          0
#define CSI_NEUTRAL       1
#define CSI_CONT_UP       2
#define CSI_CONT_DOWN     3
#define CSI_REVERSAL_UP   4
#define CSI_REVERSAL_DOWN 5

//+------------------------------------------------------------------+
//| Every tunable in the model. Defaults are the calibrated set -     |
//| see docs/CSI-MODEL.md before changing one.                        |
//+------------------------------------------------------------------+
struct CSISettings
  {
   double            devMultiplier;      // swing confirmed after N x ATR retrace
   double            bodyMarubozu;       // body/range thresholds
   double            bodyStrong;
   double            bodyStandard;
   double            bodyWeak;
   double            scoreMarubozu;      // Vi magnitude per class
   double            scoreStrong;
   double            scoreStandard;
   double            scoreWeak;
   double            wickThreshold;      // wick/range that counts as rejection
   double            wickBonus;
   bool              counterNegative;    // counter-direction candles subtract
   double            csAlpha;            // CS sigmoid gain
   double            csMu;               // CS sigmoid midpoint
   double            spReference;        // efficiency ratio scoring SP = 100
   double            npAtrSpan;          // displacement in ATR for NP saturation
   double            weightCS;           // the 0.5 / 0.3 / 0.2 collapse
   double            weightSP;
   double            weightNP;
   double            reversalRatio;      // B/A at or above this = reversal
   double            continuationRatio;  // B/A at or below this = continuation
   double            minCD;              // below this fused score, no verdict
  };

//+------------------------------------------------------------------+
void CSIDefaults(CSISettings &s)
  {
   s.devMultiplier     = 2.0;
   s.bodyMarubozu      = 0.80;
   s.bodyStrong        = 0.60;
   s.bodyStandard      = 0.40;
   s.bodyWeak          = 0.20;
   s.scoreMarubozu     = 4.0;
   s.scoreStrong       = 3.0;
   s.scoreStandard     = 2.0;
   s.scoreWeak         = 1.0;
   s.wickThreshold     = 0.50;
   s.wickBonus         = 1.0;
   s.counterNegative   = true;
   s.csAlpha           = 3.0;
   s.csMu              = 0.0;
   s.spReference       = 0.60;
   s.npAtrSpan         = 8.0;
   s.weightCS          = 0.5;
   s.weightSP          = 0.3;
   s.weightNP          = 0.2;
   s.reversalRatio     = 1.10;
   s.continuationRatio = 0.75;
   s.minCD             = 45.0;
  }

//+------------------------------------------------------------------+
//| One scored leg.                                                  |
//+------------------------------------------------------------------+
struct CSILeg
  {
   int               startIdx;
   int               endIdx;
   int               dir;           // +1 up leg, -1 down leg
   datetime          endTime;
   double            pivotPrice;    // the swing that terminated the leg (RP)
   double            invalidPrice;  // the swing that opened it
   double            cns;
   double            cs;
   double            sp;
   double            np;
   double            csi;
   int               verdict;       // verdict formed when this leg closed
   double            cd;
   double            ratio;
  };

//+------------------------------------------------------------------+
//| Vi - the score a single candle contributes to its leg.           |
//|                                                                  |
//| Scored by class, not counted as one unit, and signed by          |
//| agreement with the leg. The signing is what keeps CNS a *net*    |
//| score and is why a 68-bar leg totals ~32 rather than ~68.        |
//+------------------------------------------------------------------+
double CSICandleValue(const CSISettings &s, const double o, const double h,
                      const double l, const double c, const int legDir)
  {
   const double range = h - l;
   if(range <= 0.0)
      return(0.0);

   const double bodyRatio = MathAbs(c - o) / range;

   double magnitude = 0.0;
   if(bodyRatio >= s.bodyMarubozu)      magnitude = s.scoreMarubozu;
   else if(bodyRatio >= s.bodyStrong)   magnitude = s.scoreStrong;
   else if(bodyRatio >= s.bodyStandard) magnitude = s.scoreStandard;
   else if(bodyRatio >= s.bodyWeak)     magnitude = s.scoreWeak;
   // below bodyWeak the candle is a doji: indecision scores nothing.

   int candleDir = 0;
   if(c > o)      candleDir = 1;
   else if(c < o) candleDir = -1;

   double value = 0.0;
   if(candleDir == legDir)
      value = magnitude;
   else if(candleDir != 0)
      value = s.counterNegative ? -magnitude : 0.0;

   // A long wick against the leg direction is a rejection in its favour.
   const double bodyTop = MathMax(o, c);
   const double bodyBot = MathMin(o, c);
   if(legDir > 0 && (bodyBot - l) / range >= s.wickThreshold)
      value += s.wickBonus;
   else if(legDir < 0 && (h - bodyTop) / range >= s.wickThreshold)
      value += s.wickBonus;

   return(value);
  }

//+------------------------------------------------------------------+
//| CS - net score per bar through a bounded sigmoid, so a long limp |
//| leg cannot out-score a short decisive one on bar count alone.    |
//+------------------------------------------------------------------+
double CSIScoreCS(const CSISettings &s, const double cns, const int bars)
  {
   if(bars <= 0)
      return(0.0);
   return(100.0 / (1.0 + MathExp(-s.csAlpha * ((cns / (double)bars) - s.csMu))));
  }

//+------------------------------------------------------------------+
//| SP - Kaufman efficiency ratio: displacement over distance        |
//| actually travelled. A leg that grinds to the same target scores  |
//| lower than one that goes straight there.                         |
//+------------------------------------------------------------------+
double CSIScoreSP(const CSISettings &s, const double displacement, const double path)
  {
   if(path <= 0.0 || s.spReference <= 0.0)
      return(0.0);
   return(100.0 * MathMin(1.0, (MathAbs(displacement) / path) / s.spReference));
  }

//+------------------------------------------------------------------+
//| NP - displacement in ATR units, saturating, so the score is      |
//| comparable across symbols and volatility regimes.                |
//+------------------------------------------------------------------+
double CSIScoreNP(const CSISettings &s, const double displacement, const double atr)
  {
   if(atr <= 0.0 || s.npAtrSpan <= 0.0)
      return(0.0);
   return(100.0 * (1.0 - MathExp(-MathAbs(displacement) / (s.npAtrSpan * atr))));
  }

//+------------------------------------------------------------------+
//| CD - fusion of two consecutive opposing legs.                    |
//|                                                                  |
//| Geometric mean (both legs must be strong) scaled by a quadratic  |
//| penalty on the *relative* gap, which bounds the result to 0..100 |
//| for every input pair. docs/CSI-MODEL.md §5 records why the       |
//| absolute-gap form in the source material cannot be used.         |
//+------------------------------------------------------------------+
double CSIFuseCD(const double a, const double b)
  {
   if(a <= 0.0 || b <= 0.0)
      return(0.0);
   const double rel = MathAbs(a - b) / (a + b);
   return(MathSqrt(a * b) * (1.0 - rel * rel));
  }

//+------------------------------------------------------------------+
string CSIVerdictText(const int v)
  {
   switch(v)
     {
      case CSI_CONT_UP:        return("CONTINUATION UP");
      case CSI_CONT_DOWN:      return("CONTINUATION DOWN");
      case CSI_REVERSAL_UP:    return("REVERSAL UP");
      case CSI_REVERSAL_DOWN:  return("REVERSAL DOWN");
      case CSI_NEUTRAL:        return("NEUTRAL");
     }
   return("-");
  }

//+------------------------------------------------------------------+
//| +1 for a verdict that wants long, -1 short, 0 for no trade.      |
//+------------------------------------------------------------------+
int CSIVerdictBias(const int v)
  {
   if(v == CSI_CONT_UP || v == CSI_REVERSAL_UP)     return(1);
   if(v == CSI_CONT_DOWN || v == CSI_REVERSAL_DOWN) return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| The leg engine: swing detection, scoring, and the rolling        |
//| two-leg verdict. Fed one bar at a time, in order.                |
//+------------------------------------------------------------------+
class CCSIEngine
  {
private:
   CSISettings       m_s;
   //--- swing tracker
   int               m_dir;
   int               m_extIdx;
   int               m_legStart;
   double            m_extPrice;
   bool              m_seeded;
   //--- rolling results
   double            m_csiPrev;
   double            m_csiLast;
   int               m_dirLast;
   double            m_cns, m_cs, m_sp, m_np;
   double            m_cd, m_ratio;
   int               m_verdict;
   double            m_rp, m_invalid;
   int               m_legs;

public:
                     CCSIEngine(void) { CSIDefaults(m_s); Reset(); }

   void              Configure(const CSISettings &s) { m_s = s; }
   void              Settings(CSISettings &out) const { out = m_s; }

   void Reset(void)
     {
      m_dir = 0; m_extIdx = 0; m_legStart = 0; m_extPrice = 0.0; m_seeded = false;
      m_csiPrev = 0.0; m_csiLast = 0.0; m_dirLast = 0;
      m_cns = 0.0; m_cs = 0.0; m_sp = 0.0; m_np = 0.0;
      m_cd = 0.0; m_ratio = 0.0; m_verdict = CSI_NONE;
      m_rp = 0.0; m_invalid = 0.0; m_legs = 0;
     }

   //--- state readers
   double            CSIPrev(void)  const { return(m_csiPrev); }
   double            CSILast(void)  const { return(m_csiLast); }
   int               DirLast(void)  const { return(m_dirLast); }
   double            CNS(void)      const { return(m_cns); }
   double            CS(void)       const { return(m_cs); }
   double            SP(void)       const { return(m_sp); }
   double            NP(void)       const { return(m_np); }
   double            CD(void)       const { return(m_cd); }
   double            Ratio(void)    const { return(m_ratio); }
   int               Verdict(void)  const { return(m_verdict); }
   double            RP(void)       const { return(m_rp); }
   double            Invalid(void)  const { return(m_invalid); }
   int               LegsScored(void) const { return(m_legs); }
   int               LiveDir(void)  const { return(m_dir); }
   int               LiveStart(void) const { return(m_legStart); }

   //+---------------------------------------------------------------+
   //| Start tracking at a known bar. Call once before the first Feed.|
   //+---------------------------------------------------------------+
   void Seed(const int idx, const double high)
     {
      m_dir      = 1;
      m_extPrice = high;
      m_extIdx   = idx;
      m_legStart = idx;
      m_seeded   = true;
     }

   //+---------------------------------------------------------------+
   //| Feed bar i. Returns true when a leg terminated and was scored, |
   //| filling `out`. Arrays are non-series (index 0 = oldest).       |
   //+---------------------------------------------------------------+
   bool Feed(const int i, const datetime &time[], const double &open[],
             const double &high[], const double &low[], const double &close[],
             const double &atr[], const int atrCount, CSILeg &out)
     {
      if(!m_seeded)
        {
         Seed(i, high[i]);
         return(false);
        }

      const double dev = ((i < atrCount) ? atr[i] : 0.0) * m_s.devMultiplier;
      if(dev <= 0.0)
         return(false);

      bool closed = false;

      if(m_dir > 0)
        {
         if(high[i] > m_extPrice)
           {
            m_extPrice = high[i];
            m_extIdx   = i;
           }
         else if(m_extPrice - low[i] >= dev)
           {
            closed = ScoreLeg(m_legStart, m_extIdx, 1, time, open, high, low, close, atr, atrCount, out);
            m_legStart = m_extIdx;
            m_dir      = -1;
            m_extPrice = low[i];
            m_extIdx   = i;
           }
        }
      else
        {
         if(low[i] < m_extPrice)
           {
            m_extPrice = low[i];
            m_extIdx   = i;
           }
         else if(high[i] - m_extPrice >= dev)
           {
            closed = ScoreLeg(m_legStart, m_extIdx, -1, time, open, high, low, close, atr, atrCount, out);
            m_legStart = m_extIdx;
            m_dir      = 1;
            m_extPrice = high[i];
            m_extIdx   = i;
           }
        }

      return(closed);
     }

private:
   //+---------------------------------------------------------------+
   //| Score one completed leg and fold it into the two-leg verdict.  |
   //+---------------------------------------------------------------+
   bool ScoreLeg(const int startIdx, const int endIdx, const int dir,
                 const datetime &time[], const double &open[], const double &high[],
                 const double &low[], const double &close[],
                 const double &atr[], const int atrCount, CSILeg &out)
     {
      const int bars = endIdx - startIdx;
      if(bars < 2)
         return(false);

      double cns = 0.0, path = 0.0;
      for(int k = startIdx + 1; k <= endIdx; k++)
        {
         cns  += CSICandleValue(m_s, open[k], high[k], low[k], close[k], dir);
         path += MathAbs(close[k] - close[k - 1]);
        }

      const double displacement = close[endIdx] - close[startIdx];
      const double atrHere = (endIdx < atrCount && atr[endIdx] > 0.0) ? atr[endIdx] : 0.0;

      const double cs  = CSIScoreCS(m_s, cns, bars);
      const double sp  = CSIScoreSP(m_s, displacement, path);
      const double np  = CSIScoreNP(m_s, displacement, atrHere);
      const double csi = m_s.weightCS * cs + m_s.weightSP * sp + m_s.weightNP * np;

      // Roll the window: this leg becomes B, the one before it A.
      m_csiPrev = m_csiLast;
      m_csiLast = csi;
      m_dirLast = dir;
      m_cns = cns; m_cs = cs; m_sp = sp; m_np = np;
      m_legs++;

      m_cd = 0.0; m_ratio = 0.0; m_verdict = CSI_NONE;

      if(m_legs >= 2 && m_csiPrev > 0.0)
        {
         m_cd    = CSIFuseCD(m_csiPrev, m_csiLast);
         m_ratio = m_csiLast / m_csiPrev;

         // A counter-leg that matches the impulse it answers has taken
         // control - a reversal. One far below it was only a pullback.
         if(m_ratio >= m_s.reversalRatio)
            m_verdict = (dir > 0) ? CSI_REVERSAL_UP : CSI_REVERSAL_DOWN;
         else if(m_ratio <= m_s.continuationRatio)
            m_verdict = (dir > 0) ? CSI_CONT_DOWN : CSI_CONT_UP;
         else
            m_verdict = CSI_NEUTRAL;

         if(m_cd < m_s.minCD)
            m_verdict = CSI_NEUTRAL;
        }

      m_rp      = (dir > 0) ? high[endIdx] : low[endIdx];
      m_invalid = (dir > 0) ? low[startIdx] : high[startIdx];

      out.startIdx     = startIdx;
      out.endIdx       = endIdx;
      out.dir          = dir;
      out.endTime      = time[endIdx];
      out.pivotPrice   = m_rp;
      out.invalidPrice = m_invalid;
      out.cns          = cns;
      out.cs           = cs;
      out.sp           = sp;
      out.np           = np;
      out.csi          = csi;
      out.verdict      = m_verdict;
      out.cd           = m_cd;
      out.ratio        = m_ratio;
      return(true);
     }
  };
//+------------------------------------------------------------------+
