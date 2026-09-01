//+------------------------------------------------------------------+
//|                                      GridBot_2X_AutoUpdate.mq5   |
//| Two-sided limit grid that configures itself from the account,    |
//| the symbol and current volatility.                               |
//+------------------------------------------------------------------+
//
// What "auto" means here
// ----------------------
// With InpAutoConfigure on (the default) you set a risk percentage and the EA
// derives everything else at the start of every cycle:
//
//   * grid distance   from ATR, floored by the symbol's own spread, stops level
//                     and freeze level, so the step is never tighter than the
//                     broker will actually accept
//   * levels per side from what the risk budget can survive
//   * base lot        from the risk budget, the step, and the tick value
//   * multiplier      the preferred one if it fits, otherwise stepped down
//   * profit target,  trail, emergency stop, exposure cap and daily loss limit
//                     as percentages of equity
//
// The solver's contract: if the ladder fills to its deepest level and price
// keeps going one more step, the loss is approximately InpRiskPercentPerCycle
// of equity. If no shape satisfies that on this symbol, the EA refuses to
// start rather than quietly trading a riskier one.
//
// Manual mode (InpAutoConfigure = false) uses the fixed inputs instead, and
// every safety mechanism behaves identically.
//
// Risk note, stated plainly: this is a martingale grid. Lot size grows
// geometrically with depth, so the deepest level of a 5-level 2.0x ladder
// carries 16x the risk of the first. The guards below are real and persistent,
// but they cap a loss, they do not remove it.
//
#property copyright "OpenAI"
#property version   "3.00"

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_GRID_DIRECTION_MODE
{
   GRID_DIRECTION_BOTH = 0,       // Always maintain both sides
   GRID_DIRECTION_SMART_TREND,    // Buy dips in uptrends, sell rallies in downtrends
   GRID_DIRECTION_BUY_ONLY,
   GRID_DIRECTION_SELL_ONLY
};

input group "Auto-configuration"
input bool   InpAutoConfigure             = true;   // Derive the whole ladder from equity
input double InpRiskPercentPerCycle       = 2.0;    // Equity lost if the ladder fills and runs on
input double InpTargetPercentPerCycle     = 0.5;    // Basket profit target, percent of equity
input double InpDailyLossPercent          = 6.0;    // 0=off; daily loss lock, percent of equity
input int    InpMaxLevelsPerSide          = 8;      // Upper bound the solver may choose
input double InpPreferredMultiplier       = 2.0;    // Solver starts here and steps down if needed
input double InpExposureHeadroomPercent   = 20.0;   // Volume cap above the planned ladder

input group "Auto distance"
input bool   InpUseATRGridSpacing         = true;   // Adapt grid distance to volatility
input ENUM_TIMEFRAMES InpATRTimeframe     = PERIOD_M15;
input int    InpATRPeriod                 = 14;
input double InpATRMultiplier             = 1.0;
input bool   InpAutoStepBounds            = true;   // Floor/ceiling from the symbol itself
input double InpStepSpreadFactor          = 4.0;    // Step floor = this many spreads
input int    InpMinimumGridStepPoints     = 150;    // Used when auto bounds are off
input int    InpMaximumGridStepPoints     = 1500;   // Used when auto bounds are off

input group "Manual grid settings (used when auto-configure is off)"
input double InpBaseLot                   = 0.01;   // Lot size at level 1
input int    InpLevelsPerSide             = 5;      // Buy-limit and sell-limit levels
input int    InpGridStepPoints            = 300;    // Distance between levels, in points
input double InpMartingaleMultiplier      = 2.0;    // Lot multiplier (2.0 = 2X)
input double InpMaximumLot                = 5.0;    // Hard lot cap for one order
input double InpBasketProfitMoney         = 10.0;   // Close basket at this floating profit
input double InpTrailStartMoney           = 5.0;    // Start tracking peak basket profit
input double InpTrailGivebackMoney        = 2.0;    // Close after this drop from the peak
input double InpEmergencyLossMoney        = 0.0;    // 0=off; close and pause at this loss
input double InpMaximumTotalVolume        = 1.0;    // Positions + pending lots; 0=unlimited
input double InpDailyLossLimitMoney       = 0.0;    // 0=off; close and lock until next day

input group "Market logic"
input ENUM_GRID_DIRECTION_MODE InpDirectionMode = GRID_DIRECTION_SMART_TREND;
input ENUM_TIMEFRAMES InpTrendTimeframe   = PERIOD_M15;
input int    InpFastEMAPeriod             = 50;
input int    InpSlowEMAPeriod             = 200;
input int    InpTrendGapPoints            = 20;     // Smaller EMA gaps are treated as ranging

input group "Basket exit settings"
input bool   InpUseBasketProfitTrail      = true;   // Protect profit before fixed target
input double InpMaxBasketDrawdownPercent  = 10.0;   // 0=off; percent of account balance
input bool   InpAutoRestartAfterProfit    = true;   // Build a new grid after profit close
input int    InpRestartDelaySeconds       = 3;      // Delay before the next grid
input bool   InpAutoRecenterWhenFlat      = true;   // Move an untouched grid with price
input int    InpRecenterAfterSteps        = 2;      // Recenter after this many grid steps
input int    InpRecenterCooldownSeconds   = 60;     // Minimum gap between recenters

input group "Risk and session controls"
input double InpMinimumMarginLevelPercent = 300.0;  // Block new limits below this; 0=off
input double InpMarginReservePercent      = 200.0;  // Free margin / estimated ladder margin
input double InpCommissionPerLotPerSide   = 0.0;    // 0=learn it from closed deals
input bool   InpUseTradingSession         = false;
input int    InpSessionStartHour          = 0;      // Broker server hour, inclusive
input int    InpSessionEndHour            = 0;      // Same as start means 24 hours
input bool   InpDeletePendingOutsideSession = true;

input group "Execution settings"
input long   InpMagicNumber               = 26082801;
input int    InpMaximumSpreadPoints       = 50;     // 0=do not filter new orders
input ulong  InpDeviationPoints           = 20;

// The EA owns magic numbers InpMagicNumber+1 .. InpMagicNumber+200: one per
// side per level. Identity lives in the magic number, never in the comment,
// because brokers may rewrite or truncate comments and a partial close returns
// an empty one -- which would make the EA read an occupied level as free and
// place a duplicate.
#define GB_LEVEL_SPAN 100

const string SLOT_PREFIX = "GB2X";

//--- cycle state -----------------------------------------------------------
double   g_anchor_price       = 0.0;
double   g_cycle_step_points  = 0.0;
double   g_peak_profit        = 0.0;
bool     g_cycle_closing      = false;
bool     g_pause_after_close  = false;
bool     g_paused             = false;
bool     g_manage_busy        = false;
bool     g_config_provisional = false;
datetime g_next_build_time    = 0;
datetime g_next_recenter_time = 0;
datetime g_daily_lock_until   = 0;

