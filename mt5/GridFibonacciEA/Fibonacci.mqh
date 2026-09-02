//+------------------------------------------------------------------+
//|                                                    Fibonacci.mqh |
//|  CORE: impulse-leg detection and the Fibonacci geometry every     |
//|  entry, stop, target and grid level is derived from.              |
//|                                                                   |
//|  Geometry convention                                              |
//|  -------------------                                              |
//|  An UP leg runs low L -> high H, range R = H - L.                 |
//|     retracement(r) = H - r*R      (1.0 lands back on L)           |
//|     extension(e)   = L + e*R      (1.618 sits above H)            |
//|  A DOWN leg runs high H -> low L, mirrored:                       |
//|     retracement(r) = L + r*R                                      |
//|     extension(e)   = H - e*R                                      |
//|  Both directions therefore share one code path via `dir`.         |
//+------------------------------------------------------------------+
#ifndef GFEA_FIBONACCI_MQH
#define GFEA_FIBONACCI_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Pivot tests — a bar is a pivot when `strength` bars on BOTH sides |
//| fail to exceed it. Requiring both sides is what makes the pivot   |
//| confirmed and non-repainting: it can only be judged `strength`    |
//| bars after the fact, and it never changes afterwards.             |
//+------------------------------------------------------------------+
bool IsPivotHigh(const ENUM_TIMEFRAMES tf, const int shift, const int strength)
  {
   double h = iHigh(_Symbol, tf, shift);
   if(h <= 0) return false;
   for(int k = 1; k <= strength; k++)
     {
      double left  = iHigh(_Symbol, tf, shift + k);
      double right = iHigh(_Symbol, tf, shift - k);
      if(left <= 0 || right <= 0) return false;
      if(left > h || right > h)   return false;
     }
   return true;
  }

