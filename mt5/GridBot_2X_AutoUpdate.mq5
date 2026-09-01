//+------------------------------------------------------------------+
//|                                      GridBot_2X_AutoUpdate.mq5  |
//| Two-sided limit grid with martingale sizing and basket restart. |
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_GRID_DIRECTION_MODE
{
   GRID_DIRECTION_BOTH = 0,       // Always maintain both sides
   GRID_DIRECTION_SMART_TREND,    // Buy dips in uptrends, sell rallies in downtrends
   GRID_DIRECTION_BUY_ONLY,
   GRID_DIRECTION_SELL_ONLY
};

input group "Grid settings"
input double InpBaseLot                   = 0.01;   // Lot size at level 1
input int    InpLevelsPerSide             = 5;      // Buy-limit and sell-limit levels
input int    InpGridStepPoints            = 300;    // Distance between levels, in points
input double InpMartingaleMultiplier      = 2.0;    // Lot multiplier (2.0 = 2X)
input double InpMaximumLot                = 5.0;    // Hard lot cap for one order
input bool   InpAutoRecenterWhenFlat      = true;   // Move an untouched grid with price
input int    InpRecenterAfterSteps        = 1;      // Recenter after this many grid steps

input group "Smart market logic"
input bool   InpUseATRGridSpacing         = true;       // Adapt grid distance to volatility
input ENUM_TIMEFRAMES InpATRTimeframe     = PERIOD_M15;
input int    InpATRPeriod                 = 14;
input double InpATRMultiplier             = 1.0;
input int    InpMinimumGridStepPoints     = 150;
input int    InpMaximumGridStepPoints     = 1500;
input ENUM_GRID_DIRECTION_MODE InpDirectionMode = GRID_DIRECTION_SMART_TREND;
input ENUM_TIMEFRAMES InpTrendTimeframe   = PERIOD_M15;
input int    InpFastEMAPeriod             = 50;
input int    InpSlowEMAPeriod             = 200;
input int    InpTrendGapPoints            = 20;     // Smaller EMA gaps are treated as ranging

input group "Basket exit settings"
input double InpBasketProfitMoney         = 10.0;   // Close basket at this floating profit
input bool   InpUseBasketProfitTrail      = true;   // Protect profit before fixed target
input double InpTrailStartMoney           = 5.0;    // Start tracking peak basket profit
input double InpTrailGivebackMoney        = 2.0;    // Close after this drop from the peak
input double InpEmergencyLossMoney        = 0.0;    // 0=off; close and pause at this loss
input double InpMaxBasketDrawdownPercent  = 10.0;   // 0=off; percent of account balance
input bool   InpAutoRestartAfterProfit    = true;   // Build a new grid after profit close
input int    InpRestartDelaySeconds       = 3;      // Delay before the next grid

input group "Risk and session controls"
input double InpMaximumTotalVolume        = 1.0;    // Positions + pending lots; 0=unlimited
input double InpMinimumMarginLevelPercent = 300.0;  // Block new limits below this; 0=off
input double InpMarginReservePercent      = 200.0;  // Free margin / estimated order margin
input double InpDailyLossLimitMoney       = 0.0;    // 0=off; close and lock until next day
input bool   InpUseTradingSession         = false;
input int    InpSessionStartHour          = 0;      // Broker server hour, inclusive
input int    InpSessionEndHour            = 0;      // Same as start means 24 hours
input bool   InpDeletePendingOutsideSession = true;

input group "Execution settings"
input long   InpMagicNumber               = 26082801;
input int    InpMaximumSpreadPoints       = 50;     // 0=do not filter new orders
input ulong  InpDeviationPoints           = 20;

const string SLOT_PREFIX = "GB2X";

double   g_anchor_price       = 0.0;
double   g_cycle_step_points  = 0.0;
double   g_peak_profit        = 0.0;
bool     g_cycle_closing      = false;
bool     g_pause_after_close  = false;
bool     g_paused             = false;
bool     g_manage_busy        = false;
datetime g_next_build_time    = 0;
datetime g_last_error_log     = 0;
datetime g_daily_lock_until   = 0;
int      g_atr_handle         = INVALID_HANDLE;
int      g_fast_ema_handle    = INVALID_HANDLE;
int      g_slow_ema_handle    = INVALID_HANDLE;
string   g_regime_text        = "Initializing";
string   g_status_text        = "Initializing";

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string SlotTag(const bool is_buy, const int level)
{
   return StringFormat("%s:%s:%d", SLOT_PREFIX, is_buy ? "B" : "S", level);
}