//--- resolved configuration for the current cycle --------------------------
double   g_cfg_base_lot       = 0.0;
int      g_cfg_levels         = 0;
double   g_cfg_multiplier     = 1.0;
double   g_cfg_max_lot        = 0.0;
double   g_cfg_target_money   = 0.0;
double   g_cfg_trail_start    = 0.0;
double   g_cfg_trail_give     = 0.0;
double   g_cfg_emergency      = 0.0;
double   g_cfg_max_volume     = 0.0;
double   g_cfg_daily_loss     = 0.0;

//--- cached history --------------------------------------------------------
double   g_day_realized       = 0.0;
double   g_commission_per_lot = 0.0;
datetime g_day_start_cached   = 0;
bool     g_history_dirty      = true;

//--- indicators and display ------------------------------------------------
int      g_atr_handle         = INVALID_HANDLE;
int      g_fast_ema_handle    = INVALID_HANDLE;
int      g_slow_ema_handle    = INVALID_HANDLE;
string   g_regime_text        = "Initializing";
string   g_status_text        = "Initializing";
string   g_config_text        = "";
datetime g_last_dashboard     = 0;

//--- per-retcode log throttle ----------------------------------------------
uint     g_logged_codes[];
datetime g_logged_times[];

//+------------------------------------------------------------------+
//| Slot identity: encoded in the magic number                       |
//+------------------------------------------------------------------+
long SlotMagic(const bool is_buy, const int level)
{
   return InpMagicNumber + (is_buy ? 0 : GB_LEVEL_SPAN) + level;
}

bool DecodeSlotMagic(const long magic, bool &is_buy, int &level)
{
   long delta = magic - InpMagicNumber;
   if(delta < 1 || delta > 2 * GB_LEVEL_SPAN)
      return false;

   is_buy = (delta <= GB_LEVEL_SPAN);
   level  = (int)(is_buy ? delta : delta - GB_LEVEL_SPAN);
   return (level >= 1 && level <= GB_LEVEL_SPAN);
}

bool IsManagedMagic(const long magic)
{
   bool is_buy = false;
   int  level  = 0;
   return DecodeSlotMagic(magic, is_buy, level);
}

string SlotTag(const bool is_buy, const int level)
{
   // Human-readable label only. Never used to decide whether a slot is filled.
   return StringFormat("%s:%s:%d", SLOT_PREFIX, is_buy ? "B" : "S", level);
}

//+------------------------------------------------------------------+
//| Persistent state                                                 |
//+------------------------------------------------------------------+
string GVName(const string suffix)
{
   string base = StringFormat("GB3_%I64d_%I64d_%s",
                              AccountInfoInteger(ACCOUNT_LOGIN),
                              InpMagicNumber,
                              _Symbol);
   int room = 63 - StringLen(suffix) - 1;
   if(room < 1)
      room = 1;
   if(StringLen(base) > room)
      base = StringSubstr(base, 0, room);
   return base + "_" + suffix;
}

void GVWrite(const string suffix, const double value)
{
   GlobalVariableSet(GVName(suffix), value);
}

bool GVRead(const string suffix, double &value)
{
   string name = GVName(suffix);
   if(!GlobalVariableCheck(name))
      return false;
   value = GlobalVariableGet(name);
   return true;
}

void GVDelete(const string suffix)
{
   string name = GVName(suffix);
   if(GlobalVariableCheck(name))
      GlobalVariableDel(name);
}

// Everything whose loss would let the EA resume trading against its own rules,
// plus the cycle geometry a restart needs to avoid rebuilding off-centre.
void SaveState()
{
   GVWrite("ANC", g_anchor_price);
   GVWrite("STP", g_cycle_step_points);
   GVWrite("BAS", g_cfg_base_lot);
   GVWrite("LVL", (double)g_cfg_levels);
   GVWrite("MUL", g_cfg_multiplier);
   GVWrite("PSD", g_paused ? 1.0 : 0.0);
   GVWrite("LCK", (double)g_daily_lock_until);
   GVWrite("CPL", g_commission_per_lot);
   GlobalVariablesFlush();   // an unclean terminal exit must not drop a guard
}

void ClearCycleState()
{
   GVDelete("ANC");
   GVDelete("STP");
   GVDelete("BAS");
   GVDelete("LVL");
   GVDelete("MUL");
   GlobalVariablesFlush();
}

//+------------------------------------------------------------------+
//| Symbol and market helpers                                        |
//+------------------------------------------------------------------+
bool GetCurrentTick(MqlTick &tick)
{
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   return (tick.ask > 0.0 && tick.bid > 0.0);
}

double CurrentReferencePrice()
{
   MqlTick tick;
   if(!GetCurrentTick(tick))
      return 0.0;

   return (tick.ask + tick.bid) * 0.5;
}

double CurrentSpreadPoints()
{
   MqlTick tick;
   if(!GetCurrentTick(tick))
      return 0.0;
   return (tick.ask - tick.bid) / _Point;
}

// Stops level governs setting a price; freeze level governs modifying or
// deleting one. Both matter, and both are commonly zero on forex and non-zero
// on indices and metals.
double MinimumOrderDistancePrice()
{
   int stops  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double distance = (double)MathMax(stops, freeze) * _Point;
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;
   return MathMax(distance, tick_size);
}

// Money moved per point, per one lot, in account currency.
double MoneyPerPointPerLot()
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_value <= 0.0 || tick_size <= 0.0)
      return 0.0;
   return tick_value * (_Point / tick_size);
}

int VolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   int digits = 0;
   double probe = step;
   while(digits < 8 && MathAbs(probe - MathRound(probe)) > 1e-10)
   {
      probe *= 10.0;
      digits++;
   }
   return digits;
}

// Round down to the symbol's volume step, without applying any user cap.
double RoundVolumeToStep(const double requested)
{
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = minimum;
   if(step <= 0.0)
      return 0.0;

   double bounded = MathMin(requested, maximum);
   double rounded = MathFloor((bounded + 1e-12) / step) * step;
   return NormalizeDouble(rounded, VolumeDigits());
}

// Applies the per-order cap as well. Returns 0.0 when the symbol's minimum lot
// is larger than the cap -- in that case the honest answer is to place nothing,
// not to round up and silently exceed the operator's limit.
double NormalizeVolume(const double requested_volume)
{
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double cap     = g_cfg_max_lot > 0.0 ? g_cfg_max_lot : requested_volume;

   if(minimum > cap + 1e-12)
      return 0.0;

   double rounded = RoundVolumeToStep(MathMin(requested_volume, cap));
   if(rounded < minimum - 1e-12)
      return 0.0;

   return rounded;
}

