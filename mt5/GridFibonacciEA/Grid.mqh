//+------------------------------------------------------------------+
//|                                                         Grid.mqh |
//|  The cycle engine: open, extend, protect and close one Fibonacci  |
//|  grid basket.                                                     |
//|                                                                   |
//|  Design rules that keep the ladder survivable                     |
//|  --------------------------------------------                     |
//|  * One cycle at a time, so exposure is always knowable.           |
//|  * Every level sits between the first entry and the structural    |
//|    stop — the ladder is bounded by market structure, not by an    |
//|    arbitrary level count.                                          |
//|  * Every position carries the same broker-side stop and the far   |
//|    fib target, so the basket is protected even if the terminal    |
//|    dies mid-cycle.                                                 |
//|  * One fill per bar: a single violent candle cannot fill the      |
//|    whole ladder.                                                   |
//+------------------------------------------------------------------+
#ifndef GFEA_GRID_MQH
#define GFEA_GRID_MQH

#include "Risk.mqh"
#include "Signals.mqh"

//+------------------------------------------------------------------+
//| Price the basket is currently valued against.                    |
//+------------------------------------------------------------------+
double CloseSidePrice(const int dir)
  {
   return SymbolInfoDouble(_Symbol, dir > 0 ? SYMBOL_BID : SYMBOL_ASK);
  }

//--- True once `price` has reached `level` in the basket's favour.
bool ReachedInFavour(const int dir, const double price, const double level)
  {
   if(level <= 0) return false;
   return(dir > 0 ? price >= level : price <= level);
  }

//+------------------------------------------------------------------+
//| Money target for the basket under the selected model.            |
//| Returns 0 when the model is not money-based.                     |
//+------------------------------------------------------------------+
double BasketMoneyTarget(void)
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double byPct  = equity * InpBasketTpPct / 100.0;

   switch(InpBasketTpMode)
     {
      case BTP_MONEY:      return InpBasketTpMoney;
      case BTP_EQUITY_PCT: return byPct;
      case BTP_FIRST_HIT:  return MathMin(InpBasketTpMoney, byPct);
     }
   return 0;   // BTP_FIB_EXTENSION is price-based only
  }

//+------------------------------------------------------------------+
//| Close the cycle and fold it into the statistics.                 |
//+------------------------------------------------------------------+
void FinishCycle(const string why)
  {
   double pl = g_ea.cycle.realised;

   g_ea.stats.cyclesTotal++;
   g_ea.stats.realisedTotal += pl;
   if(pl > 0) g_ea.stats.cyclesWon++;
   if(pl > g_ea.stats.bestCycle)  g_ea.stats.bestCycle  = pl;
   if(pl < g_ea.stats.worstCycle) g_ea.stats.worstCycle = pl;

   Notify(StringFormat("CYCLE CLOSED %s", FmtMoney(pl)),
          StringFormat("%s | %d level(s) | %s", DirText(g_ea.cycle.dir), g_ea.cycle.levels, why),
          true);

   CycleReset(TimeCurrent());
  }

void CloseCycle(const string why)
  {
   CloseAllMine(why);
   FinishCycle(why);
  }

