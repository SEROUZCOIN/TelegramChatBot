//+------------------------------------------------------------------+
//|                                                      Signals.mqh |
//|  CORE: the Advanced Moving Average engine and the regime filter   |
//|  that decides whether a Fibonacci cycle may open at all.          |
//|                                                                   |
//|  Three questions, answered in order:                              |
//|    1. WHAT is the market doing?   -> regime (trend / range / chop)|
//|    2. WHICH way?                  -> MA stack + slope + HTF       |
//|    3. WHERE do we act?            -> the fib zone (Fibonacci.mqh) |
//|  A cycle needs all three to agree.                                |
//+------------------------------------------------------------------+
#ifndef GFEA_SIGNALS_MQH
#define GFEA_SIGNALS_MQH

#include "Fibonacci.mqh"

#define SIG_BUF_MAX 64      // ceiling for one CopyBuffer read

//--- Reusable dynamic read buffers. They must be DYNAMIC: ArraySetAsSeries
//--- has no effect on a statically sized array, so a fixed-size buffer here
//--- would silently invert every index. Declared once at file scope so the
//--- per-bar refresh does not reallocate.
double g_bufFast[], g_bufMid[], g_bufSlow[], g_bufHtf[];
double g_bufAdx[],  g_bufDip[], g_bufDim[], g_bufAtr[];

//+------------------------------------------------------------------+
//| Handles are created here once and released once. Creating them    |
//| per tick is the classic cause of error 4806.                      |
//+------------------------------------------------------------------+
bool InitIndicators(void)
  {
   ENUM_TIMEFRAMES tf = SignalTF();

   g_ea.hMaFast = iMA(_Symbol, tf, InpMaFast, 0, InpMaMethod, InpMaPrice);
   g_ea.hMaMid  = iMA(_Symbol, tf, InpMaMid,  0, InpMaMethod, InpMaPrice);
   g_ea.hMaSlow = iMA(_Symbol, tf, InpMaSlow, 0, InpMaMethod, InpMaPrice);
   g_ea.hAdx    = iADX(_Symbol, tf, InpAdxPeriod);
   g_ea.hAtr    = iATR(_Symbol, tf, InpAtrPeriod);
   g_ea.hMaHtf  = InpUseHtf ? iMA(_Symbol, InpHtfTF, InpHtfMaPeriod, 0, InpMaMethod, InpMaPrice)
                            : INVALID_HANDLE;

   if(g_ea.hMaFast == INVALID_HANDLE || g_ea.hMaMid == INVALID_HANDLE ||
      g_ea.hMaSlow == INVALID_HANDLE || g_ea.hAdx == INVALID_HANDLE   ||
      g_ea.hAtr == INVALID_HANDLE)
     {
      LogError("Indicator handle creation failed");
      return false;
     }
   if(InpUseHtf && g_ea.hMaHtf == INVALID_HANDLE)
     {
      LogError("Higher timeframe MA handle failed");
      return false;
     }
   return true;
  }