double LevelVolume(const int level)
{
   double requested = g_cfg_base_lot * MathPow(g_cfg_multiplier, level - 1);
   return NormalizeVolume(requested);
}

double NormalizeLimitPrice(const double raw_price, const bool is_buy)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;

   // Round away from the market so rounding can never push a limit through it.
   double price;
   if(is_buy)
      price = MathFloor((raw_price / tick_size) + 1e-9) * tick_size;
   else
      price = MathCeil((raw_price / tick_size) - 1e-9) * tick_size;

   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| Indicators                                                       |
//+------------------------------------------------------------------+
bool ReadIndicatorValue(const int handle, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[1];
   // Use the last completed candle so spacing and regime do not flicker intrabar.
   if(CopyBuffer(handle, 0, 1, 1, buffer) != 1 || buffer[0] == EMPTY_VALUE)
      return false;

   value = buffer[0];
   return true;
}

//+------------------------------------------------------------------+
//| Auto distance                                                    |
//+------------------------------------------------------------------+
// The floor is what the broker and the current spread will actually tolerate;
// the ceiling keeps the grid from becoming a pair of unreachable orders.
double AutoStepFloorPoints()
{
   if(!InpAutoStepBounds)
      return (double)InpMinimumGridStepPoints;

   double spread_floor = CurrentSpreadPoints() * InpStepSpreadFactor;
   double broker_floor = MinimumOrderDistancePrice() / _Point * 2.0;
   double absolute     = 10.0;

   return MathMax(MathMax(spread_floor, broker_floor), absolute);
}

double AutoStepCeilingPoints()
{
   if(!InpAutoStepBounds)
      return (double)InpMaximumGridStepPoints;

   return MathMax(AutoStepFloorPoints() * 20.0, 100.0);
}

bool CalculateSmartStepPoints(double &step_points)
{
   double floor_points   = AutoStepFloorPoints();
   double ceiling_points = AutoStepCeilingPoints();

   if(!InpUseATRGridSpacing)
   {
      step_points = MathMax((double)InpGridStepPoints, floor_points);
      return true;
   }

   double atr = 0.0;
   if(!ReadIndicatorValue(g_atr_handle, atr) || atr <= 0.0)
   {
      // ATR is not ready yet (fresh chart, few bars). Use a provisional step
      // and re-solve once real data arrives, while the grid is still flat.
      step_points = MathMax((double)InpGridStepPoints, floor_points);
      return false;
   }

   double points = (atr / _Point) * InpATRMultiplier;
   points = MathMax(points, floor_points);
   points = MathMin(points, ceiling_points);
   step_points = MathRound(points);
   return true;
}

double CycleStepPrice()
{
   double points = g_cycle_step_points > 0.0
                   ? g_cycle_step_points
                   : (double)InpGridStepPoints;
   return points * _Point;
}

//+------------------------------------------------------------------+
//| Auto ladder solver                                               |
//+------------------------------------------------------------------+
// Sum of m^(i-1) for i in 1..levels -- the total lots the ladder commits.
double LadderVolumeWeight(const int levels, const double multiplier)
{
   double sum = 0.0;
   for(int i = 1; i <= levels; i++)
      sum += MathPow(multiplier, i - 1);
   return sum;
}

// Sum of m^(i-1) * (levels + 1 - i) -- lots multiplied by the grid steps each
// level is under water once price has filled the ladder and run one step past
// it. This is the number the risk budget is measured against.
double LadderDrawdownWeight(const int levels, const double multiplier)
{
   double sum = 0.0;
   for(int i = 1; i <= levels; i++)
      sum += MathPow(multiplier, i - 1) * (double)(levels + 1 - i);
   return sum;
}

// Prefer the requested multiplier and as many levels as the budget allows;
// step the multiplier down only when nothing fits at the current one.
bool SolveLadder(const double risk_money, const double step_points,
                 double &out_base, int &out_levels, double &out_multiplier)
{
   double money_per_point = MoneyPerPointPerLot();
   if(money_per_point <= 0.0 || step_points <= 0.0 || risk_money <= 0.0)
      return false;

   double step_money = step_points * money_per_point;   // per lot, per grid step
   double v_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double v_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   int top_multiplier = (int)MathRound(MathMax(1.0, InpPreferredMultiplier) * 10.0);

   for(int mi = top_multiplier; mi >= 10; mi--)
   {
      double multiplier = mi / 10.0;

      for(int levels = InpMaxLevelsPerSide; levels >= 1; levels--)
      {
         double weight = LadderDrawdownWeight(levels, multiplier);
         if(weight <= 0.0)
            continue;

         double base = RoundVolumeToStep(risk_money / (step_money * weight));
         if(base < v_min - 1e-12)
            continue;   // budget cannot fund even one minimum lot at this shape

         double deepest = base * MathPow(multiplier, levels - 1);
         if(deepest > v_max)
            continue;

         out_base       = base;
         out_levels     = levels;
         out_multiplier = multiplier;
         return true;
      }
   }

   return false;
}