//+------------------------------------------------------------------+
//| Open a new cycle on the given leg.                               |
//+------------------------------------------------------------------+
bool OpenCycle(const int dir, const SSwing &s)
  {
   double entry = SymbolInfoDouble(_Symbol, dir > 0 ? SYMBOL_ASK : SYMBOL_BID);
   if(entry <= 0) return false;

   //--- structural stop, widened if the broker's minimum distance demands it
   double stop     = StructuralStop(s);
   double stopDist = MathAbs(entry - stop);
   double minDist  = MinStopDistance() * 1.5;
   if(stopDist < minDist)
     {
      stopDist = minDist;
      stop     = NormalizePrice(entry - dir * stopDist);
     }

   //--- an invalidation further away than the whole leg means the geometry
   //--- has already broken down; stand aside rather than size into it
   if(s.range > 0 && stopDist > s.range * 1.5)
     {
      LogInfo("Skipped: structural stop wider than the leg");
      return false;
     }

   double lot = BaseLotForCycle(stopDist);
   if(lot <= 0)
     {
      LogInfo("Skipped: risk-sized lot is below the broker minimum");
      return false;
     }

   double tp1 = FibExtend(s, InpTp1Fib);
   double tp2 = FibExtend(s, InpTp2Fib);
   double tp3 = FibExtend(s, InpTp3Fib);

   //--- level 0 carries the far target broker-side: if the terminal dies,
   //--- the position is still bracketed by a real stop and a real target
   ulong ticket = OpenMarket(dir, lot, stop, tp3, "L0");
   if(ticket == 0) return false;

   double fill = entry;
   if(PositionSelectByTicket(ticket))
      fill = PositionGetDouble(POSITION_PRICE_OPEN);

   g_ea.cycle.active      = true;
   g_ea.cycle.dir         = dir;
   g_ea.cycle.levels      = 1;
   g_ea.cycle.anchorHi    = s.hi;
   g_ea.cycle.anchorLo    = s.lo;
   g_ea.cycle.anchorDir   = s.dir;
   g_ea.cycle.anchorAtr   = (s.atr > 0 ? s.atr : g_ea.view.atr);
   g_ea.cycle.started     = TimeCurrent();
   g_ea.cycle.lastFillBar = iTime(_Symbol, SignalTF(), 0);
   g_ea.cycle.stopPrice   = stop;
   g_ea.cycle.tp1         = tp1;
   g_ea.cycle.tp2         = tp2;
   g_ea.cycle.tp3         = tp3;
   g_ea.cycle.baseLot     = lot;
   g_ea.cycle.firstEntry  = fill;
   g_ea.cycle.riskPerUnit = stopDist;
   g_ea.cycle.realised    = 0;
   g_ea.cycle.peakProfit  = 0;
   g_ea.cycle.tp1Done     = false;
   g_ea.cycle.tp2Done     = false;
   g_ea.cycle.beDone      = false;

   GridAdd(0, ticket, entry, fill, lot, TimeCurrent());
   PlanNextLevel();

   Notify(StringFormat("CYCLE OPEN %s %s", DirText(dir), FmtLots(lot)),
          StringFormat("entry %s | stop %s | tp %s / %s / %s | retr %.3f",
                       FmtPrice(fill), FmtPrice(stop),
                       FmtPrice(tp1), FmtPrice(tp2), FmtPrice(tp3),
                       RetracementOf(s, fill)),
          true);
   return true;
  }

//+------------------------------------------------------------------+
//| Where the next ladder step sits. 0 = the ladder is closed off     |
//| because the next step would sit at or beyond invalidation.       |
//+------------------------------------------------------------------+
void PlanNextLevel(void)
  {
   if(!g_ea.cycle.active) { g_ea.cycle.nextPrice = 0; return; }

   int    dir  = g_ea.cycle.dir;
   double atr  = (g_ea.cycle.anchorAtr > 0 ? g_ea.cycle.anchorAtr : g_ea.view.atr);
   double next = GridLevelPrice(dir, g_ea.cycle.anchorHi, g_ea.cycle.anchorLo,
                                g_ea.cycle.firstEntry, g_ea.cycle.levels, atr);

   //--- never ladder into or past the structural stop
   double guardBand = MinStopDistance() * 2.0;
   bool   beyond    = (dir > 0) ? (next <= g_ea.cycle.stopPrice + guardBand)
                                : (next >= g_ea.cycle.stopPrice - guardBand);
   g_ea.cycle.nextPrice = beyond ? 0 : next;
  }

//+------------------------------------------------------------------+
//| Add one ladder step when price trades through the planned level. |
//+------------------------------------------------------------------+
bool MaybeAddGridLevel(void)
  {
   if(!g_ea.cycle.active)        return false;
   if(g_ea.cycle.nextPrice <= 0) return false;

   int    dir   = g_ea.cycle.dir;
   double price = SymbolInfoDouble(_Symbol, dir > 0 ? SYMBOL_ASK : SYMBOL_BID);
   if(price <= 0) return false;

   //--- the level triggers when price trades through it AGAINST the basket
   bool triggered = (dir > 0) ? (price <= g_ea.cycle.nextPrice)
                              : (price >= g_ea.cycle.nextPrice);
   if(!triggered) return false;

   double lots = GridLevelLots(g_ea.cycle.baseLot, g_ea.cycle.levels);
   if(lots <= 0) return false;
   if(!CanAddGridLevel(lots, g_ea.cycle.riskPerUnit)) return false;

   double planned = g_ea.cycle.nextPrice;
   ulong  ticket  = OpenMarket(dir, lots, g_ea.cycle.stopPrice, g_ea.cycle.tp3,
                               StringFormat("L%d", g_ea.cycle.levels));
   if(ticket == 0) return false;

   double fill = price;
   if(PositionSelectByTicket(ticket))
      fill = PositionGetDouble(POSITION_PRICE_OPEN);

   GridAdd(g_ea.cycle.levels, ticket, planned, fill, lots, TimeCurrent());
   g_ea.cycle.levels++;
   g_ea.cycle.lastFillBar = iTime(_Symbol, SignalTF(), 0);

   //--- a new level resets break-even: the basket average has moved
   g_ea.cycle.beDone = false;
   PlanNextLevel();

   Notify(StringFormat("GRID L%d %s %s", g_ea.cycle.levels - 1, DirText(dir), FmtLots(lots)),
          StringFormat("fill %s | avg %s | float %s",
                       FmtPrice(fill), FmtPrice(BasketAvgPrice()), FmtMoney(BasketProfit())),
          false);
   return true;
  }