void ReleaseIndicators(void)
  {
   if(g_ea.hMaFast != INVALID_HANDLE) IndicatorRelease(g_ea.hMaFast);
   if(g_ea.hMaMid  != INVALID_HANDLE) IndicatorRelease(g_ea.hMaMid);
   if(g_ea.hMaSlow != INVALID_HANDLE) IndicatorRelease(g_ea.hMaSlow);
   if(g_ea.hMaHtf  != INVALID_HANDLE) IndicatorRelease(g_ea.hMaHtf);
   if(g_ea.hAdx    != INVALID_HANDLE) IndicatorRelease(g_ea.hAdx);
   if(g_ea.hAtr    != INVALID_HANDLE) IndicatorRelease(g_ea.hAtr);

   g_ea.hMaFast = INVALID_HANDLE;
   g_ea.hMaMid  = INVALID_HANDLE;
   g_ea.hMaSlow = INVALID_HANDLE;
   g_ea.hMaHtf  = INVALID_HANDLE;
   g_ea.hAdx    = INVALID_HANDLE;
   g_ea.hAtr    = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//| One guarded buffer read. `out` is series-indexed: out[0] is the   |
//| value at `start`, out[1] the bar before it, and so on.            |
//+------------------------------------------------------------------+
bool ReadBuffer(const int handle, const int bufferIndex, const int start,
                const int count, double &out[])
  {
   if(handle == INVALID_HANDLE) return false;
   int need = MathMax(1, MathMin(count, SIG_BUF_MAX));
   ArraySetAsSeries(out, true);
   int got = CopyBuffer(handle, bufferIndex, start, need, out);
   return(got == need);      // fewer bars than asked = history still loading
  }

//+------------------------------------------------------------------+
//| Refresh the whole market view from the last CLOSED bar.           |
//| Reading shift 1 rather than 0 is what makes every decision in     |
//| this EA non-repainting.                                           |
//+------------------------------------------------------------------+
bool RefreshMarketView(SMarketView &v)
  {
   int slopeBars = MathMax(1, MathMin(InpSlopeBars, SIG_BUF_MAX - 2));

   if(!ReadBuffer(g_ea.hAtr,    0, 1, 2, g_bufAtr))  return false;
   if(!ReadBuffer(g_ea.hMaFast, 0, 1, 2, g_bufFast)) return false;
   if(!ReadBuffer(g_ea.hMaMid,  0, 1, 2, g_bufMid))  return false;
   if(!ReadBuffer(g_ea.hMaSlow, 0, 1, slopeBars + 1, g_bufSlow)) return false;
   if(!ReadBuffer(g_ea.hAdx,    0, 1, 2, g_bufAdx))  return false;
   if(!ReadBuffer(g_ea.hAdx,    1, 1, 2, g_bufDip))  return false;
   if(!ReadBuffer(g_ea.hAdx,    2, 1, 2, g_bufDim))  return false;

   v.atr     = g_bufAtr[0];
   v.fast    = g_bufFast[0];
   v.mid     = g_bufMid[0];
   v.slow    = g_bufSlow[0];
   v.adx     = g_bufAdx[0];
   v.diPlus  = g_bufDip[0];
   v.diMinus = g_bufDim[0];

   //--- MA stack: strict ordering only. A tangled stack is not a trend.
   if(v.fast > v.mid && v.mid > v.slow)      v.stackDir =  1;
   else if(v.fast < v.mid && v.mid < v.slow) v.stackDir = -1;
   else                                      v.stackDir =  0;

   //--- Slope of the anchor MA, normalised by ATR so the threshold is
   //--- portable across symbols, timeframes and price scales.
   v.slopeAtr = 0;
   if(v.atr > 0)
      v.slopeAtr = (g_bufSlow[0] - g_bufSlow[slopeBars]) / (double)slopeBars / v.atr;

   //--- Higher timeframe agreement
   v.htf    = 0;
   v.htfDir = 0;
   if(InpUseHtf)
     {
      if(ReadBuffer(g_ea.hMaHtf, 0, 1, 2, g_bufHtf))
        {
         v.htf = g_bufHtf[0];
         double htfClose = iClose(_Symbol, InpHtfTF, 1);
         if(htfClose > 0 && v.htf > 0)
            v.htfDir = (htfClose > v.htf) ? 1 : -1;
        }
     }

   //--- Regime classification
   bool trending = (v.adx >= InpAdxTrendMin) &&
                   (v.stackDir != 0) &&
                   (MathAbs(v.slopeAtr) >= InpMinSlopeAtr) &&
                   (!InpUseHtf || v.htfDir == v.stackDir);

   if(trending)
      v.regime = (v.stackDir > 0) ? REG_TREND_UP : REG_TREND_DOWN;
   else if(v.adx <= InpAdxRangeMax)
      v.regime = REG_RANGE;
   else
      v.regime = REG_CHOP;

   v.bias = (v.regime == REG_TREND_UP) ? 1 : (v.regime == REG_TREND_DOWN ? -1 : 0);
   return(v.atr > 0);
  }

//+------------------------------------------------------------------+
//| Entry confirmation on the last closed bar.                       |
//+------------------------------------------------------------------+
bool ConfirmMaReclaim(const int dir, const SMarketView &v)
  {
   double c = iClose(_Symbol, SignalTF(), 1);
   if(c <= 0 || v.fast <= 0) return false;
   return(dir > 0 ? c > v.fast : c < v.fast);
  }

bool ConfirmRejection(const int dir)
  {
   ENUM_TIMEFRAMES tf = SignalTF();
   double h = iHigh(_Symbol, tf, 1);
   double l = iLow(_Symbol, tf, 1);
   double o = iOpen(_Symbol, tf, 1);
   double c = iClose(_Symbol, tf, 1);
   double range = h - l;
   if(range <= 0) return false;

   //--- a rejection bar leaves most of its range as a wick against `dir`
   double wick = (dir > 0) ? (MathMin(o, c) - l) : (h - MathMax(o, c));
   return(wick / range >= 0.40);
  }

bool EntryConfirmed(const int dir, const SMarketView &v)
  {
   switch(InpEntryConfirm)
     {
      case CONFIRM_NONE:       return true;
      case CONFIRM_MA_RECLAIM: return ConfirmMaReclaim(dir, v);
      case CONFIRM_REJECTION:  return ConfirmRejection(dir);
      case CONFIRM_BOTH:       return(ConfirmMaReclaim(dir, v) && ConfirmRejection(dir));
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Is this regime allowed to open a cycle at all?                   |
//+------------------------------------------------------------------+
bool RegimeAllowsEntry(const SMarketView &v, const int legDir)
  {
   if(v.regime == REG_CHOP) return false;   // never open a cycle without structure

   bool isTrend = (v.regime == REG_TREND_UP || v.regime == REG_TREND_DOWN);

   if(isTrend)
     {
      if(InpRegimePolicy == REGIME_RANGE_ONLY) return false;
      //--- trend continuation only: the leg must point the way the trend does
      return(v.bias == legDir);
     }

   //--- range: fade the extremes, so the leg direction leads and we only
   //--- require that the MA stack is not aggressively opposed to it
   if(InpRegimePolicy == REGIME_TREND_ONLY) return false;
   return(v.stackDir != -legDir || v.adx < InpAdxRangeMax);
  }

//+------------------------------------------------------------------+
//| The full entry decision. Returns +1 buy, -1 sell, 0 stand aside. |
//+------------------------------------------------------------------+
int EntrySignal(const SSwing &s, const SMarketView &v)
  {
   if(!s.valid || s.range <= 0) return 0;

   int dir = s.dir;
   if(!RegimeAllowsEntry(v, dir)) return 0;

   //--- price must sit inside the retracement window of the leg
   double price = SymbolInfoDouble(_Symbol, dir > 0 ? SYMBOL_ASK : SYMBOL_BID);
   if(price <= 0) return 0;

   double r = RetracementOf(s, price);
   if(r < InpEntryFibMin || r > InpEntryFibMax) return 0;

   //--- in a range we insist on the deeper half of the window: shallow
   //--- pullbacks inside a range are noise, not a discount
   if(v.regime == REG_RANGE && r < 0.5) return 0;

   if(!EntryConfirmed(dir, v)) return 0;

   return dir;
  }

#endif // GFEA_SIGNALS_MQH
//+------------------------------------------------------------------+