bool ResolveConfiguration()
{
   if(!InpAutoConfigure)
   {
      g_cfg_base_lot   = InpBaseLot;
      g_cfg_levels     = InpLevelsPerSide;
      g_cfg_multiplier = InpMartingaleMultiplier;
      g_cfg_max_lot    = InpMaximumLot;
      g_cfg_target_money = InpBasketProfitMoney;
      g_cfg_trail_start  = InpTrailStartMoney;
      g_cfg_trail_give   = InpTrailGivebackMoney;
      g_cfg_emergency    = InpEmergencyLossMoney;
      g_cfg_max_volume   = InpMaximumTotalVolume;
      g_cfg_daily_loss   = InpDailyLossLimitMoney;

      g_config_text = StringFormat("manual: %d lvl x%.1f from %.2f",
                                   g_cfg_levels, g_cfg_multiplier, g_cfg_base_lot);
      return (g_cfg_base_lot > 0.0 && g_cfg_levels >= 1);
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return false;

   double risk_money = equity * InpRiskPercentPerCycle / 100.0;

   double base = 0.0, multiplier = 1.0;
   int levels = 0;
   if(!SolveLadder(risk_money, g_cycle_step_points, base, levels, multiplier))
   {
      g_config_text = "no ladder fits the risk budget";
      return false;
   }

   g_cfg_base_lot   = base;
   g_cfg_levels     = levels;
   g_cfg_multiplier = multiplier;

   double ladder_lots = base * LadderVolumeWeight(levels, multiplier);
   g_cfg_max_lot    = base * MathPow(multiplier, levels - 1);
   g_cfg_max_volume = ladder_lots * (1.0 + InpExposureHeadroomPercent / 100.0);

   g_cfg_target_money = equity * InpTargetPercentPerCycle / 100.0;
   g_cfg_trail_start  = g_cfg_target_money * 0.6;
   g_cfg_trail_give   = g_cfg_target_money * 0.25;
   g_cfg_emergency    = risk_money;
   g_cfg_daily_loss   = InpDailyLossPercent > 0.0
                        ? equity * InpDailyLossPercent / 100.0
                        : 0.0;

   g_config_text = StringFormat("auto: %d lvl x%.1f from %.2f (%.2f lots, risk %.2f)",
                                levels, multiplier, base, ladder_lots, risk_money);
   return true;
}

void PrintLadder()
{
   string ladder = "";
   double total = 0.0;
   for(int level = 1; level <= g_cfg_levels; level++)
   {
      double volume = g_cfg_base_lot * MathPow(g_cfg_multiplier, level - 1);
      volume = RoundVolumeToStep(MathMin(volume, g_cfg_max_lot));
      total += volume;
      ladder += StringFormat("%s%.2f", level == 1 ? "" : " / ", volume);
   }

   PrintFormat("Ladder per side: %s  = %.2f lots | step %.0f points | target %.2f | emergency %.2f",
               ladder, total, g_cycle_step_points, g_cfg_target_money, g_cfg_emergency);
}

//+------------------------------------------------------------------+
//| Managed order and position scanning                              |
//+------------------------------------------------------------------+
bool IsManagedSelectedOrder()
{
   return (OrderGetString(ORDER_SYMBOL) == _Symbol &&
           IsManagedMagic(OrderGetInteger(ORDER_MAGIC)));
}

bool IsManagedSelectedPosition()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           IsManagedMagic(PositionGetInteger(POSITION_MAGIC)));
}

int ManagedOrderCount()
{
   int count = 0;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0 || !IsManagedSelectedOrder())
         continue;
      count++;
   }
   return count;
}

int ManagedPositionCount()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;
      count++;
   }
   return count;
}

bool HasManagedExposure()
{
   return (ManagedOrderCount() > 0 || ManagedPositionCount() > 0);
}

double ManagedPositionVolume()
{
   double volume = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;
      volume += PositionGetDouble(POSITION_VOLUME);
   }
   return volume;
}

double ManagedTotalVolume()
{
   double volume = ManagedPositionVolume();

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0 || !IsManagedSelectedOrder())
         continue;
      volume += OrderGetDouble(ORDER_VOLUME_CURRENT);
   }

   return volume;
}

// MQL5 has no POSITION_COMMISSION -- commission is a deal property -- so a raw
// sum of POSITION_PROFIT is gross. The exit commission has not been charged
// yet, so subtract the estimate here; otherwise every basket closes for less
// than the target says.
double EstimatedExitCommission()
{
   double per_lot = InpCommissionPerLotPerSide > 0.0
                    ? InpCommissionPerLotPerSide
                    : g_commission_per_lot;
   if(per_lot <= 0.0)
      return 0.0;

   return ManagedPositionVolume() * per_lot;
}

double ManagedFloatingProfit()
{
   double profit = 0.0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;

      profit += PositionGetDouble(POSITION_PROFIT);
      profit += PositionGetDouble(POSITION_SWAP);
   }
   return profit - EstimatedExitCommission();
}

// A slot is occupied when an order or position carries its magic number.
bool SlotExists(const bool is_buy, const int level)
{
   long magic = SlotMagic(is_buy, level);

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == magic)
         return true;
   }

   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Trade result handling                                            |
//+------------------------------------------------------------------+
bool TradeResultSucceeded()
{
   uint code = trade.ResultRetcode();
   return (code == TRADE_RETCODE_DONE ||
           code == TRADE_RETCODE_PLACED ||
           code == TRADE_RETCODE_DONE_PARTIAL);
}

// Throttle per retcode rather than globally: when a whole ladder is rejected
// at once, a single global throttle reports one failure and hides the rest.
void LogTradeFailure(const string action)
{
   uint code = trade.ResultRetcode();
   datetime now = TimeCurrent();

   int total = ArraySize(g_logged_codes);
   for(int i = 0; i < total; i++)
   {
      if(g_logged_codes[i] != code)
         continue;
      if(now - g_logged_times[i] < 10)
         return;
      g_logged_times[i] = now;
      PrintFormat("%s failed. Retcode=%u (%s), broker comment=%s",
                  action, code, trade.ResultRetcodeDescription(), trade.ResultComment());
      return;
   }

   ArrayResize(g_logged_codes, total + 1);
   ArrayResize(g_logged_times, total + 1);
   g_logged_codes[total] = code;
   g_logged_times[total] = now;

   PrintFormat("%s failed. Retcode=%u (%s), broker comment=%s",
               action, code, trade.ResultRetcodeDescription(), trade.ResultComment());
}

bool TradingIsAvailable()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;

   ENUM_SYMBOL_TRADE_MODE mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   return (mode != SYMBOL_TRADE_MODE_DISABLED && mode != SYMBOL_TRADE_MODE_CLOSEONLY);
}

bool SpreadIsAllowed(const MqlTick &tick)
{
   if(InpMaximumSpreadPoints <= 0)
      return true;

   double spread_points = (tick.ask - tick.bid) / _Point;
   return (spread_points <= InpMaximumSpreadPoints);
}

//+------------------------------------------------------------------+
//| History cache                                                    |
//+------------------------------------------------------------------+
datetime ServerDayStart(const datetime moment)
{
   MqlDateTime parts;
   if(!TimeToStruct(moment, parts))
      return 0;
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
}

// HistorySelect costs roughly 5-30 ms per call, so it must never sit on the
// tick path. Recompute only when a deal actually closed, or when the broker
// day rolls over.
void RefreshHistoryCache(const bool force)
{
   datetime now = TimeCurrent();
   datetime start = ServerDayStart(now);

   if(!force && !g_history_dirty && start == g_day_start_cached)
      return;

   g_history_dirty = false;
   g_day_start_cached = start;
   g_day_realized = 0.0;

   if(start <= 0 || !HistorySelect(start, now))
      return;

   double commission_sum = 0.0;
   double volume_sum = 0.0;

   for(int index = 0; index < HistoryDealsTotal(); index++)
   {
      ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         !IsManagedMagic(HistoryDealGetInteger(ticket, DEAL_MAGIC)))
         continue;

      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);

      g_day_realized += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      g_day_realized += HistoryDealGetDouble(ticket, DEAL_SWAP);
      g_day_realized += commission;
      g_day_realized += HistoryDealGetDouble(ticket, DEAL_FEE);

      if(volume > 0.0)
      {
         commission_sum += MathAbs(commission);
         volume_sum += volume;
      }
   }

   // Learn the per-lot, per-side commission from what this account is actually
   // charged, so the profit target means net money without being told.
   if(volume_sum > 0.0 && commission_sum > 0.0)
      g_commission_per_lot = commission_sum / volume_sum;
}