//+------------------------------------------------------------------+
//| Partial profit taking on the fib extension ladder.                |
//+------------------------------------------------------------------+
void ManagePartials(void)
  {
   if(!g_ea.cycle.active) return;
   int    dir   = g_ea.cycle.dir;
   double price = CloseSidePrice(dir);

   //--- The flag is set whether or not volume actually moved. A basket at
   //--- the broker minimum cannot be split; without this the check would
   //--- re-fire on every tick for the rest of the cycle.
   if(!g_ea.cycle.tp1Done && InpTp1ClosePct > 0 &&
      ReachedInFavour(dir, price, g_ea.cycle.tp1))
     {
      double done = ClosePartialBasket(InpTp1ClosePct, "TP1 fib 1.272");
      g_ea.cycle.tp1Done = true;
      if(done > 0)
         Notify("TP1 TAKEN", StringFormat("%.2f lots at %s",
                done, FmtPrice(g_ea.cycle.tp1)), true);
      else
         LogInfo("TP1 reached but the basket is too small to split - running on");
     }

   if(g_ea.cycle.tp1Done && !g_ea.cycle.tp2Done && InpTp2ClosePct > 0 &&
      ReachedInFavour(dir, price, g_ea.cycle.tp2))
     {
      double done = ClosePartialBasket(InpTp2ClosePct, "TP2 fib 1.618");
      g_ea.cycle.tp2Done = true;
      if(done > 0)
         Notify("TP2 TAKEN", StringFormat("%.2f lots at %s",
                done, FmtPrice(g_ea.cycle.tp2)), true);
      else
         LogInfo("TP2 reached but the basket is too small to split - running on");
     }
  }

//+------------------------------------------------------------------+
//| Break-even, measured on the basket average rather than on the    |
//| first entry — which is the only meaningful reference once the    |
//| ladder has more than one step.                                    |
//+------------------------------------------------------------------+
void ManageBreakEven(void)
  {
   if(!InpUseBreakEven || !g_ea.cycle.active || g_ea.cycle.beDone) return;
   if(g_ea.cycle.riskPerUnit <= 0) return;

   int    dir   = g_ea.cycle.dir;
   double avg   = BasketAvgPrice();
   double price = CloseSidePrice(dir);
   if(avg <= 0 || price <= 0) return;

   double moved = (price - avg) * dir;
   if(moved < InpBeTriggerR * g_ea.cycle.riskPerUnit) return;

   double be = NormalizePrice(avg + dir * InpBeOffsetPoints * g_ea.point);
   if(SetBasketStop(be) > 0)
     {
      g_ea.cycle.stopPrice = be;
      g_ea.cycle.beDone    = true;
      Notify("BREAK EVEN", StringFormat("stop moved to %s", FmtPrice(be)), false);
     }
  }

//+------------------------------------------------------------------+
//| Trailing: ATR distance, or a step up the fib extension ladder.   |
//+------------------------------------------------------------------+
void ManageTrailing(void)
  {
   if(InpTrailMode == TRAIL_OFF || !g_ea.cycle.active) return;

   int    dir   = g_ea.cycle.dir;
   double price = CloseSidePrice(dir);
   if(price <= 0) return;

   double want = 0;

   if(InpTrailMode == TRAIL_ATR)
     {
      double atr = (g_ea.view.atr > 0 ? g_ea.view.atr : g_ea.cycle.anchorAtr);
      if(atr <= 0) return;
      want = NormalizePrice(price - dir * atr * InpTrailAtr);
     }
   else // TRAIL_FIB_STEP — lock in each extension as the next is reached
     {
      double avg = BasketAvgPrice();
      if(ReachedInFavour(dir, price, g_ea.cycle.tp3))      want = g_ea.cycle.tp2;
      else if(ReachedInFavour(dir, price, g_ea.cycle.tp2)) want = g_ea.cycle.tp1;
      else if(ReachedInFavour(dir, price, g_ea.cycle.tp1)) want = avg;
      if(want > 0) want = NormalizePrice(want);
     }

   if(want <= 0) return;

   //--- only ever improve, and only by more than the step, so we do not
   //--- hammer the server with micro-modifications (retcode 10024)
   double step = InpTrailStepPts * g_ea.point;
   bool better = (g_ea.cycle.stopPrice <= 0) ||
                 (dir > 0 ? want > g_ea.cycle.stopPrice + step
                          : want < g_ea.cycle.stopPrice - step);
   if(!better) return;

   if(SetBasketStop(want) > 0)
      g_ea.cycle.stopPrice = want;
  }

