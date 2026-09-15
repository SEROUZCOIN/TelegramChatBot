//+------------------------------------------------------------------+
//|                                                 AQ_Structure.mqh |
//|     APEX QUANTUM — trend rails, swing structure, imbalance       |
//|                                                                  |
//|  Three cooperating pieces:                                       |
//|   1. AQ_CalcTrendLines()  — the Perfect-Trend-Line recurrence:   |
//|      a fast and a slow rail that trail the extreme of their      |
//|      window and only swap sides when price closes through both.  |
//|   2. CAQStructure zigzag  — swing detection driven by Parabolic  |
//|      SAR flips; every pivot records the bar where it became      |
//|      KNOWN (confirm), so downstream logic never peeks ahead.     |
//|   3. BOS / CHoCH + fair value gaps built on those pivots.        |
//+------------------------------------------------------------------+
#ifndef AQ_STRUCTURE_MQH
#define AQ_STRUCTURE_MQH

#include "AQ_Core.mqh"

#define AQ_PIV_MAX      192           // confirmed pivots retained
#define AQ_BRK_MAX       48           // structural breaks retained
#define AQ_FVG_MAX      128           // imbalances retained

//+------------------------------------------------------------------+
//| Perfect Trend Line — pure per-bar recurrence, incremental        |
//| trend: +1 bullish, -1 bearish. Writes every trend-related buffer |
//| in one pass so the plotted rails and the exported state can      |
//| never disagree.                                                  |
//+------------------------------------------------------------------+
void AQ_CalcTrendLines(const int rates_total, const int start,
                       const int fastLen, const int slowLen,
                       const double &high[], const double &low[], const double &close[],
                       double &fastLine[], double &slowLine[], double &trend[],
                       double &railUp[], double &railDn[], double &fastCol[])
  {
   for(int i = start; i < rates_total; i++)
     {
      if(i == 0)
        {
         fastLine[0] = slowLine[0] = close[0];
         trend[0]    = 1.0;
         railUp[0]   = railDn[0] = EMPTY_VALUE;
         fastCol[0]  = 0.0;
         continue;
        }

      int sf = i - fastLen + 1; if(sf < 0) sf = 0;
      int ss = i - slowLen + 1; if(ss < 0) ss = 0;
      int cf = i - sf + 1;
      int cs = i - ss + 1;

      double hiF = high[ArrayMaximum(high, sf, cf)];
      double loF = low [ArrayMinimum(low,  sf, cf)];
      double hiS = high[ArrayMaximum(high, ss, cs)];
      double loS = low [ArrayMinimum(low,  ss, cs)];

      //--- each rail trails the opposite extreme of its window while price holds above it
      slowLine[i] = (close[i] > slowLine[i - 1]) ? loS : hiS;
      fastLine[i] = (close[i] > fastLine[i - 1]) ? loF : hiF;

      trend[i] = trend[i - 1];
      if(close[i] < slowLine[i] && close[i] < fastLine[i]) trend[i] = -1.0;
      if(close[i] > slowLine[i] && close[i] > fastLine[i]) trend[i] =  1.0;

      railUp[i]  = (trend[i] > 0.0) ? slowLine[i] : EMPTY_VALUE;
      railDn[i]  = (trend[i] < 0.0) ? slowLine[i] : EMPTY_VALUE;
      fastCol[i] = (trend[i] > 0.0) ? 0.0 : 1.0;
     }
  }

//+------------------------------------------------------------------+
//| Configuration                                                    |
//+------------------------------------------------------------------+
struct AQStructCfg
  {
   int               lookback;        // bars scanned
   double            sarStep;         // Parabolic SAR step
   double            sarMax;          // Parabolic SAR maximum
   bool              showFib;         // draw the retracement of the live leg
   int               maxFvg;          // imbalance boxes drawn
   int               maxBreaks;       // break markers drawn
  };