double ManagedProfitToday()
{
   RefreshHistoryCache(false);
   return g_day_realized;
}

bool SessionIsOpen()
{
   if(!InpUseTradingSession || InpSessionStartHour == InpSessionEndHour)
      return true;

   MqlDateTime parts;
   if(!TimeToStruct(TimeCurrent(), parts))
      return false;

   if(InpSessionStartHour < InpSessionEndHour)
      return (parts.hour >= InpSessionStartHour && parts.hour < InpSessionEndHour);

   return (parts.hour >= InpSessionStartHour || parts.hour < InpSessionEndHour);
}

//+------------------------------------------------------------------+
//| Direction filter                                                 |
//+------------------------------------------------------------------+
bool GetDirectionPermissions(bool &allow_buy, bool &allow_sell)
{
   allow_buy = false;
   allow_sell = false;

   if(InpDirectionMode == GRID_DIRECTION_BOTH)
   {
      allow_buy = true;
      allow_sell = true;
      g_regime_text = "Both sides";
      return true;
   }
   if(InpDirectionMode == GRID_DIRECTION_BUY_ONLY)
   {
      allow_buy = true;
      g_regime_text = "Buy only";
      return true;
   }
   if(InpDirectionMode == GRID_DIRECTION_SELL_ONLY)
   {
      allow_sell = true;
      g_regime_text = "Sell only";
      return true;
   }

   double fast_ema = 0.0;
   double slow_ema = 0.0;
   if(!ReadIndicatorValue(g_fast_ema_handle, fast_ema) ||
      !ReadIndicatorValue(g_slow_ema_handle, slow_ema))
   {
      g_regime_text = "Waiting for EMA data";
      return false;
   }

   double gap = InpTrendGapPoints * _Point;
   if(fast_ema > slow_ema + gap)
   {
      allow_buy = true;
      g_regime_text = "Uptrend: buy dips";
   }
   else if(fast_ema < slow_ema - gap)
   {
      allow_sell = true;
      g_regime_text = "Downtrend: sell rallies";
   }
   else
   {
      allow_buy = true;
      allow_sell = true;
      g_regime_text = "Range: both sides";
   }

   return true;
}

//+------------------------------------------------------------------+
//| Risk gates                                                       |
//+------------------------------------------------------------------+
bool MarginAllowsOrder(const bool is_buy, const double volume, const double price)
{
   if(g_cfg_max_volume > 0.0 &&
      ManagedTotalVolume() + volume > g_cfg_max_volume + 1e-10)
   {
      g_status_text = "Exposure cap blocks new limits";
      return false;
   }

   double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(InpMinimumMarginLevelPercent > 0.0 && margin_level > 0.0 &&
      margin_level < InpMinimumMarginLevelPercent)
   {
      g_status_text = "Margin-level guard active";
      return false;
   }

   // OrderCalcMargin ignores existing exposure, and forex pendings usually
   // reserve nothing, so budget for the whole ladder rather than this order:
   // in a fast move every level can trigger together.
   double per_lot_margin = 0.0;
   ENUM_ORDER_TYPE market_type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcMargin(market_type, _Symbol, 1.0, price, per_lot_margin) &&
      per_lot_margin > 0.0 && InpMarginReservePercent > 0.0)
   {
      double ladder_lots = g_cfg_base_lot * LadderVolumeWeight(g_cfg_levels, g_cfg_multiplier);
      double required_free = per_lot_margin * ladder_lots * InpMarginReservePercent / 100.0;
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < required_free)
      {
         g_status_text = "Free-margin reserve blocks new limits";
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Cycle state                                                      |
//+------------------------------------------------------------------+
void StartNewCycleState()
{
   g_anchor_price = CurrentReferencePrice();
   g_config_provisional = !CalculateSmartStepPoints(g_cycle_step_points);
   g_peak_profit = 0.0;

   if(!ResolveConfiguration())
   {
      g_status_text = "Cannot size a ladder: " + g_config_text;
      g_cfg_levels = 0;
      return;
   }

   SaveState();
   PrintLadder();
}

//+------------------------------------------------------------------+
//| Anchor restoration                                               |
//+------------------------------------------------------------------+
// Recover the anchor from every managed order, not the first one found, and
// take the median so a single stale order cannot define the whole cycle.
bool InferAnchorFromMarket(double &anchor)
{
   double distance = CycleStepPrice();
   if(distance <= 0.0)
      return false;

   double candidates[];
   int count = 0;

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0 || !IsManagedSelectedOrder())
         continue;

      bool is_buy = false;
      int level = 0;
      if(!DecodeSlotMagic(OrderGetInteger(ORDER_MAGIC), is_buy, level))
         continue;

      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      ArrayResize(candidates, count + 1);
      candidates[count++] = is_buy ? price + level * distance
                                   : price - level * distance;
   }

   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;

      bool is_buy = false;
      int level = 0;
      if(!DecodeSlotMagic(PositionGetInteger(POSITION_MAGIC), is_buy, level))
         continue;

      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      ArrayResize(candidates, count + 1);
      candidates[count++] = is_buy ? price + level * distance
                                   : price - level * distance;
   }

   if(count == 0)
      return false;

   ArraySort(candidates);
   anchor = candidates[count / 2];
   return (anchor > 0.0);
}

void RestoreOrCreateAnchor()
{
   double value = 0.0;

   // Risk guards first: losing these is what lets a stopped EA restart itself.
   if(GVRead("PSD", value))
      g_paused = (value > 0.5);
   if(GVRead("LCK", value))
      g_daily_lock_until = (datetime)value;
   if(GVRead("CPL", value) && value > 0.0)
      g_commission_per_lot = value;

   if(GVRead("STP", value) && value > 0.0)
      g_cycle_step_points = value;
   if(g_cycle_step_points <= 0.0)
      g_config_provisional = !CalculateSmartStepPoints(g_cycle_step_points);

   bool have_shape = false;
   double saved_base = 0.0, saved_mult = 0.0, saved_levels = 0.0;
   if(GVRead("BAS", saved_base) && GVRead("MUL", saved_mult) && GVRead("LVL", saved_levels) &&
      saved_base > 0.0 && saved_mult >= 1.0 && saved_levels >= 1.0)
   {
      // Keep the shape the live orders were built with, so a restart does not
      // re-solve into a different ladder around existing positions.
      g_cfg_base_lot   = saved_base;
      g_cfg_multiplier = saved_mult;
      g_cfg_levels     = (int)saved_levels;
      g_cfg_max_lot    = saved_base * MathPow(saved_mult, g_cfg_levels - 1);
      have_shape = true;
   }

   if(GVRead("ANC", value) && value > 0.0)
   {
      g_anchor_price = value;
      if(have_shape)
      {
         ResolveMoneyLimitsOnly();
         return;
      }
   }

   double inferred = 0.0;
   if(g_anchor_price <= 0.0 && InferAnchorFromMarket(inferred))
   {
      g_anchor_price = inferred;
      if(have_shape)
      {
         ResolveMoneyLimitsOnly();
         SaveState();
         return;
      }
   }

   if(g_anchor_price > 0.0 && have_shape)
   {
      ResolveMoneyLimitsOnly();
      SaveState();
      return;
   }

   StartNewCycleState();
}

