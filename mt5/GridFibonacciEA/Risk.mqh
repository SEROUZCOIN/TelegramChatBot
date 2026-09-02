//+------------------------------------------------------------------+
//|                                                         Risk.mqh |
//|  Position sizing and the account-protection layer.                |
//|                                                                   |
//|  Grid systems do not die from bad entries, they die from an       |
//|  unbounded ladder meeting an unbounded loss. Everything here      |
//|  exists to put a hard ceiling on both.                            |
//+------------------------------------------------------------------+
#ifndef GFEA_RISK_MQH
#define GFEA_RISK_MQH

#include "Execution.mqh"

//+------------------------------------------------------------------+
//| POSITION SIZING                                                  |
//+------------------------------------------------------------------+

//--- Lots that put exactly `riskMoney` at stake over `stopDistance` of price.
double LotsForRisk(const double riskMoney, const double stopDistance)
  {
   if(stopDistance <= 0 || riskMoney <= 0) return 0;
   if(g_ea.tickSize <= 0 || g_ea.tickValue <= 0) return 0;

   double lossPerLot = (stopDistance / g_ea.tickSize) * g_ea.tickValue;
   if(lossPerLot <= 0) return 0;
   return NormalizeVolume(riskMoney / lossPerLot);
  }

//--- Sum of the progression multipliers across the whole planned ladder.
//--- With PROG_FLAT and 6 levels this is 6.0; with PROG_FIBONACCI it is 20.0.
double LadderLotUnits(void)
  {
   int levels = MathMax(1, MathMin(InpGridMaxLevels, MAX_GRID_LEVELS));
   double sum = 0;
   for(int i = 0; i < levels; i++)
     {
      int k = MathMax(0, MathMin(i, 7));
      switch(InpLotProgression)
        {
         case PROG_FLAT:      sum += 1.0;                            break;
         case PROG_LINEAR:    sum += (double)(i + 1);                break;
         case PROG_FIBONACCI: sum += FIB_LOTS[k];                    break;
         case PROG_GEOMETRIC: sum += MathPow(InpLotFactor, i);       break;
        }
     }
   return sum;
  }

//--- Hard ceiling on total basket volume: whichever of the explicit cap and
//--- the risk-budget cap is tighter.
double MaxBasketLots(const double stopDistance)
  {
   double byRisk = 0;
   if(stopDistance > 0)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      byRisk = LotsForRisk(equity * InpMaxTotalRiskPct / 100.0, stopDistance);
     }

   if(InpGridMaxLotTotal > 0 && byRisk > 0) return MathMin(InpGridMaxLotTotal, byRisk);
   if(InpGridMaxLotTotal > 0)               return InpGridMaxLotTotal;
   return byRisk;
  }

//--- The first entry of a cycle. Later levels scale off this base lot.
double BaseLotForCycle(const double stopDistance)
  {
   double lot = 0;
   switch(InpLotMode)
     {
      case LOT_FIXED:
         lot = InpFixedLot;
         break;

      case LOT_RISK_PERCENT:
        {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         lot = LotsForRisk(equity * InpRiskPercent / 100.0, stopDistance);
         break;
        }

      case LOT_PER_BALANCE:
        {
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double steps   = (InpBalanceStep > 0) ? balance / InpBalanceStep : 0;
         lot = InpLotPerBalance * steps;
         break;
        }
     }

   lot = NormalizeVolume(lot);

   //--- A grid multiplies the base lot across the ladder, so the base must
   //--- leave room for the whole ladder, not just for itself.
   double cap = MaxBasketLots(stopDistance);
   double ladderUnits = LadderLotUnits();
   if(ladderUnits > 0 && cap > 0)
      lot = MathMin(lot, NormalizeVolume(cap / ladderUnits));

   if(lot < g_ea.volMin) return 0;      // below the broker minimum: skip, never round up
   return lot;
  }

//--- Would adding `addLots` push the basket past its budget?
bool RiskBudgetAllows(const double addLots, const double stopDistance)
  {
   double cap = MaxBasketLots(stopDistance);
   if(cap <= 0) return true;             // no measurable cap: fall back to level count
   return(BasketVolume() + addLots <= cap + 1e-9);
  }

//+------------------------------------------------------------------+
//| ACCOUNT PROTECTION                                                |
//+------------------------------------------------------------------+
void GuardInit(void)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   g_ea.guard.dayStartBalance = balance;
   g_ea.guard.dayStartEquity  = equity;
   g_ea.guard.peakEquity      = equity;
   g_ea.guard.dayStamp        = DayStart(TimeCurrent());
   g_ea.guard.halted          = false;
   g_ea.guard.dailyTargetHit  = false;
   g_ea.guard.haltReason      = "";
  }

void GuardBreach(const string reason, const bool halt)
  {
   g_ea.guard.haltReason = reason;
   Notify("PROTECTION BREACH", reason, true);

   if(halt && InpHaltOnBreach)
     {
      CloseAllMine(reason);
      CycleReset(TimeCurrent());
      g_ea.guard.halted = true;
      g_ea.tradingEnabled = false;      // STATE owns the runtime switch, not the input
     }
  }