//+------------------------------------------------------------------+
//| CAQStructure                                                     |
//+------------------------------------------------------------------+
class CAQStructure
  {
private:
   AQStructCfg       m_cfg;
   int               m_hSar;
   double            m_sar[];
   int               m_base;

   AQPivot           m_piv[];
   int               m_pivCount;
   AQBreak           m_brk[];
   int               m_brkCount;
   AQFvg             m_fvg[];
   int               m_fvgCount;

   int               m_dir;           // live structural direction (+1 / -1)
   int               m_lastEvent;     // most recent BOS / CHoCH
   datetime          m_lastEventTime;
   double            m_legLo, m_legHi;// live leg range (premium / discount frame)
   datetime          m_legT1, m_legT2;
   double            m_legP1, m_legP2;

   void              PushPivot(const int bar, const int confirm, const datetime t, const double price, const int dir);
   void              PushBreak(const int bar, const datetime t, const double price, const int ev);

public:
                     CAQStructure(void) : m_hSar(INVALID_HANDLE), m_base(0), m_pivCount(0),
                                          m_brkCount(0), m_fvgCount(0), m_dir(0),
                                          m_lastEvent(0), m_lastEventTime(0),
                                          m_legLo(0.0), m_legHi(0.0),
                                          m_legT1(0), m_legT2(0), m_legP1(0.0), m_legP2(0.0) {}

   bool              Init(const AQStructCfg &cfg);
   void              Release(void);

   bool              CalcZigZag(const int total, const datetime &time[],
                                const double &high[], const double &low[],
                                double &zzHi[], double &zzLo[]);
   void              CalcBreaks(const int total, const datetime &time[], const double &close[], double &evBuf[]);
   void              CalcFvg(const int total, const datetime &time[], const double &high[], const double &low[]);

   void              RenderBreaks(void);
   void              RenderFvg(const int total, const datetime &time[]);
   void              RenderFib(void);
   void              EraseBreaks(void) { AQ_DeleteGroup("B"); }
   void              EraseFvg(void)    { AQ_DeleteGroup("G"); }
   void              EraseFib(void)    { AQ_DeleteGroup("F"); }

   //--- state accessors
   int               Direction(void)     const { return(m_dir); }
   int               LastEvent(void)     const { return(m_lastEvent); }
   datetime          LastEventTime(void) const { return(m_lastEventTime); }
   double            LegLow(void)        const { return(m_legLo); }
   double            LegHigh(void)       const { return(m_legHi); }
   int               PivotCount(void)    const { return(m_pivCount); }

   //--- history-safe queries (only data known at or before 'bar' is used)
   bool              LegAt(const int bar, double &lo, double &hi) const;
   int               DirAt(const int bar) const;
   int               FvgAt(const int bar, const double price) const;
   string            EventName(const int ev) const;
  };

//+------------------------------------------------------------------+
//| Handles                                                          |
//+------------------------------------------------------------------+
bool CAQStructure::Init(const AQStructCfg &cfg)
  {
   m_cfg  = cfg;
   m_hSar = iSAR(_Symbol, PERIOD_CURRENT, m_cfg.sarStep, m_cfg.sarMax);
   if(m_hSar == INVALID_HANDLE)
     {
      Print("APEX QUANTUM: iSAR handle failed, err=", GetLastError());
      return(false);
     }
   return(true);
  }

void CAQStructure::Release(void)
  {
   if(m_hSar != INVALID_HANDLE) { IndicatorRelease(m_hSar); m_hSar = INVALID_HANDLE; }
  }

void CAQStructure::PushPivot(const int bar, const int confirm, const datetime t, const double price, const int dir)
  {
   if(m_pivCount >= AQ_PIV_MAX)
     {
      //--- drop the oldest, keep the window rolling
      for(int i = 1; i < m_pivCount; i++) m_piv[i - 1] = m_piv[i];
      m_pivCount--;
     }
   ArrayResize(m_piv, m_pivCount + 1, AQ_PIV_MAX);
   m_piv[m_pivCount].bar     = bar;
   m_piv[m_pivCount].confirm = confirm;
   m_piv[m_pivCount].time    = t;
   m_piv[m_pivCount].price   = price;
   m_piv[m_pivCount].dir     = dir;
   m_pivCount++;
  }

