//+------------------------------------------------------------------+
//|                                                        State.mqh |
//|  STATE layer: every runtime-mutable value lives here.            |
//|                                                                  |
//|  Rule enforced throughout the project: an `input` can never       |
//|  change at runtime, so anything a button, a Telegram command or   |
//|  a breach handler must be able to flip is SEEDED from the input   |
//|  in OnInit and read from STATE everywhere after that.             |
//+------------------------------------------------------------------+
#ifndef GFEA_STATE_MQH
#define GFEA_STATE_MQH

#include <Arrays\ArrayObj.mqh>
#include "Config.mqh"

//+------------------------------------------------------------------+
//| One executed grid level. Owned by CArrayObj (FreeMode = true).   |
//+------------------------------------------------------------------+
class CGridLevel : public CObject
  {
public:
   int      level;        // 0 = first entry of the cycle
   ulong    ticket;       // position ticket (hedging) or 0 on netting
   double   requested;    // price the level was meant to fill at
   double   filled;       // price it actually filled at
   double   lots;         // volume of this level
   datetime opened;       // fill time
   double   closedPL;     // realised P/L once this level is gone
   bool     closed;       // level no longer open

                     CGridLevel(void): level(0), ticket(0), requested(0), filled(0),
                                       lots(0), opened(0), closedPL(0), closed(false) {}
                     CGridLevel(const int lv, const ulong tk, const double req,
                                const double fill, const double vol, const datetime t):
                                level(lv), ticket(tk), requested(req), filled(fill),
                                lots(vol), opened(t), closedPL(0), closed(false) {}

   //--- No Compare() override. It would only serve CArrayObj::Sort/Search,
   //--- neither of which this project calls: levels are appended in ladder
   //--- order, so insertion order IS level order. Leaving the override out
   //--- also removes a signature that must match CObject exactly across MT5
   //--- builds, which is a compile failure waiting for a terminal we cannot
   //--- test against.
  };

//+------------------------------------------------------------------+
//| The Fibonacci impulse leg the whole cycle is anchored to.        |
//+------------------------------------------------------------------+
struct SSwing
  {
   bool     valid;        // a tradable leg was found
   int      dir;          // +1 leg up (low -> high), -1 leg down
   double   hi;           // leg high price
   double   lo;           // leg low price
   datetime hiTime;       // leg high bar time
   datetime loTime;       // leg low bar time
   double   range;        // hi - lo
   double   atr;          // ATR at detection time
   datetime found;        // when this leg was accepted
  };

//+------------------------------------------------------------------+
//| Snapshot of the moving-average / regime engine for this bar.     |
//+------------------------------------------------------------------+
struct SMarketView
  {
   double   fast;         // fast MA on the signal timeframe
   double   mid;          // mid MA
   double   slow;         // slow MA
   double   htf;          // higher-timeframe MA
   double   slopeAtr;     // slow-MA slope per bar, normalised by ATR
   double   adx;          // ADX main line
   double   diPlus;       // +DI
   double   diMinus;      // -DI
   double   atr;          // ATR on the signal timeframe
   int      stackDir;     // +1 fast>mid>slow, -1 fast<mid<slow, 0 tangled
   int      htfDir;       // +1 price above HTF MA, -1 below, 0 unknown
   int      bias;         // final directional bias, +1 / -1 / 0
   ENUM_MARKET_REGIME regime;
  };

//+------------------------------------------------------------------+
//| The live grid cycle. One cycle at a time, netting-safe.          |
//+------------------------------------------------------------------+
struct SCycle
  {
   bool     active;       // a basket is open
   int      dir;          // +1 long basket, -1 short basket
   int      levels;       // levels filled so far
   double   anchorHi;     // frozen copy of the leg the cycle was opened on
   double   anchorLo;
   int      anchorDir;
   double   anchorAtr;
   datetime started;      // first fill time
   datetime lastFillBar;  // bar time of the last fill (spacing gate)
   double   nextPrice;    // price the next grid level triggers at
   double   stopPrice;    // shared structural stop for the whole basket
   double   tp1;          // fib extension targets
   double   tp2;
   double   tp3;
   double   baseLot;      // lot of level 0; the ladder scales off it
   double   riskPerUnit;  // first-entry stop distance, the cycle's 1R
   double   firstEntry;   // fill price of level 0
   double   realised;     // P/L already banked by partial closes
   double   peakProfit;   // best unrealised basket profit seen
   bool     tp1Done;      // TP1 partial taken
   bool     tp2Done;      // TP2 partial taken
   bool     beDone;       // stop moved to break-even
   datetime closedAt;     // when the last cycle ended (cooldown gate)
  };

//+------------------------------------------------------------------+
//| Account-protection state (persisted across restarts).            |
//+------------------------------------------------------------------+
struct SGuard
  {
   double   dayStartBalance;  // balance at the current trading day open
   double   dayStartEquity;   // equity at the same moment
   double   peakEquity;       // high-water mark since the EA was attached
   datetime dayStamp;         // midnight of the day the counters belong to
   bool     halted;           // hard halt after a breach
   bool     dailyTargetHit;   // daily profit target reached, resting
   string   haltReason;       // human-readable reason, shown on the panel
  };