//--- Roll the daily counters over at the server-time day boundary.
void GuardRollDay(void)
  {
   datetime today = DayStart(TimeCurrent());
   if(today <= g_ea.guard.dayStamp) return;

   g_ea.guard.dayStamp        = today;
   g_ea.guard.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_ea.guard.dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_ea.guard.dailyTargetHit  = false;

   //--- a new day clears a soft halt, never a hard drawdown halt
   if(g_ea.guard.halted && StringFind(g_ea.guard.haltReason, "Daily") == 0)
     {
      g_ea.guard.halted     = false;
      g_ea.guard.haltReason = "";
      g_ea.tradingEnabled   = true;
      LogInfo("New trading day: daily halt cleared");
     }
  }

//+------------------------------------------------------------------+
//| Called first on every tick. False means: open nothing new.       |
//| Breaches that require closing positions do so here.              |
//+------------------------------------------------------------------+
bool GuardAllowsTrading(void)
  {
   GuardRollDay();

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_ea.guard.peakEquity) g_ea.guard.peakEquity = equity;

   double ddPct = (g_ea.guard.peakEquity > 0)
                  ? (g_ea.guard.peakEquity - equity) / g_ea.guard.peakEquity * 100.0 : 0;
   if(ddPct > g_ea.stats.maxDDPct) g_ea.stats.maxDDPct = ddPct;

   if(g_ea.guard.halted) return false;

   //--- absolute equity floor
   if(InpMinEquityStop > 0 && equity <= InpMinEquityStop)
     {
      GuardBreach(StringFormat("Equity floor %.2f reached", InpMinEquityStop), true);
      return false;
     }

   //--- total drawdown from the equity high-water mark
   if(InpMaxTotalDDPct > 0 && ddPct >= InpMaxTotalDDPct)
     {
      GuardBreach(StringFormat("Total drawdown %.2f%% >= %.2f%%", ddPct, InpMaxTotalDDPct), true);
      return false;
     }

   //--- daily loss, measured against the day-start balance
   double dayPL = equity - g_ea.guard.dayStartBalance;
   if(InpMaxDailyLossPct > 0)
     {
      double limit = g_ea.guard.dayStartBalance * InpMaxDailyLossPct / 100.0;
      if(-dayPL >= limit)
        {
         GuardBreach(StringFormat("Daily loss %.2f >= %.2f", -dayPL, limit), true);
         return false;
        }
     }

   //--- daily profit target: stop opening, but let live cycles finish
   if(InpMaxDailyProfitPct > 0 && !g_ea.guard.dailyTargetHit)
     {
      double target = g_ea.guard.dayStartBalance * InpMaxDailyProfitPct / 100.0;
      if(dayPL >= target)
        {
         g_ea.guard.dailyTargetHit = true;
         Notify("DAILY TARGET REACHED", StringFormat("Day P/L %.2f", dayPL), true);
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Composite gate for opening a NEW cycle.                          |
//+------------------------------------------------------------------+
bool CanOpenNewCycle(void)
  {
   if(!g_ea.tradingEnabled)        return false;
   if(g_ea.guard.halted)           return false;
   if(g_ea.guard.dailyTargetHit)   return false;
   if(g_ea.cycle.active)           return false;
   if(CountMyPositions() > 0)      return false;   // reconcile before starting fresh
   if(!SpreadOK())                 return false;
   if(!SessionAllowsEntry())       return false;
   if(IsFridayCloseTime())         return false;

   //--- cooldown after the previous cycle, measured in signal-TF bars
   if(InpCooldownBars > 0 && g_ea.cycle.closedAt > 0)
     {
      int barSeconds = PeriodSeconds(SignalTF());
      long elapsed = (long)TimeCurrent() - (long)g_ea.cycle.closedAt;
      if(barSeconds > 0 && elapsed < (long)InpCooldownBars * (long)barSeconds)
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Gate for adding one more level to the LIVE cycle.                |
//+------------------------------------------------------------------+
bool CanAddGridLevel(const double lots, const double stopDistance)
  {
   if(!g_ea.gridEnabled)      return false;
   if(!g_ea.tradingEnabled)   return false;
   if(g_ea.guard.halted)      return false;
   if(!g_ea.cycle.active)     return false;
   if(!SpreadOK())            return false;
   if(IsFridayCloseTime())    return false;

   if(g_ea.cycle.levels >= MathMin(InpGridMaxLevels, MAX_GRID_LEVELS)) return false;
   if(!RiskBudgetAllows(lots, stopDistance)) return false;

   //--- one fill per bar keeps a single violent candle from filling the ladder
   if(g_ea.cycle.lastFillBar == iTime(_Symbol, SignalTF(), 0)) return false;

   return true;
  }

#endif // GFEA_RISK_MQH
//+------------------------------------------------------------------+