// Money limits track equity even on a restored cycle; the lot ladder does not,
// because live orders were placed against the old one.
void ResolveMoneyLimitsOnly()
{
   if(!InpAutoConfigure)
   {
      ResolveConfiguration();
      return;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return;

   double ladder_lots = g_cfg_base_lot * LadderVolumeWeight(g_cfg_levels, g_cfg_multiplier);
   g_cfg_max_volume   = ladder_lots * (1.0 + InpExposureHeadroomPercent / 100.0);
   g_cfg_target_money = equity * InpTargetPercentPerCycle / 100.0;
   g_cfg_trail_start  = g_cfg_target_money * 0.6;
   g_cfg_trail_give   = g_cfg_target_money * 0.25;
   g_cfg_emergency    = equity * InpRiskPercentPerCycle / 100.0;
   g_cfg_daily_loss   = InpDailyLossPercent > 0.0
                        ? equity * InpDailyLossPercent / 100.0
                        : 0.0;

   g_config_text = StringFormat("restored: %d lvl x%.1f from %.2f",
                                g_cfg_levels, g_cfg_multiplier, g_cfg_base_lot);
}

//+------------------------------------------------------------------+
//| Order operations                                                 |
//+------------------------------------------------------------------+
bool PlaceGridOrder(const bool is_buy, const int level, const MqlTick &tick)
{
   double distance = CycleStepPrice();
   double raw_price = is_buy
                      ? g_anchor_price - level * distance
                      : g_anchor_price + level * distance;
   double price = NormalizeLimitPrice(raw_price, is_buy);

   double minimum_distance = MinimumOrderDistancePrice();
   if(is_buy && price >= tick.ask - minimum_distance)
      return false;
   if(!is_buy && price <= tick.bid + minimum_distance)
      return false;

   double volume = LevelVolume(level);
   if(volume <= 0.0)
   {
      g_status_text = "Symbol minimum lot exceeds the level cap";
      return false;
   }

   if(!MarginAllowsOrder(is_buy, volume, price))
      return false;

   ResetLastError();
   trade.SetExpertMagicNumber((ulong)SlotMagic(is_buy, level));

   // Pending orders fill later under rules the broker sets then, so they take
   // ORDER_FILLING_RETURN whatever the symbol's market execution mode says.
   trade.SetTypeFilling(ORDER_FILLING_RETURN);

   string tag = SlotTag(is_buy, level);
   bool sent;
   if(is_buy)
      sent = trade.BuyLimit(volume, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, tag);
   else
      sent = trade.SellLimit(volume, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, tag);

   trade.SetTypeFillingBySymbol(_Symbol);

   if(!sent || !TradeResultSucceeded())
   {
      LogTradeFailure(StringFormat("Place %s level %d", is_buy ? "buy limit" : "sell limit", level));
      return false;
   }

   PrintFormat("Placed %s level %d: %.2f lots at %.*f",
               is_buy ? "buy limit" : "sell limit",
               level, volume,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS), price);
   return true;
}

void DeleteManagedOrders(const int side_filter)
{
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      ulong ticket = OrderGetTicket(index);
      if(ticket == 0 || !IsManagedSelectedOrder())
         continue;

      if(side_filter != 0)
      {
         bool is_buy = false;
         int level = 0;
         if(!DecodeSlotMagic(OrderGetInteger(ORDER_MAGIC), is_buy, level))
            continue;
         if((side_filter > 0) != is_buy)
            continue;
      }

      ResetLastError();
      bool sent = trade.OrderDelete(ticket);
      if(sent && TradeResultSucceeded())
         continue;

      // A pending order inside the freeze band cannot be deleted until price
      // moves away. That is broker policy, not a bug to hammer at silently.
      if(trade.ResultRetcode() == TRADE_RETCODE_INVALID_STOPS)
         g_status_text = "Order frozen near market; waiting for price to move";

      LogTradeFailure(StringFormat("Delete pending order #%I64u", ticket));
   }
}

void CloseManagedPositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !IsManagedSelectedPosition())
         continue;

      ResetLastError();
      bool sent = trade.PositionClose(ticket, InpDeviationPoints);
      if(!sent || !TradeResultSucceeded())
         LogTradeFailure(StringFormat("Close position #%I64u", ticket));
   }
}

void MaintainGrid()
{
   if(g_anchor_price <= 0.0 || g_cfg_levels < 1 || !TradingIsAvailable())
      return;

   MqlTick tick;
   if(!GetCurrentTick(tick) || !SpreadIsAllowed(tick))
      return;

   bool allow_buy = false;
   bool allow_sell = false;
   if(!GetDirectionPermissions(allow_buy, allow_sell))
   {
      g_status_text = "Waiting for indicator data";
      return;
   }

   if(!allow_buy)
      DeleteManagedOrders(1);
   if(!allow_sell)
      DeleteManagedOrders(-1);

   g_status_text = "Grid active";

   for(int level = 1; level <= g_cfg_levels; level++)
   {
      if(allow_buy && !SlotExists(true, level))
         PlaceGridOrder(true, level, tick);

      if(allow_sell && !SlotExists(false, level))
         PlaceGridOrder(false, level, tick);
   }
}

//+------------------------------------------------------------------+
//| Basket close                                                     |
//+------------------------------------------------------------------+
void StartBasketClose(const bool pause_after_close, const string reason)
{
   if(g_cycle_closing)
      return;

   g_cycle_closing = true;
   g_pause_after_close = pause_after_close;
   PrintFormat("Closing the managed basket: %s", reason);
}