string AnchorVariableName()
{
   string name = StringFormat("GB2X_%I64d_%I64d_%s",
                              AccountInfoInteger(ACCOUNT_LOGIN),
                              InpMagicNumber,
                              _Symbol);
   return StringSubstr(name, 0, 63);
}

string StepVariableName()
{
   string base = AnchorVariableName();
   return StringSubstr(base, 0, 61) + "_S";
}

void SaveAnchor()
{
   if(g_anchor_price > 0.0)
      GlobalVariableSet(AnchorVariableName(), g_anchor_price);
   if(g_cycle_step_points > 0.0)
      GlobalVariableSet(StepVariableName(), g_cycle_step_points);
}

void RemoveSavedAnchor()
{
   string name = AnchorVariableName();
   if(GlobalVariableCheck(name))
      GlobalVariableDel(name);
   name = StepVariableName();
   if(GlobalVariableCheck(name))
      GlobalVariableDel(name);
}

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

double CalculateSmartStepPoints()
{
   if(!InpUseATRGridSpacing)
      return (double)InpGridStepPoints;

   double atr = 0.0;
   if(!ReadIndicatorValue(g_atr_handle, atr) || atr <= 0.0)
      return (double)InpGridStepPoints;

   double points = (atr / _Point) * InpATRMultiplier;
   points = MathMax(points, (double)InpMinimumGridStepPoints);
   points = MathMin(points, (double)InpMaximumGridStepPoints);
   return MathRound(points);
}

double CycleStepPrice()
{
   double points = g_cycle_step_points > 0.0
                   ? g_cycle_step_points
                   : (double)InpGridStepPoints;
   return points * _Point;
}

void StartNewCycleState()
{
   g_anchor_price = CurrentReferencePrice();
   g_cycle_step_points = CalculateSmartStepPoints();
   g_peak_profit = 0.0;
   SaveAnchor();
}

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

double NormalizeVolume(const double requested_volume)
{
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = minimum;

   double capped = MathMin(requested_volume, InpMaximumLot);
   capped = MathMin(capped, maximum);
   capped = MathMax(capped, minimum);

   double normalized = MathFloor((capped + 1e-12) / step) * step;
   normalized = MathMax(normalized, minimum);
   normalized = MathMin(normalized, maximum);

   int volume_digits = 0;
   double probe = step;
   while(volume_digits < 8 && MathAbs(probe - MathRound(probe)) > 1e-10)
   {
      probe *= 10.0;
      volume_digits++;
   }

   return NormalizeDouble(normalized, volume_digits);
}

double LevelVolume(const int level)
{
   double requested = InpBaseLot * MathPow(InpMartingaleMultiplier, level - 1);
   return NormalizeVolume(requested);
}

double NormalizeLimitPrice(const double raw_price, const bool is_buy)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;

   double price;
   if(is_buy)
      price = MathFloor((raw_price / tick_size) + 1e-9) * tick_size;
   else
      price = MathCeil((raw_price / tick_size) - 1e-9) * tick_size;

   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

bool IsManagedSelectedOrder()
{
   return (OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == InpMagicNumber);
}

bool IsManagedSelectedPosition()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
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
   return profit;
}

double ManagedTotalVolume()
{
   double volume = 0.0;

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0 || !IsManagedSelectedOrder())
         continue;
      volume += OrderGetDouble(ORDER_VOLUME_CURRENT);
   }

   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;
      volume += PositionGetDouble(POSITION_VOLUME);
   }

   return volume;
}

bool IsSlotOrderSide(const string comment, const bool is_buy)
{
   string prefix = StringFormat("%s:%s:", SLOT_PREFIX, is_buy ? "B" : "S");
   return (StringFind(comment, prefix) == 0);
}

void DeleteManagedSideOrders(const bool is_buy)
{
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      ulong ticket = OrderGetTicket(index);
      if(ticket == 0 || !IsManagedSelectedOrder())
         continue;
      if(!IsSlotOrderSide(OrderGetString(ORDER_COMMENT), is_buy))
         continue;

      ResetLastError();
      bool sent = trade.OrderDelete(ticket);
      if(!sent || !TradeResultSucceeded())
         LogTradeFailure(StringFormat("Delete filtered order #%I64u", ticket));
   }
}

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

