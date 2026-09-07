//+------------------------------------------------------------------+
//|                                                    NGZ_State.mqh |
//|                        Neuro Gann Zones - STATE layer             |
//|  All mutable runtime data of the indicator lives in exactly two   |
//|  global objects: g_s (state) and g_net (network weights).         |
//+------------------------------------------------------------------+
#ifndef __NGZ_STATE_MQH__
#define __NGZ_STATE_MQH__

#include "NGZ_Config.mqh"

//+------------------------------------------------------------------+
//| A Gann anchor: a confirmed pivot the geometry is projected from.  |
//| 'unit' is FROZEN at confirmation time so every line derived from  |
//| this anchor keeps the same slope forever  ->  no repainting.      |
//+------------------------------------------------------------------+
struct NgzAnchor
  {
   bool              valid;      // anchor is usable
   bool              isLow;      // true = swing low (bull anchor), false = swing high
   int               bar;        // bar index inside the OnCalculate arrays
   datetime          time;       // bar open time (index-independent reference)
   double            price;      // pivot price
   double            unit;       // price movement per bar for the 1x1 ray
   bool              broken;     // 1x1 rail invalidated by a close beyond it
  };

//+------------------------------------------------------------------+
//| Feed-forward network: NGZ_FEATURES -> hidden(tanh) -> 1(tanh)     |
//| Plain-old-data on purpose: it can be dumped with FileWriteStruct. |
//+------------------------------------------------------------------+
struct NgzNet
  {
   int               nIn;                                // input neurons
   int               nHid;                               // hidden neurons
   double            w1[NGZ_HIDDEN_MAX*NGZ_FEATURES];    // input  -> hidden
   double            b1[NGZ_HIDDEN_MAX];                 // hidden bias
   double            w2[NGZ_HIDDEN_MAX];                 // hidden -> output
   double            b2;                                 // output bias
   int               samples;                            // samples used for training
   int               epochs;                             // epochs performed
   double            loss;                               // final mean squared error
   double            accuracy;                           // directional hit-rate in sample
  };

//+------------------------------------------------------------------+
//| Whole-indicator runtime state                                    |
//+------------------------------------------------------------------+
struct NgzState
  {
   //--- geometry
   double            unit;             // live price unit (price per bar) for the 1x1 ray
   NgzAnchor         bullAnchor;       // rolling bull anchor used by the Up rail
   NgzAnchor         bearAnchor;       // rolling bear anchor used by the Down rail
   double            swingLo;          // master range low
   double            swingHi;          // master range high
   datetime          swingLoTime;
   datetime          swingHiTime;
   int               swingLoBar;
   int               swingHiBar;
   //--- scores of the last closed bar
   double            neuro;
   double            maths;
   double            gann;
   double            fused;
   double            prevFused;
   int               bias;             // +1 up, -1 down, 0 flat
   //--- derived readings for the dashboard
   double            railUp;
   double            railDn;
   double            sq9Above;
   double            sq9Below;
   int               nextCycleBars;
   int               nextCycleLen;
   double            sq9Scale;
   //--- neural layer
   bool              netReady;
   bool              netTried;         // a training attempt already happened for this history
   //--- feature cache addressing
   int               featBase;         // first bar index cached in g_feat
   //--- UI state (seeded from inputs in OnInit, owned by STATE afterwards)
   bool              showFan;
   bool              showSq9;
   bool              showZones;
   bool              showCycles;
   bool              showRetrace;
   bool              showPanel;
   bool              collapsed;
   //--- last bar snapshot (lets the drawing layer run outside OnCalculate)
   int               lastBar;
   datetime          lastBarTime;
   double            lastClose;
   double            atrNow;
   //--- housekeeping
   bool              needRedraw;
   datetime          lastDrawBar;
   datetime          lastAlertBar;
   int               lastAlertDir;
   int               warmup;
   int               dpi;
   string            prefix;
  };

//--- the only two globals of the whole program
NgzState g_s;
NgzNet   g_net;

//--- per-bar feature cache: [ (bar - g_s.featBase) * NGZ_STRIDE + slot ]
double   g_feat[];

//--- parsed Gann time cycles
int      g_cycles[];
int      g_cycleCount = 0;

//+------------------------------------------------------------------+
//| Reset an anchor to the "not found yet" state                      |
//+------------------------------------------------------------------+
void NgzAnchorClear(NgzAnchor &a)
  {
   a.valid  = false;
   a.isLow  = false;
   a.bar    = -1;
   a.time   = 0;
   a.price  = 0.0;
   a.unit   = 0.0;
   a.broken = false;
  }

//+------------------------------------------------------------------+
//| Reset everything that depends on the price history                |
//+------------------------------------------------------------------+
void NgzStateResetHistory(void)
  {
   NgzAnchorClear(g_s.bullAnchor);
   NgzAnchorClear(g_s.bearAnchor);
   g_s.swingLo     = 0.0;
   g_s.swingHi     = 0.0;
   g_s.swingLoTime = 0;
   g_s.swingHiTime = 0;
   g_s.swingLoBar  = -1;
   g_s.swingHiBar  = -1;
   g_s.neuro       = 0.0;
   g_s.maths       = 0.0;
   g_s.gann        = 0.0;
   g_s.fused       = 0.0;
   g_s.prevFused   = 0.0;
   g_s.bias        = 0;
   g_s.railUp      = 0.0;
   g_s.railDn      = 0.0;
   g_s.sq9Above    = 0.0;
   g_s.sq9Below    = 0.0;
   g_s.nextCycleBars = -1;
   g_s.nextCycleLen  = 0;
   g_s.netReady    = false;
   g_s.netTried    = false;
   g_s.featBase    = 0;
   g_s.lastBar     = -1;
   g_s.lastBarTime = 0;
   g_s.lastClose   = 0.0;
   g_s.atrNow      = 0.0;
   g_s.lastDrawBar = 0;
  }

//+------------------------------------------------------------------+
//| Index of feature slot 'slot' of bar 'bar' inside g_feat           |
//+------------------------------------------------------------------+
int NgzF(const int bar, const int slot)
  {
   return (bar - g_s.featBase) * NGZ_STRIDE + slot;
  }

#endif // __NGZ_STATE_MQH__
//+------------------------------------------------------------------+