void ContinueBasketClose()
{
   // Delete pending orders first so no new grid position can open while exits run.
   DeleteManagedOrders(0);
   CloseManagedPositions();

   if(HasManagedExposure())
      return;

   ClearCycleState();
   g_cycle_closing = false;

   if(g_daily_lock_until > TimeCurrent())
   {
      g_anchor_price = 0.0;
      g_cycle_step_points = 0.0;
      g_status_text = "Daily loss lock";
      SaveState();
      PrintFormat("Basket is flat. Daily loss lock remains until %s.",
                  TimeToString(g_daily_lock_until, TIME_DATE | TIME_MINUTES));
      return;
   }

   if(g_pause_after_close || !InpAutoRestartAfterProfit)
   {
      g_paused = true;
      SaveState();   // survives a recompile: a stopped EA must stay stopped
      Print("Basket is flat. The EA is paused; clear the pause to start another cycle.");
      return;
   }

   StartNewCycleState();
   g_next_build_time = TimeCurrent() + InpRestartDelaySeconds;
   PrintFormat("Basket is flat. A fresh grid will start after %d second(s).",
               InpRestartDelaySeconds);
}

void RecenterFlatGridIfNeeded()
{
   if(!InpAutoRecenterWhenFlat || ManagedPositionCount() > 0)
      return;

   datetime now = TimeCurrent();
   if(now < g_next_recenter_time)
      return;

   double current = CurrentReferencePrice();
   if(current <= 0.0 || g_anchor_price <= 0.0)
      return;

   double threshold = InpRecenterAfterSteps * CycleStepPrice();
   if(MathAbs(current - g_anchor_price) < threshold)
      return;

   DeleteManagedOrders(0);
   if(ManagedOrderCount() > 0)
      return;

   StartNewCycleState();
   g_next_recenter_time = now + InpRecenterCooldownSeconds;
   PrintFormat("Flat grid recentered at %.*f",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS), g_anchor_price);
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   datetime now = TimeCurrent();
   if(now == g_last_dashboard)
      return;
   g_last_dashboard = now;

   string state = g_paused ? "PAUSED" : (g_cycle_closing ? "CLOSING" : g_status_text);
   string lock_text = g_daily_lock_until > now
                      ? TimeToString(g_daily_lock_until, TIME_DATE | TIME_MINUTES)
                      : "No";

   Comment("GridBot Auto-Adaptive v3.00\n",
           "State: ", state, "\n",
           "Config: ", g_config_text, "\n",
           "Regime: ", g_regime_text, "\n",
           "Floating (net): ", DoubleToString(ManagedFloatingProfit(), 2),
           " / Target: ", DoubleToString(g_cfg_target_money, 2), "\n",
           "Peak profit: ", DoubleToString(g_peak_profit, 2),
           " | Emergency: ", DoubleToString(g_cfg_emergency, 2), "\n",
           "Positions / Orders: ", IntegerToString(ManagedPositionCount()),
           " / ", IntegerToString(ManagedOrderCount()), "\n",
           "Lots: ", DoubleToString(ManagedTotalVolume(), 2),
           " / cap ", DoubleToString(g_cfg_max_volume, 2), "\n",
           "Anchor: ", DoubleToString(g_anchor_price, _Digits),
           " | Step: ", DoubleToString(g_cycle_step_points, 0), " points\n",
           "Commission/lot: ", DoubleToString(g_commission_per_lot, 2),
           " | Today: ", DoubleToString(ManagedProfitToday(), 2), "\n",
           "Daily lock until: ", lock_text);
}

//+------------------------------------------------------------------+
//| Main manager                                                     |
//+------------------------------------------------------------------+
void FinishManagePass()
{
   UpdateDashboard();
   g_manage_busy = false;
}

void ManageEA()
{
   if(g_manage_busy)
      return;

   if(g_paused)
   {
      UpdateDashboard();
      return;
   }

   g_manage_busy = true;
   datetime now = TimeCurrent();

   if(g_cycle_closing)
   {
      ContinueBasketClose();
      FinishManagePass();
      return;
   }

   if(g_daily_lock_until > 0 && now >= g_daily_lock_until)
   {
      g_daily_lock_until = 0;
      RefreshHistoryCache(true);
      StartNewCycleState();
      g_next_build_time = now;
      g_status_text = "Daily lock released";
      Print("New broker day: daily loss lock released.");
   }

   if(g_cfg_daily_loss > 0.0 && g_daily_lock_until == 0)
   {
      double today_result = ManagedProfitToday() + ManagedFloatingProfit();
      if(today_result <= -g_cfg_daily_loss)
      {
         g_daily_lock_until = ServerDayStart(now) + 86400;
         SaveState();   // the lock must outlive a restart
         StartBasketClose(false,
                          StringFormat("daily loss limit reached (%.2f)", today_result));
         ContinueBasketClose();
         FinishManagePass();
         return;
      }
   }

   if(g_daily_lock_until > now)
   {
      g_status_text = "Daily loss lock";
      FinishManagePass();
      return;
   }

   int position_count = ManagedPositionCount();
   if(position_count > 0)
   {
      double floating_profit = ManagedFloatingProfit();
      g_peak_profit = MathMax(g_peak_profit, floating_profit);

      if(g_cfg_target_money > 0.0 && floating_profit >= g_cfg_target_money)
      {
         StartBasketClose(false,
                          StringFormat("profit target reached (%.2f)", floating_profit));
         ContinueBasketClose();
         FinishManagePass();
         return;
      }

      if(InpUseBasketProfitTrail && g_cfg_trail_give > 0.0 &&
         g_peak_profit >= g_cfg_trail_start &&
         g_peak_profit - floating_profit >= g_cfg_trail_give)
      {
         StartBasketClose(false,
                          StringFormat("profit trail triggered: peak %.2f, current %.2f",
                                       g_peak_profit, floating_profit));
         ContinueBasketClose();
         FinishManagePass();
         return;
      }

      if(g_cfg_emergency > 0.0 && floating_profit <= -g_cfg_emergency)
      {
         StartBasketClose(true,
                          StringFormat("emergency loss reached (%.2f)", floating_profit));
         ContinueBasketClose();
         FinishManagePass();
         return;
      }

      if(InpMaxBasketDrawdownPercent > 0.0)
      {
         double drawdown_limit = AccountInfoDouble(ACCOUNT_BALANCE) *
                                 InpMaxBasketDrawdownPercent / 100.0;
         if(floating_profit <= -drawdown_limit)
         {
            StartBasketClose(true,
                             StringFormat("basket drawdown guard reached (%.2f%%)",
                                          InpMaxBasketDrawdownPercent));
            ContinueBasketClose();
            FinishManagePass();
            return;
         }
      }
   }

   if(!SessionIsOpen())
   {
      g_status_text = "Outside trading session";
      if(InpDeletePendingOutsideSession)
         DeleteManagedOrders(0);
      FinishManagePass();
      return;
   }

   if(now < g_next_build_time)
   {
      g_status_text = "Restart cooldown";
      FinishManagePass();
      return;
   }

   if(g_anchor_price <= 0.0 || g_cycle_step_points <= 0.0 || g_cfg_levels < 1)
      StartNewCycleState();

   // The first cycle can be sized before ATR has enough bars. Re-solve once,
   // while the grid is still flat and nothing depends on the old numbers.
   if(g_config_provisional && position_count == 0)
   {
      double probe = 0.0;
      if(CalculateSmartStepPoints(probe))
      {
         DeleteManagedOrders(0);
         if(ManagedOrderCount() == 0)
         {
            StartNewCycleState();
            Print("ATR data available: grid re-sized from provisional settings.");
         }
      }
   }

   RecenterFlatGridIfNeeded();
   MaintainGrid();
   FinishManagePass();
}