bool MarginAllowsOrder(const bool is_buy, const double volume, const double price)
{
   if(InpMaximumTotalVolume > 0.0 &&
      ManagedTotalVolume() + volume > InpMaximumTotalVolume + 1e-10)
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

   double required_margin = 0.0;
   ENUM_ORDER_TYPE market_type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcMargin(market_type, _Symbol, volume, price, required_margin) &&
      required_margin > 0.0 && InpMarginReservePercent > 0.0)
   {
      double required_free = required_margin * InpMarginReservePercent / 100.0;
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < required_free)
      {
         g_status_text = "Free-margin reserve blocks new limits";
         return false;
      }
   }

   return true;
}

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

double ManagedProfitToday()
{
   datetime now = TimeCurrent();
   datetime start = ServerDayStart(now);
   if(start <= 0 || !HistorySelect(start, now))
      return 0.0;

   double profit = 0.0;
   for(int index = 0; index < HistoryDealsTotal(); index++)
   {
      ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
      profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      profit += HistoryDealGetDouble(ticket, DEAL_FEE);
   }
   return profit;
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

void UpdateDashboard()
{
   string state = g_paused ? "PAUSED" : (g_cycle_closing ? "CLOSING" : g_status_text);
   string lock_text = g_daily_lock_until > TimeCurrent()
                      ? TimeToString(g_daily_lock_until, TIME_DATE | TIME_MINUTES)
                      : "No";

   Comment("GridBot 2X Smart Advanced v2.00\n",
           "State: ", state, "\n",
           "Regime: ", g_regime_text, "\n",
           "Floating: ", DoubleToString(ManagedFloatingProfit(), 2),
           " / Target: ", DoubleToString(InpBasketProfitMoney, 2), "\n",
           "Peak profit: ", DoubleToString(g_peak_profit, 2), "\n",
           "Positions / Orders: ", IntegerToString(ManagedPositionCount()),
           " / ", IntegerToString(ManagedOrderCount()), "\n",
           "Managed lots: ", DoubleToString(ManagedTotalVolume(), 2), "\n",
           "Anchor: ", DoubleToString(g_anchor_price, _Digits),
           " | Step: ", DoubleToString(g_cycle_step_points, 0), " points\n",
           "Daily lock until: ", lock_text);
}

bool SlotExists(const bool is_buy, const int level)
{
   string tag = SlotTag(is_buy, level);

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0 || !IsManagedSelectedOrder())
         continue;

      if(OrderGetString(ORDER_COMMENT) == tag)
         return true;
   }

   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;

      if(PositionGetString(POSITION_COMMENT) == tag)
         return true;
   }

   return false;
}

bool TradeResultSucceeded()
{
   uint code = trade.ResultRetcode();
   return (code == TRADE_RETCODE_DONE ||
           code == TRADE_RETCODE_PLACED ||
           code == TRADE_RETCODE_DONE_PARTIAL);
}

void LogTradeFailure(const string action)
{
   datetime now = TimeCurrent();
   if(now - g_last_error_log < 10)
      return;

   g_last_error_log = now;
   PrintFormat("%s failed. Retcode=%u (%s), broker comment=%s",
               action,
               trade.ResultRetcode(),
               trade.ResultRetcodeDescription(),
               trade.ResultComment());
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
//| Anchor restoration                                               |
//+------------------------------------------------------------------+
bool InferAnchorFromExistingOrders(double &anchor)
{
   double distance = CycleStepPrice();

   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      if(OrderGetTicket(index) == 0 || !IsManagedSelectedOrder())
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      double order_price = OrderGetDouble(ORDER_PRICE_OPEN);

      for(int level = 1; level <= InpLevelsPerSide; level++)
      {
         if(comment == SlotTag(true, level))
         {
            anchor = order_price + level * distance;
            return true;
         }
         if(comment == SlotTag(false, level))
         {
            anchor = order_price - level * distance;
            return true;
         }
      }
   }

   return false;
}