//+------------------------------------------------------------------+
//| Rolling statistics for the panel and the Python dashboard.       |
//+------------------------------------------------------------------+
struct SStats
  {
   int      cyclesTotal;      // cycles closed since attach
   int      cyclesWon;        // cycles closed in profit
   double   realisedTotal;    // banked P/L since attach
   double   bestCycle;        // best closed cycle
   double   worstCycle;       // worst closed cycle
   double   maxDDPct;         // worst equity drawdown seen (%)
   int      tradesSent;       // orders sent
   int      tradesFailed;     // orders rejected
  };

//+------------------------------------------------------------------+
//| Top-level EA state — the single global the program declares.     |
//+------------------------------------------------------------------+
struct SEaState
  {
   //--- runtime copies of switchable inputs (never re-read the input)
   bool     tradingEnabled;   // seeded from InpEnableTrading, flipped by the panel
   bool     gridEnabled;      // seeded from InpGridEnable
   bool     panelVisible;     // seeded from InpShowPanel
   bool     telemetryOn;      // seeded from InpTelemetryOn

   //--- indicator handles, created once in OnInit
   int      hMaFast;
   int      hMaMid;
   int      hMaSlow;
   int      hMaHtf;
   int      hAdx;
   int      hAtr;

   //--- cached symbol specification
   double   point;
   int      digits;
   double   tickSize;
   double   tickValue;
   double   volMin;
   double   volMax;
   double   volStep;
   bool     hedging;          // account is hedging, not netting

   //--- bar / timing gates
   datetime lastBar;          // last processed signal-TF bar
   datetime lastTelemetry;    // last telemetry push
   uint     lastPanelTick;    // GetTickCount of the last panel refresh
   int      ledPhase;         // animated status LED phase
   int      chartW;           // last chart width, for right-docked relayout

   //--- working views
   SSwing      swing;
   SMarketView view;
   SCycle      cycle;
   SGuard      guard;
   SStats      stats;

   //--- last human-readable action, echoed on the panel
   string   lastEvent;
  };

//--- The only globals the program introduces.
SEaState  g_ea;
CArrayObj g_grid;   // owns every CGridLevel of the live cycle

//+------------------------------------------------------------------+
//| Grid collection helpers                                          |
//+------------------------------------------------------------------+
void GridAdd(const int level, const ulong ticket, const double requested,
             const double filled, const double lots, const datetime when)
  {
   CGridLevel *gl = new CGridLevel(level, ticket, requested, filled, lots, when);
   if(gl == NULL) return;
   if(!g_grid.Add(gl)) delete gl;   // failed insert must not leak
  }

CGridLevel *GridFind(const ulong ticket)
  {
   for(int i = 0; i < g_grid.Total(); i++)
     {
      CGridLevel *gl = (CGridLevel*)g_grid.At(i);
      if(gl != NULL && gl.ticket == ticket) return gl;
     }
   return NULL;
  }

void GridClear(void)
  {
   g_grid.Clear();   // FreeMode is true by default: elements are deleted for us
  }

double GridTotalLots(void)
  {
   double sum = 0;
   for(int i = 0; i < g_grid.Total(); i++)
     {
      CGridLevel *gl = (CGridLevel*)g_grid.At(i);
      if(gl != NULL && !gl.closed) sum += gl.lots;
     }
   return sum;
  }

//+------------------------------------------------------------------+
//| Reset the cycle block. Called on attach and after every close.   |
//+------------------------------------------------------------------+
void CycleReset(const datetime closedAt = 0)
  {
   GridClear();
   g_ea.cycle.active      = false;
   g_ea.cycle.dir         = 0;
   g_ea.cycle.levels      = 0;
   g_ea.cycle.anchorHi    = 0;
   g_ea.cycle.anchorLo    = 0;
   g_ea.cycle.anchorDir   = 0;
   g_ea.cycle.anchorAtr   = 0;
   g_ea.cycle.started     = 0;
   g_ea.cycle.lastFillBar = 0;
   g_ea.cycle.nextPrice   = 0;
   g_ea.cycle.stopPrice   = 0;
   g_ea.cycle.tp1         = 0;
   g_ea.cycle.tp2         = 0;
   g_ea.cycle.tp3         = 0;
   g_ea.cycle.baseLot     = 0;
   g_ea.cycle.riskPerUnit = 0;
   g_ea.cycle.firstEntry  = 0;
   g_ea.cycle.realised    = 0;
   g_ea.cycle.peakProfit  = 0;
   g_ea.cycle.tp1Done     = false;
   g_ea.cycle.tp2Done     = false;
   g_ea.cycle.beDone      = false;
   if(closedAt > 0) g_ea.cycle.closedAt = closedAt;
  }

#endif // GFEA_STATE_MQH
//+------------------------------------------------------------------+