bool IsPivotLow(const ENUM_TIMEFRAMES tf, const int shift, const int strength)
  {
   double l = iLow(_Symbol, tf, shift);
   if(l <= 0) return false;
   for(int k = 1; k <= strength; k++)
     {
      double left  = iLow(_Symbol, tf, shift + k);
      double right = iLow(_Symbol, tf, shift - k);
      if(left <= 0 || right <= 0) return false;
      if(left < l || right < l)   return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Detect the leg the cycle anchors to.                             |
//|                                                                   |
//| Step 1: find the most recent CONFIRMED pivot of either kind.      |
//| Step 2: take the opposite extreme between that pivot and the      |
//|         lookback horizon as the leg origin. Using the extreme     |
//|         rather than the nearest opposite pivot yields the largest |
//|         leg ending at the same point, which is the leg traders    |
//|         actually draw their fibs on.                              |
//| Step 3: reject legs smaller than InpMinSwingAtr x ATR — small     |
//|         legs produce fib levels inside the noise band.            |
//+------------------------------------------------------------------+
bool DetectSwing(SSwing &out)
  {
   ENUM_TIMEFRAMES tf = SignalTF();
   int strength = MathMax(1, InpPivotStrength);
   int avail    = Bars(_Symbol, tf);
   int horizon  = MathMin(InpSwingLookback, avail - strength - 2);
   if(horizon < strength * 4) return false;

   //--- Step 1 — walk forward from the newest confirmed bar
   int  pivotShift = -1;
   bool pivotIsHigh = false;
   for(int s = strength + 1; s <= horizon; s++)
     {
      bool ph = IsPivotHigh(tf, s, strength);
      bool pl = IsPivotLow(tf, s, strength);
      if(ph || pl)
        {
         //--- an inside bar can satisfy both tests; the wider wick wins
         if(ph && pl)
           {
            double up   = iHigh(_Symbol, tf, s) - iClose(_Symbol, tf, s);
            double down = iClose(_Symbol, tf, s) - iLow(_Symbol, tf, s);
            pivotIsHigh = (up >= down);
           }
         else
            pivotIsHigh = ph;
         pivotShift = s;
         break;
        }
     }
   if(pivotShift < 0) return false;

   //--- Step 2 — opposite extreme between the pivot and the horizon
   int    originShift = -1;
   double originPrice = 0;
   for(int s = pivotShift + 1; s <= horizon; s++)
     {
      if(pivotIsHigh)
        {
         double l = iLow(_Symbol, tf, s);
         if(l <= 0) continue;
         if(originShift < 0 || l < originPrice) { originPrice = l; originShift = s; }
        }
      else
        {
         double h = iHigh(_Symbol, tf, s);
         if(h <= 0) continue;
         if(originShift < 0 || h > originPrice) { originPrice = h; originShift = s; }
        }
     }
   if(originShift < 0) return false;

   double pivotPrice = pivotIsHigh ? iHigh(_Symbol, tf, pivotShift)
                                   : iLow(_Symbol, tf, pivotShift);
   if(pivotPrice <= 0) return false;

   //--- Step 3 — size gate
   double atr = g_ea.view.atr;
   double range = MathAbs(pivotPrice - originPrice);
   if(range <= 0) return false;
   if(atr > 0 && range < InpMinSwingAtr * atr) return false;

   out.valid  = true;
   out.dir    = pivotIsHigh ? 1 : -1;
   out.hi     = pivotIsHigh ? pivotPrice : originPrice;
   out.lo     = pivotIsHigh ? originPrice : pivotPrice;
   out.hiTime = iTime(_Symbol, tf, pivotIsHigh ? pivotShift : originShift);
   out.loTime = iTime(_Symbol, tf, pivotIsHigh ? originShift : pivotShift);
   out.range  = out.hi - out.lo;
   out.atr    = atr;
   out.found  = TimeCurrent();
   return(out.range > 0);
  }

//+------------------------------------------------------------------+
//| Level math — one implementation for both leg directions          |
//+------------------------------------------------------------------+
double FibRetraceOf(const int dir, const double hi, const double lo, const double ratio)
  {
   double range = hi - lo;
   if(range <= 0) return 0;
   return(dir > 0 ? hi - ratio * range : lo + ratio * range);
  }

double FibExtendOf(const int dir, const double hi, const double lo, const double ratio)
  {
   double range = hi - lo;
   if(range <= 0) return 0;
   return(dir > 0 ? lo + ratio * range : hi - ratio * range);
  }

double FibRetrace(const SSwing &s, const double ratio)
  {
   return FibRetraceOf(s.dir, s.hi, s.lo, ratio);
  }

double FibExtend(const SSwing &s, const double ratio)
  {
   return FibExtendOf(s.dir, s.hi, s.lo, ratio);
  }

//--- How deep the current price sits in the leg. 0 = at the leg tip,
//--- 1 = back at the leg origin, >1 = the leg is broken.
double RetracementOf(const SSwing &s, const double price)
  {
   if(!s.valid || s.range <= 0) return -1;
   return(s.dir > 0 ? (s.hi - price) / s.range : (price - s.lo) / s.range);
  }

//--- The tradable pullback window, expressed as prices.
void EntryZone(const SSwing &s, double &zoneNear, double &zoneFar)
  {
   double a = FibRetrace(s, InpEntryFibMin);
   double b = FibRetrace(s, InpEntryFibMax);
   zoneNear = MathMax(a, b);
   zoneFar  = MathMin(a, b);
  }

bool PriceInEntryZone(const SSwing &s, const double price)
  {
   double r = RetracementOf(s, price);
   if(r < 0) return false;
   return(r >= InpEntryFibMin - 1e-9 && r <= InpEntryFibMax + 1e-9);
  }

//+------------------------------------------------------------------+
//| Structural stop: beyond the invalidation retracement, plus an     |
//| ATR buffer so a wick through the level does not take the cycle    |
//| out before the structure is genuinely broken.                     |
//+------------------------------------------------------------------+
double StructuralStop(const SSwing &s)
  {
   if(!s.valid) return 0;
   double level  = FibRetrace(s, InpSlFibLevel);
   double buffer = InpSlAtrBuffer * (s.atr > 0 ? s.atr : g_ea.view.atr);
   return NormalizePrice(level - s.dir * buffer);
  }

//+------------------------------------------------------------------+
//| Fibonacci-spaced grid ladder.                                     |
//|                                                                   |
//| SPACING_FIB_LEG walks the retracement ladder of the anchor leg,   |
//| so every add sits on a level a discretionary trader would also    |
//| be watching, and the ladder can never extend past invalidation.   |
//| The ATR models widen each step by the Fibonacci sequence, which   |
//| is what keeps a deep sequence survivable: equal spacing fills the |
//| whole ladder inside one impulse, fib-widened spacing does not.    |
//+------------------------------------------------------------------+
double GridStepDistance(const int levelIndex, const double atr)
  {
   int i = MathMax(0, MathMin(levelIndex, 7));
   switch(InpGridSpacing)
     {
      case SPACING_ATR_FIB:
         return atr * InpGridBaseAtr * FIB_WIDEN[i];
      case SPACING_ATR_LINEAR:
         return atr * InpGridBaseAtr;
      case SPACING_FIXED_POINTS:
         return (double)InpGridFixedPoints * g_ea.point;
     }
   return atr * InpGridBaseAtr * FIB_WIDEN[i];
  }

//--- Price at which grid level `levelIndex` (1-based; 0 is the first entry)
//--- should be filled for a cycle anchored on the given leg.
double GridLevelPrice(const int dir, const double hi, const double lo,
                      const double firstEntry, const int levelIndex, const double atr)
  {
   if(levelIndex <= 0) return firstEntry;
   int remaining = levelIndex;   // inputs and parameters are const: work on a copy

   if(InpGridSpacing == SPACING_FIB_LEG && (hi - lo) > 0)
     {
      //--- walk the retracement ladder outward from the entry ratio
      double entryR = (dir > 0) ? (hi - firstEntry) / (hi - lo)
                                : (firstEntry - lo) / (hi - lo);
      for(int i = 0; i < ArraySize(FIB_RETRACE); i++)
        {
         if(FIB_RETRACE[i] <= entryR + 1e-6) continue;
         remaining--;
         if(remaining <= 0)
            return NormalizePrice(FibRetraceOf(dir, hi, lo, FIB_RETRACE[i]));
        }
      //--- ladder exhausted inside the leg: widen with ATR beyond it
     }

   double dist = 0;
   for(int i = 1; i <= remaining; i++)
      dist += GridStepDistance(i - 1, atr);
   return NormalizePrice(firstEntry - dir * dist);
  }

//+------------------------------------------------------------------+
//| Lot for a grid level under the selected progression.              |
//+------------------------------------------------------------------+
double GridLevelLots(const double baseLot, const int levelIndex)
  {
   int i = MathMax(0, MathMin(levelIndex, 7));
   double mult = 1.0;
   switch(InpLotProgression)
     {
      case PROG_FLAT:      mult = 1.0;                          break;
      case PROG_LINEAR:    mult = (double)(levelIndex + 1);      break;
      case PROG_FIBONACCI: mult = FIB_LOTS[i];                   break;
      case PROG_GEOMETRIC: mult = MathPow(InpLotFactor, levelIndex); break;
     }
   return NormalizeVolume(baseLot * mult);
  }

#endif // GFEA_FIBONACCI_MQH
//+------------------------------------------------------------------+