bool InferAnchorFromExistingPositions(double &anchor)
{
   double distance = CycleStepPrice();

   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      if(PositionGetTicket(index) == 0 || !IsManagedSelectedPosition())
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

      for(int level = 1; level <= InpLevelsPerSide; level++)
      {
         if(comment == SlotTag(true, level))
         {
            anchor = open_price + level * distance;
            return true;
         }
         if(comment == SlotTag(false, level))
         {
            anchor = open_price - level * distance;
            return true;
         }
      }
   }

   return false;
}

void RestoreOrCreateAnchor()
{
   string step_name = StepVariableName();
   if(GlobalVariableCheck(step_name))
      g_cycle_step_points = GlobalVariableGet(step_name);
   if(g_cycle_step_points <= 0.0)
      g_cycle_step_points = CalculateSmartStepPoints();

   string name = AnchorVariableName();
   if(GlobalVariableCheck(name))
   {
      double saved = GlobalVariableGet(name);
      if(saved > 0.0)
      {
         g_anchor_price = saved;
         return;
      }
   }

   double inferred = 0.0;
   if(InferAnchorFromExistingOrders(inferred) ||
      InferAnchorFromExistingPositions(inferred))
   {
      g_anchor_price = inferred;
      SaveAnchor();
      return;
   }

   StartNewCycleState();
}

//+------------------------------------------------------------------+
//| Order and basket operations                                      |
//+------------------------------------------------------------------+
bool PlaceGridOrder(const bool is_buy, const int level, const MqlTick &tick)
{
   double distance = CycleStepPrice();
   double raw_price = is_buy
                      ? g_anchor_price - level * distance
                      : g_anchor_price + level * distance;
   double price = NormalizeLimitPrice(raw_price, is_buy);

   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minimum_distance = MathMax(stops_level * _Point,
                                     SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));

   if(is_buy && price >= tick.ask - minimum_distance)
      return false;
   if(!is_buy && price <= tick.bid + minimum_distance)
      return false;

   double volume = LevelVolume(level);
   if(!MarginAllowsOrder(is_buy, volume, price))
      return false;
   string tag = SlotTag(is_buy, level);

   ResetLastError();
   bool sent;
   if(is_buy)
      sent = trade.BuyLimit(volume, price, _Symbol, 0.0, 0.0,
                            ORDER_TIME_GTC, 0, tag);
   else
      sent = trade.SellLimit(volume, price, _Symbol, 0.0, 0.0,
                             ORDER_TIME_GTC, 0, tag);

   if(!sent || !TradeResultSucceeded())
   {
      LogTradeFailure(StringFormat("Place %s level %d", is_buy ? "buy limit" : "sell limit", level));
      return false;
   }

   PrintFormat("Placed %s level %d: %.2f lots at %.*f",
               is_buy ? "buy limit" : "sell limit",
               level,
               volume,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               price);
   return true;
}

void MaintainGrid()
{
   if(g_anchor_price <= 0.0 || !TradingIsAvailable())
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
      DeleteManagedSideOrders(true);
   if(!allow_sell)
      DeleteManagedSideOrders(false);

   g_status_text = "Grid active";

   for(int level = 1; level <= InpLevelsPerSide; level++)
   {
      if(allow_buy && !SlotExists(true, level))
         PlaceGridOrder(true, level, tick);

      if(allow_sell && !SlotExists(false, level))
         PlaceGridOrder(false, level, tick);
   }
}

