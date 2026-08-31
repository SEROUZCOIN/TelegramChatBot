//+------------------------------------------------------------------+
//|                                                        Swing.mqh |
//|  CORE: non-repainting pivot detection and the pivot history.     |
//|                                                                  |
//|  A pivot cannot be confirmed until the bars to its right have    |
//|  closed. That lag is inherent, not a bug to engineer away — it   |
//|  is the price of a definition a backtest can honestly evaluate.  |
//|  Nothing here ever reads bar 0 (still forming).                  |
//+------------------------------------------------------------------+
#ifndef FIBBOT_SWING_MQH
#define FIBBOT_SWING_MQH

#include "Config.mqh"

//--- indicator reads (always the last CLOSED bar) ------------------

double GetAtr()
  {
   double v[1];
   if(CopyBuffer(g_bot.hATR, 0, 1, 1, v) != 1)
      return(0);
   return(v[0]);
  }

double GetTrendMa()
  {
   if(g_bot.hTrendMA == INVALID_HANDLE)
      return(0);
   double v[1];
   // الإزاحة 1 على إطار الاتجاه = آخر شمعة مغلقة هناك، فلا إعادة رسم
   if(CopyBuffer(g_bot.hTrendMA, 0, 1, 1, v) != 1)
      return(0);
   return(v[0]);
  }

//--- pivot history -------------------------------------------------

int PivotCount()
  {
   return(ArraySize(g_pivots));
  }

// الفهرس 0 = الأحدث
bool PivotAt(const int indexFromNewest, SPivot &out)
  {
   int total = ArraySize(g_pivots);
   int idx   = total - 1 - indexFromNewest;
   if(idx < 0 || idx >= total)
      return(false);
   out = g_pivots[idx];
   return(true);
  }

void PivotAdd(const datetime time, const double price, const bool isHigh)
  {
   int n = ArraySize(g_pivots);
   ArrayResize(g_pivots, n + 1);
   g_pivots[n].time   = time;
   g_pivots[n].price  = price;
   g_pivots[n].isHigh = isHigh;

   // القص من الأقدم حتى لا ينمو المصفوف بلا حد
   int total = ArraySize(g_pivots);
   if(total > PIVOT_HISTORY)
     {
      int drop = total - PIVOT_HISTORY;
      SPivot kept[];
      ArrayResize(kept, PIVOT_HISTORY);
      ArrayCopy(kept, g_pivots, 0, drop, PIVOT_HISTORY);
      ArrayResize(g_pivots, PIVOT_HISTORY);
      ArrayCopy(g_pivots, kept, 0, 0, PIVOT_HISTORY);
     }
  }

//--- detection -----------------------------------------------------

// الشمعة المرشحة الوحيدة عند كل شمعة جديدة: الإزاحة right+1
// (كل الشموع على يمينها مغلقة، والشمعة 0 لا تُقرأ إطلاقاً)
int CandidatePivotShift()
  {
   return(InpPivotRight + 1);
  }

bool IsPivotHigh(const int shift)
  {
   double h = iHigh(_Symbol, _Period, shift);
   if(h == 0)
      return(false);

   for(int i = 1; i <= InpPivotRight; i++)      // الجانب الأيمن: أصغر بصرامة
     {
      double r = iHigh(_Symbol, _Period, shift - i);
      if(r == 0 || r >= h)
         return(false);
     }
   for(int i = 1; i <= InpPivotLeft; i++)       // الجانب الأيسر: أصغر أو يساوي
     {
      double l = iHigh(_Symbol, _Period, shift + i);
      if(l == 0 || l > h)
         return(false);
     }
   return(true);
  }

bool IsPivotLow(const int shift)
  {
   double lo = iLow(_Symbol, _Period, shift);
   if(lo == 0)
      return(false);

   for(int i = 1; i <= InpPivotRight; i++)
     {
      double r = iLow(_Symbol, _Period, shift - i);
      if(r == 0 || r <= lo)
         return(false);
     }
   for(int i = 1; i <= InpPivotLeft; i++)
     {
      double l = iLow(_Symbol, _Period, shift + i);
      if(l == 0 || l < lo)
         return(false);
     }
   return(true);
  }

// تُستدعى مرة واحدة عند كل شمعة جديدة. تعيد true عند تأكيد نقطة جديدة.
bool SwingScanNewBar()
  {
   int shift = CandidatePivotShift();
   if(Bars(_Symbol, _Period) < shift + InpPivotLeft + 2)
      return(false);

   datetime t = iTime(_Symbol, _Period, shift);
   if(t == 0)
      return(false);

   // لا تسجل النقطة نفسها مرتين
   int total = ArraySize(g_pivots);
   if(total > 0 && g_pivots[total - 1].time == t)
      return(false);

   if(IsPivotHigh(shift))
     {
      PivotAdd(t, iHigh(_Symbol, _Period, shift), true);
      return(true);
     }
   if(IsPivotLow(shift))
     {
      PivotAdd(t, iLow(_Symbol, _Period, shift), false);
      return(true);
     }
   return(false);
  }

//--- leg construction ----------------------------------------------

// آخر نقطة مؤكدة من النوع المطلوب، بدءاً من فهرس معيّن (0 = الأحدث)
int FindPivot(const bool isHigh, const int fromIndex)
  {
   int total = ArraySize(g_pivots);
   for(int i = fromIndex; i < total; i++)
     {
      SPivot p;
      if(!PivotAt(i, p))
         break;
      if(p.isHigh == isHigh)
         return(i);
     }
   return(-1);
  }

// أكبر مدى شمعة داخل الساق — دليل الاندفاع (displacement)
double LargestBarRangeBetween(const datetime fromTime, const datetime toTime)
  {
   int fromShift = iBarShift(_Symbol, _Period, fromTime, false);
   int toShift   = iBarShift(_Symbol, _Period, toTime, false);
   if(fromShift < 0 || toShift < 0)
      return(0);

   int hi = MathMax(fromShift, toShift);
   int lo = MathMin(fromShift, toShift);
   double best = 0;
   for(int s = lo; s <= hi; s++)
     {
      double r = iHigh(_Symbol, _Period, s) - iLow(_Symbol, _Period, s);
      if(r > best)
         best = r;
     }
   return(best);
  }

int BarsBetween(const datetime fromTime, const datetime toTime)
  {
   int fromShift = iBarShift(_Symbol, _Period, fromTime, false);
   int toShift   = iBarShift(_Symbol, _Period, toTime, false);
   if(fromShift < 0 || toShift < 0)
      return(-1);
   return(MathAbs(fromShift - toShift));
  }

#endif // FIBBOT_SWING_MQH
//+------------------------------------------------------------------+