//+------------------------------------------------------------------+
//| Whole-basket exit checks, in order of severity.                  |
//| Returns true when the cycle was closed and must not be managed   |
//| further this tick.                                                |
//+------------------------------------------------------------------+
bool ManageBasketExit(void)
  {
   if(!g_ea.cycle.active) return false;

   int    dir     = g_ea.cycle.dir;
   double price   = CloseSidePrice(dir);
   double floating= BasketProfit();
   double total   = floating + g_ea.cycle.realised;

   if(total > g_ea.cycle.peakProfit) g_ea.cycle.peakProfit = total;

   //--- 1. cycle loss ceiling — the grid's hard stop before the broker's
   double maxLoss = AccountInfoDouble(ACCOUNT_EQUITY) * InpCycleMaxLossPct / 100.0;
   if(InpCycleMaxLossPct > 0 && -total >= maxLoss)
     {
      CloseCycle(StringFormat("cycle loss %.2f >= %.2f", -total, maxLoss));
      return true;
     }

   //--- 2. end of week
   if(IsFridayCloseTime())
     {
      CloseCycle("Friday session close");
      return true;
     }

   //--- 3. money target
   double moneyTarget = BasketMoneyTarget();
   if(moneyTarget > 0 && total >= moneyTarget)
     {
      CloseCycle(StringFormat("basket target %s", FmtMoney(total)));
      return true;
     }

   //--- 4. final fib extension
   if((InpBasketTpMode == BTP_FIB_EXTENSION || InpBasketTpMode == BTP_FIRST_HIT) &&
      ReachedInFavour(dir, price, g_ea.cycle.tp3))
     {
      CloseCycle(StringFormat("fib 2.618 target %s", FmtPrice(g_ea.cycle.tp3)));
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Per-tick cycle management, called after the guards have passed.  |
//+------------------------------------------------------------------+
void ManageCycle(void)
  {
   if(!g_ea.cycle.active) return;

   //--- the broker may have closed everything (stop, target, manual, margin)
   if(CountMyPositions() == 0)
     {
      FinishCycle("no positions remain");
      return;
     }

   if(ManageBasketExit()) return;

   ManagePartials();
   ManageBreakEven();
   ManageTrailing();
   MaybeAddGridLevel();
  }

//+------------------------------------------------------------------+
//| Rebuild cycle state from live positions after a restart.         |
//| Without this, a terminal restart mid-cycle would leave a basket  |
//| running with no manager.                                          |
//+------------------------------------------------------------------+
void AdoptExistingBasket(void)
  {
   int n = CountMyPositions();
   if(n == 0) return;

   int dir = BasketDirection();
   if(dir == 0)
     {
      Notify("ADOPTION FAILED", "positions found in both directions - manage manually", true);
      return;
     }

   CycleReset();
   g_ea.cycle.active     = true;
   g_ea.cycle.dir        = dir;
   g_ea.cycle.levels     = n;
   g_ea.cycle.started    = TimeCurrent();
   g_ea.cycle.firstEntry = BasketAvgPrice();
   g_ea.cycle.baseLot    = (n > 0 ? NormalizeVolume(BasketVolume() / n) : g_ea.volMin);
   g_ea.cycle.anchorAtr  = g_ea.view.atr;

   //--- rebuild the ladder from the live positions, oldest level first
   int level = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsMine()) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      GridAdd(level++, t, open, open, PositionGetDouble(POSITION_VOLUME),
              (datetime)PositionGetInteger(POSITION_TIME));

      //--- inherit whatever protection the positions already carry
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl > 0 && (g_ea.cycle.stopPrice <= 0 ||
                    (dir > 0 ? sl < g_ea.cycle.stopPrice : sl > g_ea.cycle.stopPrice)))
         g_ea.cycle.stopPrice = sl;
      if(tp > 0) g_ea.cycle.tp3 = tp;
     }

   if(g_ea.cycle.stopPrice > 0)
      g_ea.cycle.riskPerUnit = MathAbs(g_ea.cycle.firstEntry - g_ea.cycle.stopPrice);

   //--- an adopted basket is managed to its exit but never extended: the
   //--- anchor leg that justified its ladder is gone
   g_ea.cycle.nextPrice = 0;

   Notify(StringFormat("BASKET ADOPTED %s", DirText(dir)),
          StringFormat("%d position(s) | avg %s | float %s",
                       n, FmtPrice(g_ea.cycle.firstEntry), FmtMoney(BasketProfit())),
          true);
  }

#endif // GFEA_GRID_MQH
//+------------------------------------------------------------------+