void DeleteManagedOrders()
{
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      ulong ticket = OrderGetTicket(index);
      if(ticket == 0 || !IsManagedSelectedOrder())
         continue;

      ResetLastError();
      bool sent = trade.OrderDelete(ticket);
      if(!sent || !TradeResultSucceeded())
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
   DeleteManagedOrders();
   CloseManagedPositions();

   if(HasManagedExposure())
      return;

   RemoveSavedAnchor();
   g_cycle_closing = false;

   if(g_daily_lock_until > TimeCurrent())
   {
      g_anchor_price = 0.0;
      g_cycle_step_points = 0.0;
      g_status_text = "Daily loss lock";
      PrintFormat("Basket is flat. Daily loss lock remains until %s.",
                  TimeToString(g_daily_lock_until, TIME_DATE | TIME_MINUTES));
      return;
   }

   if(g_pause_after_close || !InpAutoRestartAfterProfit)
   {
      g_paused = true;
      Print("Basket is flat. The EA is paused; reattach it to start another cycle.");
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

   double current = CurrentReferencePrice();
   if(current <= 0.0 || g_anchor_price <= 0.0)
      return;

   double threshold = InpRecenterAfterSteps * CycleStepPrice();
   if(MathAbs(current - g_anchor_price) < threshold)
      return;

   DeleteManagedOrders();
   if(ManagedOrderCount() > 0)
      return;

   StartNewCycleState();
   PrintFormat("Flat grid recentered at %.*f",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               g_anchor_price);
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
      StartNewCycleState();
      g_next_build_time = now;
      g_status_text = "Daily lock released";
      Print("New broker day: daily loss lock released.");
   }

   if(InpDailyLossLimitMoney > 0.0 && g_daily_lock_until == 0)
   {
      double today_result = ManagedProfitToday() + ManagedFloatingProfit();
      if(today_result <= -InpDailyLossLimitMoney)
      {
         g_daily_lock_until = ServerDayStart(now) + 86400;
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

      if(floating_profit >= InpBasketProfitMoney)
      {
         StartBasketClose(false,
                          StringFormat("profit target reached (%.2f)", floating_profit));
         ContinueBasketClose();
         FinishManagePass();
         return;
      }

      if(InpUseBasketProfitTrail &&
         g_peak_profit >= InpTrailStartMoney &&
         g_peak_profit - floating_profit >= InpTrailGivebackMoney)
      {
         StartBasketClose(false,
                          StringFormat("profit trail triggered: peak %.2f, current %.2f",
                                       g_peak_profit, floating_profit));
         ContinueBasketClose();
         FinishManagePass();
         return;
      }

      if(InpEmergencyLossMoney > 0.0 &&
         floating_profit <= -InpEmergencyLossMoney)
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
         DeleteManagedOrders();
      FinishManagePass();
      return;
   }

   if(TimeCurrent() < g_next_build_time)
   {
      g_status_text = "Restart cooldown";
      FinishManagePass();
      return;
   }

   if(g_anchor_price <= 0.0 || g_cycle_step_points <= 0.0)
      StartNewCycleState();

   RecenterFlatGridIfNeeded();
   MaintainGrid();
   FinishManagePass();
}

//+------------------------------------------------------------------+
//| MT5 event handlers                                               |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpBaseLot <= 0.0 ||
      InpLevelsPerSide < 1 ||
      InpGridStepPoints < 1 ||
      InpMartingaleMultiplier < 1.0 ||
      InpMaximumLot <= 0.0 ||
      InpBasketProfitMoney <= 0.0 ||
      InpATRPeriod < 1 ||
      InpATRMultiplier <= 0.0 ||
      InpMinimumGridStepPoints < 1 ||
      InpMaximumGridStepPoints < InpMinimumGridStepPoints ||
      InpFastEMAPeriod < 1 ||
      InpSlowEMAPeriod <= InpFastEMAPeriod ||
      InpTrendGapPoints < 0 ||
      (InpUseBasketProfitTrail &&
       (InpTrailStartMoney < 0.0 || InpTrailGivebackMoney <= 0.0)) ||
      InpEmergencyLossMoney < 0.0 ||
      InpMaxBasketDrawdownPercent < 0.0 ||
      InpMaximumTotalVolume < 0.0 ||
      InpMinimumMarginLevelPercent < 0.0 ||
      InpMarginReservePercent < 0.0 ||
      InpDailyLossLimitMoney < 0.0 ||
      InpRestartDelaySeconds < 0 ||
      InpRecenterAfterSteps < 1 ||
      InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 23 ||
      InpMagicNumber <= 0)
   {
      Print("Invalid input parameter(s). Check lot, level, step, target, delay and magic values.");
      return INIT_PARAMETERS_INCORRECT;
   }

   ENUM_ACCOUNT_MARGIN_MODE margin_mode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("GridBot_2X_AutoUpdate requires an MT5 hedging account. Netting mode is not supported.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
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

   RestoreOrCreateAnchor();
   if(g_anchor_price <= 0.0)
   {
      Print("Could not obtain a valid market price for the initial grid anchor.");
      return INIT_FAILED;
   }

   EventSetTimer(1);
   PrintFormat("GridBot Smart Advanced v2 initialized on %s at anchor %.*f, step %.0f points. Magic=%I64d",
               _Symbol,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               g_anchor_price,
               g_cycle_step_points,
               InpMagicNumber);
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
   // Run immediately after fills, closes or manual pending-order deletions.
   ManageEA();
}
