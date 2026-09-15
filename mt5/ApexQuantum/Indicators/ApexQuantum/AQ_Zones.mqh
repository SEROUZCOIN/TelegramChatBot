//+------------------------------------------------------------------+
//|                                                     AQ_Zones.mqh |
//|        APEX QUANTUM — Supply & Demand zone engine (CAQZones)     |
//|                                                                  |
//|  Derived from the Shved Supply/Demand method, rebuilt for MQL5:  |
//|   * forward (non-series) indexing throughout — no mixed          |
//|     conventions, no per-call ArraySetAsSeries on shared arrays;  |
//|   * dual fractal resolution (fast = minor swing, slow = major)   |
//|     so a level born on a major swing outranks a minor one;       |
//|   * every candidate level is walked forward to the present:      |
//|     retests promote it, a second break kills it, a single break  |
//|     flips it (support becomes resistance and vice versa);        |
//|   * overlapping survivors are merged so one price area produces  |
//|     one zone, not a stack of near-duplicates.                    |
//+------------------------------------------------------------------+
#ifndef AQ_ZONES_MQH
#define AQ_ZONES_MQH

#include "AQ_Core.mqh"

#define AQ_ZONE_MAX      256          // hard ceiling on tracked zones
#define AQ_ZONE_SKIP       5          // most recent bars ignored (level not yet formed)
#define AQ_ZONE_GAP       10          // bars that must separate two counted retests

//+------------------------------------------------------------------+
//| Configuration                                                    |
//+------------------------------------------------------------------+
struct AQZoneCfg
  {
   int               lookback;        // bars scanned for level birth
   double            fastFactor;      // minor fractal width factor
   double            slowFactor;      // major fractal width factor
   double            fuzz;            // zone thickness, in ATR halves
   bool              merge;           // merge overlapping zones
   bool              extend;          // pad the zone by the fuzz distance
   bool              showWeak;        // draw weak zones
   bool              showFresh;       // draw untested zones
   bool              showBroken;      // draw flipped (turncoat) zones
   int               maxDraw;         // max zones drawn, nearest price first
   bool              solid;           // fill zone rectangles
   int               lineWidth;       // zone border width
   ENUM_LINE_STYLE   style;           // zone border style
   bool              labels;          // draw the grade caption
  };

//+------------------------------------------------------------------+
//| CAQZones                                                         |
//+------------------------------------------------------------------+
class CAQZones
  {
private:
   AQZoneCfg         m_cfg;
   int               m_halfFast;      // fast fractal half-window, in bars
   int               m_halfSlow;      // slow fractal half-window, in bars
   int               m_base;          // first scanned bar index
   int               m_size;          // scanned window length
   double            m_fu[], m_fd[];  // minor fractal highs / lows (window-local)
   double            m_su[], m_sd[];  // major fractal highs / lows (window-local)
   AQZone            m_zone[];
   int               m_count;
   AQZone            m_tmp[];
   int               m_tmpCount;
   bool              m_tmpDead[];     // merged-away marker

   //--- window-local fractal accessors (0.0 outside the window)
   double            FU(const int bar) const { int k = bar - m_base; return((k >= 0 && k < m_size) ? m_fu[k] : 0.0); }
   double            FD(const int bar) const { int k = bar - m_base; return((k >= 0 && k < m_size) ? m_fd[k] : 0.0); }
   double            SU(const int bar) const { int k = bar - m_base; return((k >= 0 && k < m_size) ? m_su[k] : 0.0); }
   double            SD(const int bar) const { int k = bar - m_base; return((k >= 0 && k < m_size) ? m_sd[k] : 0.0); }

   bool              IsFractal(const bool up, const int half, const int bar, const int total,
                               const double &high[], const double &low[]) const;
   void              BuildFractals(const int total, const double &high[], const double &low[]);
   void              BuildZone(const bool fromHigh, const int b, const int total,
                               const double &high[], const double &low[],
                               const double &close[], const double &atr[]);
   void              MergeOverlaps(void);
   void              Finalize(const int total, const datetime &time[], const double &close[]);
   int               GradeOf(const int tests, const bool flipped, const bool weak) const;
   color             ZoneColor(const AQZone &z) const;
   string            GradeName(const int grade) const;

public:
                     CAQZones(void) : m_count(0), m_tmpCount(0), m_base(0), m_size(0),
                                      m_halfFast(8), m_halfSlow(15) {}
   void              Configure(const AQZoneCfg &cfg) { m_cfg = cfg; }
   bool              Calculate(const int total, const datetime &time[], const double &high[],
                               const double &low[], const double &close[], const double &atr[]);
   void              Render(const int total, const datetime &time[]);
   void              Erase(void) { AQ_DeleteGroup("Z"); }
   int               Count(void) const { return(m_count); }
   bool              At(const int i, AQZone &z) const;
   int               Context(const double price, const int upToBar, const double tol, int &grade) const;
   bool              Nearest(const int kind, const double price, AQZone &z) const;
  };