//+------------------------------------------------------------------+
//| MT5 event handlers                                               |
//+------------------------------------------------------------------+
int OnInit()
{
   bool auto_inputs_ok = !InpAutoConfigure ||
      (InpRiskPercentPerCycle > 0.0 && InpRiskPercentPerCycle <= 100.0 &&
       InpTargetPercentPerCycle > 0.0 &&
       InpDailyLossPercent >= 0.0 &&
       InpMaxLevelsPerSide >= 1 && InpMaxLevelsPerSide <= GB_LEVEL_SPAN &&
       InpPreferredMultiplier >= 1.0 &&
       InpExposureHeadroomPercent >= 0.0);

   bool manual_inputs_ok = InpAutoConfigure ||
      (InpBaseLot > 0.0 &&
       InpLevelsPerSide >= 1 && InpLevelsPerSide <= GB_LEVEL_SPAN &&
       InpGridStepPoints >= 1 &&
       InpMartingaleMultiplier >= 1.0 &&
       InpMaximumLot > 0.0 &&
       InpBasketProfitMoney > 0.0 &&
       InpMaximumTotalVolume >= 0.0 &&
       InpDailyLossLimitMoney >= 0.0 &&
       InpEmergencyLossMoney >= 0.0 &&
       (!InpUseBasketProfitTrail ||
        (InpTrailStartMoney >= 0.0 && InpTrailGivebackMoney > 0.0)));

   if(!auto_inputs_ok || !manual_inputs_ok ||
      InpATRPeriod < 1 ||
      InpATRMultiplier <= 0.0 ||
      InpStepSpreadFactor <= 0.0 ||
      InpMinimumGridStepPoints < 1 ||
      InpMaximumGridStepPoints < InpMinimumGridStepPoints ||
      InpFastEMAPeriod < 1 ||
      InpSlowEMAPeriod <= InpFastEMAPeriod ||
      InpTrendGapPoints < 0 ||
      InpMaxBasketDrawdownPercent < 0.0 ||
      InpMinimumMarginLevelPercent < 0.0 ||
      InpMarginReservePercent < 0.0 ||
      InpCommissionPerLotPerSide < 0.0 ||
      InpRestartDelaySeconds < 0 ||
      InpRecenterAfterSteps < 1 ||
      InpRecenterCooldownSeconds < 0 ||
      InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 23 ||
      InpMagicNumber <= 0 || InpMagicNumber > LONG_MAX - 2 * GB_LEVEL_SPAN)
   {
      Print("Invalid input parameter(s). Check the risk, level, step, target and magic values.");
      return INIT_PARAMETERS_INCORRECT;
   }

   ENUM_ACCOUNT_MARGIN_MODE margin_mode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("GridBot requires an MT5 hedging account. Netting mode is not supported.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpUseATRGridSpacing)
   {
      g_atr_handle = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(g_atr_handle == INVALID_HANDLE)
      {
         Print("Could not create the ATR indicator handle.");
         return INIT_FAILED;
      }
   }

   if(InpDirectionMode == GRID_DIRECTION_SMART_TREND)
   {
      g_fast_ema_handle = iMA(_Symbol, InpTrendTimeframe, InpFastEMAPeriod,
                              0, MODE_EMA, PRICE_CLOSE);
      g_slow_ema_handle = iMA(_Symbol, InpTrendTimeframe, InpSlowEMAPeriod,
                              0, MODE_EMA, PRICE_CLOSE);
      if(g_fast_ema_handle == INVALID_HANDLE || g_slow_ema_handle == INVALID_HANDLE)
      {
         Print("Could not create the EMA trend-filter handles.");
         return INIT_FAILED;
      }
   }

   // Log what this symbol actually allows. It turns a class of mystery
   // rejections into a one-line diagnosis.
   PrintFormat("%s: digits=%d point=%.*f tick=%.*f vol min/step/max=%.2f/%.2f/%.2f stops=%d freeze=%d tickvalue=%.5f",
               _Symbol,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               _Digits, _Point,
               _Digits, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));

   RefreshHistoryCache(true);
   RestoreOrCreateAnchor();

   if(g_anchor_price <= 0.0)
   {
      Print("Could not obtain a valid market price for the initial grid anchor.");
      return INIT_FAILED;
   }

   if(g_cfg_levels < 1)
   {
      PrintFormat("Refusing to start: %s. Raise InpRiskPercentPerCycle, fund the "
                  "account further, or choose a symbol with a smaller minimum lot.",
                  g_config_text);
      return INIT_FAILED;
   }

   if(g_paused)
      Print("Restored a paused state from a previous session. Delete the EA's "
            "global variables to clear it.");
   if(g_daily_lock_until > TimeCurrent())
      PrintFormat("Restored a daily loss lock until %s.",
                  TimeToString(g_daily_lock_until, TIME_DATE | TIME_MINUTES));

   EventSetTimer(1);
   PrintFormat("GridBot Auto-Adaptive v3 on %s | anchor %.*f | %s | magic %I64d..%I64d",
               _Symbol,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               g_anchor_price, g_config_text,
               InpMagicNumber + 1, InpMagicNumber + 2 * GB_LEVEL_SPAN);
   ManageEA();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
   if(g_fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_fast_ema_handle);
   if(g_slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_slow_ema_handle);

   SaveState();   // flush the guards before the terminal can drop them
   Comment("");
   // Managed trades are deliberately left intact when the EA is removed.
}

void OnTick()
{
   ManageEA();
}

void OnTimer()
{
   ManageEA();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Fires several times per fill, and for every symbol in the terminal.
   // Without this filter another EA's activity drags this one through full
   // order and position scans.
   if(trans.symbol != _Symbol)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      g_history_dirty = true;   // recompute realised P&L, but only now
      RefreshHistoryCache(false);
   }
   else if(trans.type != TRADE_TRANSACTION_ORDER_DELETE)
      return;

   ManageEA();
}
