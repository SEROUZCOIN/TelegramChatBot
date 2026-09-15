//+------------------------------------------------------------------+
//|                                                    AQ_Signal.mqh |
//|            APEX QUANTUM — confluence scoring & entry model       |
//|                                                                  |
//|  Every module votes; the sum is a score in [-100 .. +100].       |
//|  A score alone never fires an arrow: it must also agree with the |
//|  primary trend rail AND coincide with a trigger event (a         |
//|  pullback into a zone/rail, or a trend flip). Everything is      |
//|  evaluated on CLOSED bars only, from data that was already known |
//|  at that bar, which is what keeps the arrows out of the repaint  |
//|  business.                                                       |
//+------------------------------------------------------------------+
#ifndef AQ_SIGNAL_MQH
#define AQ_SIGNAL_MQH

#include "AQ_Core.mqh"

//--- vote weights (single place to retune the engine)
#define AQ_W_TREND        25          // primary rail direction
#define AQ_W_FAST          8          // price vs the fast rail
#define AQ_W_STRUCT       12          // BOS / CHoCH direction
#define AQ_W_LEG           8          // discount / premium inside the live leg
#define AQ_W_FVG           6          // unfilled imbalance at price
#define AQ_W_MTF          10          // per confirming higher timeframe
#define AQ_W_CHAN_SLOPE    5          // channel tilt
#define AQ_W_CHAN_POS      5          // position between the rails
#define AQ_W_ZONE_MIN      6          // weakest zone vote
#define AQ_W_ZONE_STEP     3          // added per grade above WEAK

//+------------------------------------------------------------------+
//| Configuration                                                    |
//+------------------------------------------------------------------+
struct AQSigCfg
  {
   int               mode;            // ENUM_AQ_SIGNAL_MODE
   int               minScore;        // |score| needed to arm a signal
   int               cooldownBars;    // bars between signals
   bool              confirmCandle;   // require a closing candle in the signal direction
  };

//+------------------------------------------------------------------+
//| Everything the engine knows about one bar                        |
//+------------------------------------------------------------------+
struct AQSigCtx
  {
   int               bar;
   double            open, high, low, close, atr;
   double            fast, slow;      // trend rails
   int               trend, trendPrev;// +1 / -1
   int               zoneSide;        // +1 in demand, -1 in supply, 0 outside
   int               zoneGrade;       // ENUM_AQ_GRADE of that zone, -1 if none
   int               fvgSide;         // +1 / -1 / 0
   int               structDir;       // +1 / -1 / 0 from the last break
   int               event;           // ENUM_AQ_EVENT on this bar
   double            legLo, legHi;    // live leg frame (0 if unknown)
   int               mtf1, mtf2;      // higher timeframe trends, +1 / -1 / 0
   double            chanPos;         // 0..1 between the rails, -1 unknown
   int               chanSlope;       // +1 / -1 / 0
  };

//+------------------------------------------------------------------+
//| CAQSignal                                                        |
//+------------------------------------------------------------------+
class CAQSignal
  {
private:
   AQSigCfg          m_cfg;
   int               m_lastBar;
   int               m_lastDir;

public:
                     CAQSignal(void) : m_lastBar(-100000), m_lastDir(0) {}
   void              Configure(const AQSigCfg &cfg) { m_cfg = cfg; }
   void              Reset(void) { m_lastBar = -100000; m_lastDir = 0; }
   int               ZoneVote(const int grade) const;
   int               Score(const AQSigCtx &c) const;
   int               Evaluate(const AQSigCtx &c, int &scoreOut);
   int               LastDir(void)  const { return(m_lastDir); }
   int               LastBar(void)  const { return(m_lastBar); }
  };

//--- a proven zone is worth three times a weak one
int CAQSignal::ZoneVote(const int grade) const
  {
   if(grade < 0) return(0);
   return(AQ_W_ZONE_MIN + AQ_W_ZONE_STEP * AQ_Clamp(grade, 0, 4));
  }

//+------------------------------------------------------------------+
//| Confluence score, positive = bullish                             |
//+------------------------------------------------------------------+
int CAQSignal::Score(const AQSigCtx &c) const
  {
   int s = 0;

   //--- 1. primary trend rail
   s += c.trend * AQ_W_TREND;

   //--- 2. where price sits against the fast rail
   s += (c.close > c.fast) ? AQ_W_FAST : -AQ_W_FAST;

   //--- 3. swing structure
   s += c.structDir * AQ_W_STRUCT;

   //--- 4. discount / premium inside the live leg (buy low, sell high)
   if(c.legHi > c.legLo)
     {
      double pos = (c.close - c.legLo) / (c.legHi - c.legLo);
      if(pos < 0.40)      s += AQ_W_LEG;
      else if(pos > 0.60) s -= AQ_W_LEG;
     }

   //--- 5. supply / demand context, weighted by how proven the zone is
   if(c.zoneSide != 0) s += c.zoneSide * ZoneVote(c.zoneGrade);

   //--- 6. unfilled imbalance at price
   s += c.fvgSide * AQ_W_FVG;

   //--- 7. higher timeframe agreement
   s += c.mtf1 * AQ_W_MTF;
   s += c.mtf2 * AQ_W_MTF;

   //--- 8. channel tilt and position
   s += c.chanSlope * AQ_W_CHAN_SLOPE;
   if(c.chanPos >= 0.0)
     {
      if(c.chanPos < 0.35)      s += AQ_W_CHAN_POS;
      else if(c.chanPos > 0.65) s -= AQ_W_CHAN_POS;
     }

   return(AQ_Clamp(s, -100, 100));
  }

//+------------------------------------------------------------------+
//| Entry decision: +1 buy, -1 sell, 0 nothing                       |
//+------------------------------------------------------------------+
int CAQSignal::Evaluate(const AQSigCtx &c, int &scoreOut)
  {
   scoreOut = Score(c);

   int dir = 0;
   if(scoreOut >=  m_cfg.minScore) dir =  1;
   if(scoreOut <= -m_cfg.minScore) dir = -1;
   if(dir == 0) return(0);

   //--- never trade against the primary rail, whatever the score says
   if(dir > 0 && c.trend < 0) return(0);
   if(dir < 0 && c.trend > 0) return(0);

   //--- trigger events
   bool pullback = (c.zoneSide == dir) ||
                   (dir > 0 && c.low  <= c.fast) ||
                   (dir < 0 && c.high >= c.fast);
   bool flip     = (c.trend != c.trendPrev);
   bool trigger  = (m_cfg.mode == AQ_SIG_PULLBACK) ? pullback
                 : (m_cfg.mode == AQ_SIG_FLIP)     ? flip
                 : (pullback || flip);
   if(!trigger) return(0);

   //--- closing candle must agree
   if(m_cfg.confirmCandle)
     {
      if(dir > 0 && c.close <= c.open) return(0);
      if(dir < 0 && c.close >= c.open) return(0);
     }

   //--- spacing: a cooldown between any two signals, a longer one before
   //--- repeating the same direction (no arrow spam inside one move)
   if(c.bar - m_lastBar < m_cfg.cooldownBars) return(0);
   if(dir == m_lastDir && !flip && c.bar - m_lastBar < m_cfg.cooldownBars * 3) return(0);

   m_lastBar = c.bar;
   m_lastDir = dir;
   return(dir);
  }

#endif // AQ_SIGNAL_MQH
//+------------------------------------------------------------------+