//+------------------------------------------------------------------+
//| Fractal test: bar is the extreme of a 2*half+1 window            |
//| Left side allows equality, right side does not — the original    |
//| asymmetry, which prevents a flat double-top from producing two   |
//| competing levels.                                                |
//+------------------------------------------------------------------+
bool CAQZones::IsFractal(const bool up, const int half, const int bar, const int total,
                         const double &high[], const double &low[]) const
  {
   if(bar < half || bar + half > total - 1) return(false);
   for(int i = 1; i <= half; i++)
     {
      if(up)
        {
         if(high[bar - i] >  high[bar]) return(false);
         if(high[bar + i] >= high[bar]) return(false);
        }
      else
        {
         if(low[bar - i] <  low[bar]) return(false);
         if(low[bar + i] <= low[bar]) return(false);
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Fractal pre-pass over the scan window                            |
//+------------------------------------------------------------------+
void CAQZones::BuildFractals(const int total, const double &high[], const double &low[])
  {
   ArrayResize(m_fu, m_size); ArrayResize(m_fd, m_size);
   ArrayResize(m_su, m_size); ArrayResize(m_sd, m_size);
   ArrayInitialize(m_fu, 0.0); ArrayInitialize(m_fd, 0.0);
   ArrayInitialize(m_su, 0.0); ArrayInitialize(m_sd, 0.0);

   int from = (int)MathMax(m_base, m_halfSlow);
   int to   = total - 1 - m_halfFast;
   for(int b = from; b <= to; b++)
     {
      int k = b - m_base;
      if(k < 0 || k >= m_size) continue;
      if(IsFractal(true,  m_halfFast, b, total, high, low)) m_fu[k] = high[b];
      if(IsFractal(false, m_halfFast, b, total, high, low)) m_fd[k] = low[b];
      if(b + m_halfSlow <= total - 1)
        {
         if(IsFractal(true,  m_halfSlow, b, total, high, low)) m_su[k] = high[b];
         if(IsFractal(false, m_halfSlow, b, total, high, low)) m_sd[k] = low[b];
        }
     }
  }

//+------------------------------------------------------------------+
//| Grade a survivor                                                 |
//+------------------------------------------------------------------+
int CAQZones::GradeOf(const int tests, const bool flipped, const bool weak) const
  {
   if(tests > 3)  return(AQ_GRADE_PROVEN);
   if(tests > 0)  return(AQ_GRADE_TESTED);
   if(flipped)    return(AQ_GRADE_BROKEN);
   if(!weak)      return(AQ_GRADE_FRESH);
   return(AQ_GRADE_WEAK);
  }

//+------------------------------------------------------------------+
//| Birth a candidate level at bar b and walk it forward to now      |
//+------------------------------------------------------------------+
void CAQZones::BuildZone(const bool fromHigh, const int b, const int total,
                         const double &high[], const double &low[],
                         const double &close[], const double &atr[])
  {
   double a = atr[b];
   if(a <= 0.0) return;

   double fz   = a * 0.5 * m_cfg.fuzz;               // half-thickness of the zone
   bool   weak = fromHigh ? (SU(b) <= 0.0) : (SD(b) <= 0.0);
   double hival, loval;

   if(fromHigh)
     {
      hival = high[b] + (m_cfg.extend ? fz : 0.0);
      loval = MathMax(MathMin(close[b], high[b] - fz), high[b] - fz * 2.0);
     }
   else
     {
      loval = low[b] - (m_cfg.extend ? fz : 0.0);
      hival = MathMin(MathMax(close[b], low[b] + fz), low[b] + fz * 2.0);
     }
   if(hival <= loval) return;

   bool turned = false, flipped = false, dead = false;
   int  breaks = 0, tests = 0;

   for(int i = b + 1; i < total; i++)
     {
      //--- which fractal series marks a retest depends on the side price is on now
      bool   useUp = fromHigh ? !turned : turned;
      double pv    = useUp ? FU(i) : FD(i);

      if(pv > 0.0 && pv >= loval && pv <= hival)
        {
         //--- a retest only counts when it is separated from the previous one
         bool ok = true;
         for(int j = i - 1; j > i - AQ_ZONE_GAP - 1 && j > b; j--)
           {
            double pj = useUp ? FU(j) : FD(j);
            if(pj > 0.0 && pj >= loval && pj <= hival) { ok = false; break; }
           }
         if(ok) { breaks = 0; tests++; }              // a fresh retest clears a prior break
        }

      bool broken = fromHigh ? ((!turned && high[i] > hival) || ( turned && low[i] < loval))
                             : (( turned && high[i] > hival) || (!turned && low[i] < loval));
      if(broken)
        {
         breaks++;
         if(breaks > 1 || weak) { dead = true; break; }  // broken twice — the level is gone
         turned  = !turned;                              // broken once — it flips side
         flipped = true;
         tests   = 0;
        }
     }
   if(dead) return;

   if(m_tmpCount >= AQ_ZONE_MAX) return;
   ArrayResize(m_tmp,     m_tmpCount + 1, 64);   // reserve: no realloc storm on a busy window
   ArrayResize(m_tmpDead, m_tmpCount + 1, 64);
   m_tmp[m_tmpCount].hi        = hival;
   m_tmp[m_tmpCount].lo        = loval;
   m_tmp[m_tmpCount].startBar  = b;
   m_tmp[m_tmpCount].startTime = 0;
   m_tmp[m_tmpCount].hits      = tests;
   m_tmp[m_tmpCount].flipped   = flipped;
   m_tmp[m_tmpCount].kind      = AQ_ZONE_DEMAND;     // resolved in Finalize()
   m_tmp[m_tmpCount].grade     = GradeOf(tests, flipped, weak);
   m_tmpDead[m_tmpCount]       = false;
   m_tmpCount++;
  }

//+------------------------------------------------------------------+
//| Merge overlapping survivors (up to 3 passes — a merge can create |
//| a wider box that now overlaps a third zone)                      |
//+------------------------------------------------------------------+
void CAQZones::MergeOverlaps(void)
  {
   for(int pass = 0; pass < 3; pass++)
     {
      int merges = 0;
      for(int i = 0; i < m_tmpCount - 1; i++)
        {
         if(m_tmpDead[i]) continue;
         for(int j = i + 1; j < m_tmpCount; j++)
           {
            if(m_tmpDead[j]) continue;
            bool overlap = (m_tmp[i].hi >= m_tmp[j].lo && m_tmp[i].lo <= m_tmp[j].hi);
            if(!overlap) continue;

            m_tmp[i].hi       = MathMax(m_tmp[i].hi, m_tmp[j].hi);
            m_tmp[i].lo       = MathMin(m_tmp[i].lo, m_tmp[j].lo);
            m_tmp[i].hits    += m_tmp[j].hits;
            m_tmp[i].startBar = (int)MathMin(m_tmp[i].startBar, m_tmp[j].startBar);
            m_tmp[i].grade    = (int)MathMax(m_tmp[i].grade, m_tmp[j].grade);

            //--- two independent levels landing on the same price area is itself
            //--- evidence the area matters
            if(m_tmp[i].hits == 0 && !m_tmp[i].flipped)
              {
               m_tmp[i].hits = 1;
               if(m_tmp[i].grade < AQ_GRADE_TESTED) m_tmp[i].grade = AQ_GRADE_TESTED;
              }
            if(m_tmp[i].hits > 3) m_tmp[i].grade = AQ_GRADE_PROVEN;
            if(!m_tmp[i].flipped || !m_tmp[j].flipped) m_tmp[i].flipped = false;

            m_tmpDead[j] = true;
            merges++;
           }
        }
      if(merges == 0) break;
     }
  }

//+------------------------------------------------------------------+
//| Classify side, stamp times, order by distance to price           |
//+------------------------------------------------------------------+
void CAQZones::Finalize(const int total, const datetime &time[], const double &close[])
  {
   m_count = 0;
   ArrayResize(m_zone, m_tmpCount);
   double ref = close[total - 1 - AQ_ZONE_SKIP];

   for(int i = 0; i < m_tmpCount; i++)
     {
      if(m_tmpDead[i]) continue;
      AQZone z = m_tmp[i];

      if(z.hi < ref)      z.kind = AQ_ZONE_DEMAND;   // wholly below price -> support
      else if(z.lo > ref) z.kind = AQ_ZONE_SUPPLY;   // wholly above price -> resistance
      else
        {
         //--- price is inside the zone: the side it came from decides
         z.kind = AQ_ZONE_DEMAND;
         for(int j = total - 1 - AQ_ZONE_SKIP; j >= m_base; j--)
           {
            if(close[j] < z.lo) { z.kind = AQ_ZONE_SUPPLY; break; }
            if(close[j] > z.hi) { z.kind = AQ_ZONE_DEMAND; break; }
           }
        }
      z.startTime = time[AQ_Clamp(z.startBar, 0, total - 1)];
      m_zone[m_count++] = z;
     }
   ArrayResize(m_zone, (int)MathMax(m_count, 1));

   //--- insertion sort, nearest to price first (drives rendering priority)
   double px = close[total - 1];
   for(int i = 1; i < m_count; i++)
     {
      AQZone key = m_zone[i];
      double kd  = MathMin(MathAbs(key.hi - px), MathAbs(key.lo - px));
      int j = i - 1;
      while(j >= 0 && MathMin(MathAbs(m_zone[j].hi - px), MathAbs(m_zone[j].lo - px)) > kd)
        {
         m_zone[j + 1] = m_zone[j];
         j--;
        }
      m_zone[j + 1] = key;
     }
  }

//+------------------------------------------------------------------+
//| Full recalculation (call on a new bar, not on every tick)        |
//+------------------------------------------------------------------+
bool CAQZones::Calculate(const int total, const datetime &time[], const double &high[],
                         const double &low[], const double &close[], const double &atr[])
  {
   m_count = 0; m_tmpCount = 0;
   if(total < 60) return(false);

   m_halfFast = (int)MathRound(m_cfg.fastFactor * 2.0 + MathCeil(m_cfg.fastFactor * 0.5));
   m_halfSlow = (int)MathRound(m_cfg.slowFactor * 2.0 + MathCeil(m_cfg.slowFactor * 0.5));
   m_halfFast = (int)MathMax(m_halfFast, 2);
   m_halfSlow = (int)MathMax(m_halfSlow, m_halfFast + 1);

   m_base = (int)MathMax(1, total - 1 - m_cfg.lookback);
   m_size = total - m_base;
   if(m_size < m_halfSlow * 4) return(false);

   BuildFractals(total, high, low);

   int endBar = total - 1 - AQ_ZONE_SKIP;
   for(int b = m_base; b <= endBar; b++)
     {
      if(FU(b) > 0.0)      BuildZone(true,  b, total, high, low, close, atr);
      else if(FD(b) > 0.0) BuildZone(false, b, total, high, low, close, atr);
     }

   if(m_cfg.merge) MergeOverlaps();
   Finalize(total, time, close);
   return(true);
  }

//+------------------------------------------------------------------+
//| Accessors                                                        |
//+------------------------------------------------------------------+
bool CAQZones::At(const int i, AQZone &z) const
  {
   if(i < 0 || i >= m_count) return(false);
   z = m_zone[i];
   return(true);
  }

//--- +1 price is inside a demand zone, -1 inside a supply zone, 0 neither.
//--- upToBar keeps history evaluation honest: a zone cannot influence a bar
//--- that closed before the zone existed.
int CAQZones::Context(const double price, const int upToBar, const double tol, int &grade) const
  {
   grade = -1;
   int side = 0;
   for(int i = 0; i < m_count; i++)
     {
      if(m_zone[i].startBar > upToBar) continue;
      if(price < m_zone[i].lo - tol || price > m_zone[i].hi + tol) continue;
      if(m_zone[i].grade > grade)
        {
         grade = m_zone[i].grade;
         side  = (m_zone[i].kind == AQ_ZONE_DEMAND) ? 1 : -1;
        }
     }
   return(side);
  }

//--- nearest zone of a kind: demand below price, supply above price
bool CAQZones::Nearest(const int kind, const double price, AQZone &z) const
  {
   bool found = false;
   double best = 0.0;
   for(int i = 0; i < m_count; i++)
     {
      if(m_zone[i].kind != kind) continue;
      if(kind == AQ_ZONE_DEMAND)
        {
         if(m_zone[i].lo > price) continue;
         if(!found || m_zone[i].hi > best) { best = m_zone[i].hi; z = m_zone[i]; found = true; }
        }
      else
        {
         if(m_zone[i].hi < price) continue;
         if(!found || m_zone[i].lo < best) { best = m_zone[i].lo; z = m_zone[i]; found = true; }
        }
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| Presentation                                                     |
//+------------------------------------------------------------------+
color CAQZones::ZoneColor(const AQZone &z) const
  {
   if(z.kind == AQ_ZONE_DEMAND)
      switch(z.grade)
        {
         case AQ_GRADE_PROVEN: return(AQ_CLR_DEM_PROVEN);
         case AQ_GRADE_TESTED: return(AQ_CLR_DEM_TESTED);
         case AQ_GRADE_FRESH:  return(AQ_CLR_DEM_FRESH);
         case AQ_GRADE_BROKEN: return(AQ_CLR_DEM_BROKEN);
         default:              return(AQ_CLR_DEM_WEAK);
        }
   switch(z.grade)
     {
      case AQ_GRADE_PROVEN: return(AQ_CLR_SUP_PROVEN);
      case AQ_GRADE_TESTED: return(AQ_CLR_SUP_TESTED);
      case AQ_GRADE_FRESH:  return(AQ_CLR_SUP_FRESH);
      case AQ_GRADE_BROKEN: return(AQ_CLR_SUP_BROKEN);
      default:              return(AQ_CLR_SUP_WEAK);
     }
  }

string CAQZones::GradeName(const int grade) const
  {
   switch(grade)
     {
      case AQ_GRADE_PROVEN: return("PROVEN");
      case AQ_GRADE_TESTED: return("TESTED");
      case AQ_GRADE_FRESH:  return("FRESH");
      case AQ_GRADE_BROKEN: return("FLIPPED");
     }
   return("WEAK");
  }

void CAQZones::Render(const int total, const datetime &time[])
  {
   AQ_DeleteGroup("Z");
   if(m_count <= 0) return;

   datetime tEnd = time[total - 1] + (datetime)(PeriodSeconds() * AQ_ZONE_EXT_BARS);
   int drawn = 0;

   for(int i = 0; i < m_count && drawn < m_cfg.maxDraw; i++)
     {
      if(m_zone[i].grade == AQ_GRADE_WEAK   && !m_cfg.showWeak)   continue;
      if(m_zone[i].grade == AQ_GRADE_FRESH  && !m_cfg.showFresh)  continue;
      if(m_zone[i].grade == AQ_GRADE_BROKEN && !m_cfg.showBroken) continue;

      string id  = "Z" + (string)i;
      color  clr = ZoneColor(m_zone[i]);
      AQ_DrawZone(id, m_zone[i].startTime, m_zone[i].hi, tEnd, m_zone[i].lo,
                  clr, m_cfg.solid, m_cfg.lineWidth, m_cfg.style);

      if(m_cfg.labels)
        {
         string caption = GradeName(m_zone[i].grade) + " " +
                          (m_zone[i].kind == AQ_ZONE_DEMAND ? "DEMAND" : "SUPPLY");
         if(m_zone[i].hits > 0) caption += "  x" + (string)m_zone[i].hits;
         AQ_DrawText("ZT" + (string)i, tEnd, m_zone[i].hi, caption,
                     clr, AQ_FS_SM, ANCHOR_RIGHT_LOWER, AQ_FONT);
        }
      drawn++;
     }
  }

#endif // AQ_ZONES_MQH
//+------------------------------------------------------------------+
