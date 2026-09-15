//+------------------------------------------------------------------+
//|                                                   AQ_Channel.mqh |
//|          APEX QUANTUM — regression-style price channel           |
//|                                                                  |
//|  The SHI channel idea rebuilt forward-indexed: take the two most |
//|  recent same-side fractals, run the base rail through them, then |
//|  slide a parallel rail out to the furthest opposite excursion.   |
//|  Exposes slope and the 0..1 position of price between the rails  |
//|  — the premium / discount frame the signal engine scores with.   |
//+------------------------------------------------------------------+
#ifndef AQ_CHANNEL_MQH
#define AQ_CHANNEL_MQH

#include "AQ_Core.mqh"

//+------------------------------------------------------------------+
//| Configuration                                                    |
//+------------------------------------------------------------------+
struct AQChanCfg
  {
   int               lookback;        // bars scanned for the anchors
   int               fractalBars;     // half-window; 0 = auto per timeframe
   int               width;           // rail line width
  };

//+------------------------------------------------------------------+
//| CAQChannel                                                       |
//+------------------------------------------------------------------+
class CAQChannel
  {
private:
   AQChanCfg         m_cfg;
   AQChannel         m_ch;
   int               m_bff;
   int               AutoHalfWindow(void) const;

public:
                     CAQChannel(void) : m_bff(12) { m_ch.valid = false; }
   void              Configure(const AQChanCfg &cfg) { m_cfg = cfg; }
   bool              Calculate(const int total, const double &high[], const double &low[], const double &close[]);
   void              Render(const int total, const datetime &time[]);
   void              Erase(void) { AQ_DeleteGroup("C"); }
   bool              Get(AQChannel &c) const { c = m_ch; return(m_ch.valid); }
   int               Slope(void) const;
   double            Position(void) const { return(m_ch.valid ? m_ch.position : -1.0); }
  };

//+------------------------------------------------------------------+
//| Timeframe-adaptive fractal half-window (the original SHI table)  |
//+------------------------------------------------------------------+
int CAQChannel::AutoHalfWindow(void) const
  {
   switch(Period())
     {
      case PERIOD_M1:  return(12);
      case PERIOD_M2:  return(24);
      case PERIOD_M3:  return(36);
      case PERIOD_M4:  return(40);
      case PERIOD_M5:  return(48);
      case PERIOD_M6:  return(12);
      case PERIOD_M10: return(15);
      case PERIOD_M12: return(20);
      case PERIOD_M15: return(24);
      case PERIOD_M20: return(24);
      case PERIOD_M30: return(24);
      case PERIOD_H1:  return(12);
      case PERIOD_H2:  return(12);
      case PERIOD_H3:  return(12);
      case PERIOD_H4:  return(15);
      case PERIOD_H6:  return(12);
      case PERIOD_H8:  return(12);
      case PERIOD_H12: return(12);
      case PERIOD_D1:  return(10);
      case PERIOD_W1:  return(6);
      case PERIOD_MN1: return(6);
     }
   return(12);
  }

//+------------------------------------------------------------------+
//| Build the channel                                                |
//+------------------------------------------------------------------+
bool CAQChannel::Calculate(const int total, const double &high[], const double &low[], const double &close[])
  {
   m_ch.valid = false;
   m_bff = (m_cfg.fractalBars > 0) ? m_cfg.fractalBars : AutoHalfWindow();
   int count = m_bff * 2 + 1;
   if(total < count + 8) return(false);

   int base = (int)MathMax(m_bff, total - 1 - m_cfg.lookback);
   int last = total - 1 - m_bff;                     // newest bar with a complete window
   if(last <= base) return(false);

   int    sign = 0, b1 = -1, b2 = -1;
   double p1 = 0.0, p2 = 0.0;

   for(int b = last; b >= base; b--)
     {
      int start = b - m_bff;
      if(start < 0 || start + count > total) continue;
      bool isMax = (ArrayMaximum(high, start, count) == b);
      bool isMin = (ArrayMinimum(low,  start, count) == b);

      if(sign == 0)
        {
         if(isMax)      { sign =  1; b1 = b; p1 = high[b]; }
         else if(isMin) { sign = -1; b1 = b; p1 = low[b];  }
        }
      else if(sign > 0 && isMax && b < b1 - 1) { b2 = b; p2 = high[b]; break; }
      else if(sign < 0 && isMin && b < b1 - 1) { b2 = b; p2 = low[b];  break; }
     }
   if(b1 < 0 || b2 < 0 || b1 == b2) return(false);

   double slope = (p1 - p2) / (double)(b1 - b2);     // price per bar, forward in time

   //--- parallel rail: the largest excursion on the opposite side of the base rail
   double off = 0.0;
   bool   first = true;
   for(int i = b2; i < total; i++)
     {
      double lineAt = p2 + slope * (double)(i - b2);
      double d = (sign > 0) ? (low[i] - lineAt) : (high[i] - lineAt);
      if(first)                { off = d; first = false; }
      else if(sign > 0)        { if(d < off) off = d; }
      else                     { if(d > off) off = d; }
     }

   double baseNow = p2 + slope * (double)(total - 1 - b2);
   double offNow  = baseNow + off;

   m_ch.valid = true;
   m_ch.bar1  = b2;
   m_ch.bar2  = total - 1;
   m_ch.base1 = p2;
   m_ch.base2 = baseNow;
   m_ch.off1  = p2 + off;
   m_ch.off2  = offNow;
   m_ch.slope = slope;
   m_ch.width = MathAbs(off);

   double upper = MathMax(baseNow, offNow);
   double lower = MathMin(baseNow, offNow);
   m_ch.position = (upper > lower) ? AQ_Clamp((close[total - 1] - lower) / (upper - lower), 0.0, 1.0) : 0.5;
   return(true);
  }

//--- slope as a direction, filtered by a fraction of the channel width so a
//--- flat channel does not vote
int CAQChannel::Slope(void) const
  {
   if(!m_ch.valid || m_ch.width <= 0.0) return(0);
   double span = m_ch.slope * (double)(m_ch.bar2 - m_ch.bar1);
   if(span >  m_ch.width * 0.25) return(1);
   if(span < -m_ch.width * 0.25) return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| Presentation                                                     |
//+------------------------------------------------------------------+
void CAQChannel::Render(const int total, const datetime &time[])
  {
   AQ_DeleteGroup("C");
   if(!m_ch.valid) return;

   datetime t1 = time[AQ_Clamp(m_ch.bar1, 0, total - 1)];
   datetime t2 = time[total - 1];

   double upper1 = MathMax(m_ch.base1, m_ch.off1);
   double upper2 = MathMax(m_ch.base2, m_ch.off2);
   double lower1 = MathMin(m_ch.base1, m_ch.off1);
   double lower2 = MathMin(m_ch.base2, m_ch.off2);

   AQ_DrawTrend("C0", t1, upper1, t2, upper2, AQ_CLR_CHAN_UP, m_cfg.width, STYLE_SOLID, true);
   AQ_DrawTrend("C1", t1, lower1, t2, lower2, AQ_CLR_CHAN_DN, m_cfg.width, STYLE_SOLID, true);
   AQ_DrawTrend("C2", t1, (upper1 + lower1) * 0.5, t2, (upper2 + lower2) * 0.5,
                AQ_CLR_CHAN_MID, 1, STYLE_DOT, true);
  }

#endif // AQ_CHANNEL_MQH
//+------------------------------------------------------------------+