void CAQStructure::PushBreak(const int bar, const datetime t, const double price, const int ev)
  {
   if(m_brkCount >= AQ_BRK_MAX)
     {
      for(int i = 1; i < m_brkCount; i++) m_brk[i - 1] = m_brk[i];
      m_brkCount--;
     }
   ArrayResize(m_brk, m_brkCount + 1, AQ_BRK_MAX);
   m_brk[m_brkCount].bar   = bar;
   m_brk[m_brkCount].time  = t;
   m_brk[m_brkCount].price = price;
   m_brk[m_brkCount].ev    = ev;
   m_brkCount++;
  }

//+------------------------------------------------------------------+
//| ZigZag driven by Parabolic SAR flips                             |
//| A leg ends when SAR crosses the bar mid-price; the extreme       |
//| reached during the leg becomes the pivot, and the flip bar is    |
//| recorded as its confirmation bar.                                |
//+------------------------------------------------------------------+
bool CAQStructure::CalcZigZag(const int total, const datetime &time[],
                              const double &high[], const double &low[],
                              double &zzHi[], double &zzLo[])
  {
   m_pivCount = 0;
   if(total < 32 || m_hSar == INVALID_HANDLE) return(false);
   if(BarsCalculated(m_hSar) < total)         return(false);   // SAR not ready — retry next tick

   m_base  = (int)MathMax(1, total - 1 - m_cfg.lookback);
   int n   = total - m_base;
   if(CopyBuffer(m_hSar, 0, 0, n, m_sar) < n) return(false);   // m_sar[k] <-> bar m_base+k

   for(int i = m_base; i < total; i++) { zzHi[i] = 0.0; zzLo[i] = 0.0; }

   double mid0 = (high[m_base] + low[m_base]) * 0.5;
   bool   up   = (m_sar[0] < mid0);                            // SAR below price -> leg is rising
   double ext  = up ? high[m_base] : low[m_base];
   int    extBar = m_base;

   for(int i = m_base + 1; i < total; i++)
     {
      int    k    = i - m_base;
      double mid  = (high[i]     + low[i])     * 0.5;
      double midP = (high[i - 1] + low[i - 1]) * 0.5;

      if(up)
        {
         if(high[i] > ext) { ext = high[i]; extBar = i; }
         if(m_sar[k - 1] <= midP && m_sar[k] > mid)            // flip down: the high is locked
           {
            zzHi[extBar] = ext;
            PushPivot(extBar, i, time[extBar], ext, 1);
            up = false; ext = low[i]; extBar = i;
           }
        }
      else
        {
         if(low[i] < ext) { ext = low[i]; extBar = i; }
         if(m_sar[k - 1] >= midP && m_sar[k] < mid)            // flip up: the low is locked
           {
            zzLo[extBar] = ext;
            PushPivot(extBar, i, time[extBar], ext, -1);
            up = true; ext = high[i]; extBar = i;
           }
        }
     }

   //--- the leg in progress is drawn to its running extreme; it is NOT a pivot,
   //--- so nothing downstream (structure, signals) can act on an unconfirmed swing
   if(up) zzHi[extBar] = ext;
   else   zzLo[extBar] = ext;

   //--- live leg frame = last two confirmed pivots of opposite direction
   m_legLo = 0.0; m_legHi = 0.0;
   if(m_pivCount >= 2)
     {
      AQPivot a = m_piv[m_pivCount - 1];
      AQPivot b = m_piv[m_pivCount - 2];
      m_legLo = MathMin(a.price, b.price);
      m_legHi = MathMax(a.price, b.price);
      m_legT1 = b.time; m_legP1 = b.price;
      m_legT2 = a.time; m_legP2 = a.price;
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| BOS / CHoCH                                                      |
//| A confirmed swing becomes actionable only from its confirm bar   |
//| onward; a close through it is a break. Direction carried before  |
//| the break decides BOS (continuation) vs CHoCH (reversal).        |
//+------------------------------------------------------------------+
void CAQStructure::CalcBreaks(const int total, const datetime &time[], const double &close[], double &evBuf[])
  {
   m_brkCount = 0;
   m_dir = 0; m_lastEvent = 0; m_lastEventTime = 0;
   if(m_pivCount < 2) return;

   int    pc   = 0;
   double swHi = 0.0, swLo = 0.0;

   for(int i = m_base; i < total; i++)
     {
      evBuf[i] = 0.0;

      while(pc < m_pivCount && m_piv[pc].confirm <= i)
        {
         if(m_piv[pc].dir > 0) swHi = m_piv[pc].price;
         else                  swLo = m_piv[pc].price;
         pc++;
        }

      int ev = AQ_EV_NONE;
      double lvl = 0.0;
      if(swHi > 0.0 && close[i] > swHi)
        {
         ev  = (m_dir < 0) ? AQ_EV_CHOCH_BULL : AQ_EV_BOS_BULL;
         lvl = swHi; m_dir = 1;  swHi = 0.0;               // level consumed
        }
      else if(swLo > 0.0 && close[i] < swLo)
        {
         ev  = (m_dir > 0) ? AQ_EV_CHOCH_BEAR : AQ_EV_BOS_BEAR;
         lvl = swLo; m_dir = -1; swLo = 0.0;
        }

      if(ev != AQ_EV_NONE)
        {
         evBuf[i] = (double)ev;
         PushBreak(i, time[i], lvl, ev);
         m_lastEvent     = ev;
         m_lastEventTime = time[i];
        }
     }
  }

//+------------------------------------------------------------------+
//| Fair value gaps (3-bar imbalance), with mitigation tracked in    |
//| the same forward pass — no quadratic re-scan.                    |
//+------------------------------------------------------------------+
void CAQStructure::CalcFvg(const int total, const datetime &time[], const double &high[], const double &low[])
  {
   m_fvgCount = 0;
   ArrayResize(m_fvg, 0, AQ_FVG_MAX);
   if(total < 8) return;

   for(int i = m_base + 2; i < total; i++)
     {
      //--- age the open gaps against this bar first
      for(int f = 0; f < m_fvgCount; f++)
        {
         if(m_fvg[f].mitigated || m_fvg[f].bar >= i) continue;
         if(m_fvg[f].dir > 0) { if(low[i]  <= m_fvg[f].lo) m_fvg[f].mitigated = true; }
         else                 { if(high[i] >= m_fvg[f].hi) m_fvg[f].mitigated = true; }
        }

      bool bull = (low[i]  > high[i - 2]);
      bool bear = (high[i] < low [i - 2]);
      if(!bull && !bear) continue;

      if(m_fvgCount >= AQ_FVG_MAX)
        {
         for(int k = 1; k < m_fvgCount; k++) m_fvg[k - 1] = m_fvg[k];
         m_fvgCount--;
        }
      ArrayResize(m_fvg, m_fvgCount + 1, AQ_FVG_MAX);
      m_fvg[m_fvgCount].bar       = i;
      m_fvg[m_fvgCount].time      = time[i];
      m_fvg[m_fvgCount].hi        = bull ? low[i]  : low[i - 2];
      m_fvg[m_fvgCount].lo        = bull ? high[i - 2] : high[i];
      m_fvg[m_fvgCount].dir       = bull ? 1 : -1;
      m_fvg[m_fvgCount].mitigated = false;
      m_fvgCount++;
     }
  }

//+------------------------------------------------------------------+
//| History-safe queries                                             |
//+------------------------------------------------------------------+
bool CAQStructure::LegAt(const int bar, double &lo, double &hi) const
  {
   double a = 0.0, b = 0.0;
   int found = 0;
   for(int i = m_pivCount - 1; i >= 0 && found < 2; i--)
     {
      if(m_piv[i].confirm > bar) continue;
      if(found == 0) a = m_piv[i].price;
      else           b = m_piv[i].price;
      found++;
     }
   if(found < 2) return(false);
   lo = MathMin(a, b);
   hi = MathMax(a, b);
   return(hi > lo);
  }

int CAQStructure::DirAt(const int bar) const
  {
   int d = 0;
   for(int i = 0; i < m_brkCount; i++)
     {
      if(m_brk[i].bar > bar) break;
      d = (m_brk[i].ev > 0) ? 1 : -1;
     }
   return(d);
  }

int CAQStructure::FvgAt(const int bar, const double price) const
  {
   for(int i = m_fvgCount - 1; i >= 0; i--)
     {
      if(m_fvg[i].bar > bar) continue;
      if(price >= m_fvg[i].lo && price <= m_fvg[i].hi) return(m_fvg[i].dir);
     }
   return(0);
  }

string CAQStructure::EventName(const int ev) const
  {
   switch(ev)
     {
      case AQ_EV_BOS_BULL:   return("BOS UP");
      case AQ_EV_BOS_BEAR:   return("BOS DOWN");
      case AQ_EV_CHOCH_BULL: return("CHoCH UP");
      case AQ_EV_CHOCH_BEAR: return("CHoCH DOWN");
     }
   return("--");
  }

//+------------------------------------------------------------------+
//| Presentation                                                     |
//+------------------------------------------------------------------+
void CAQStructure::RenderBreaks(void)
  {
   AQ_DeleteGroup("B");
   if(m_brkCount == 0) return;

   int from = (int)MathMax(0, m_brkCount - m_cfg.maxBreaks);
   for(int i = from; i < m_brkCount; i++)
     {
      bool   choch = (MathAbs(m_brk[i].ev) == 2);
      color  clr   = choch ? AQ_CLR_CHOCH : AQ_CLR_BOS;
      string id    = "B" + (string)i;
      datetime t2  = m_brk[i].time + (datetime)(PeriodSeconds() * 3);
      AQ_DrawTrend(id, m_brk[i].time - (datetime)(PeriodSeconds() * 6), m_brk[i].price,
                   t2, m_brk[i].price, clr, 1, STYLE_DOT, false);
      AQ_DrawText("BT" + (string)i, t2, m_brk[i].price, EventName(m_brk[i].ev),
                  clr, AQ_FS_SM, ANCHOR_LEFT, AQ_FONT);
     }
  }

void CAQStructure::RenderFvg(const int total, const datetime &time[])
  {
   AQ_DeleteGroup("G");
   if(m_fvgCount == 0) return;

   datetime tEnd = time[total - 1] + (datetime)(PeriodSeconds() * 3);
   int drawn = 0;
   for(int i = m_fvgCount - 1; i >= 0 && drawn < m_cfg.maxFvg; i--)
     {
      if(m_fvg[i].mitigated) continue;                        // filled gaps are history
      AQ_DrawZone("G" + (string)i, m_fvg[i].time, m_fvg[i].hi, tEnd, m_fvg[i].lo,
                  m_fvg[i].dir > 0 ? AQ_CLR_FVG_BULL : AQ_CLR_FVG_BEAR, true, 1, STYLE_SOLID);
      drawn++;
     }
  }

void CAQStructure::RenderFib(void)
  {
   AQ_DeleteGroup("F");
   if(!m_cfg.showFib || m_legT1 == 0 || m_legT2 == 0) return;
   AQ_DrawFibo("F0", m_legT1, m_legP1, m_legT2, m_legP2, AQ_CLR_FIB, STYLE_DOT, true);
  }

#endif // AQ_STRUCTURE_MQH
//+------------------------------------------------------------------+
