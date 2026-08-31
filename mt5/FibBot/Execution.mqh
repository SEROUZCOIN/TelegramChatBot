//+------------------------------------------------------------------+
//|                                                    Execution.mqh |
//|  TRADE: every CTrade call in this program lives in this file.    |
//|  Execution is opt-in (InpEnableTrading, default false) — with it |
//|  off the bot analyses and publishes and never touches an order.  |
//+------------------------------------------------------------------+
#ifndef FIBBOT_EXECUTION_MQH
#define FIBBOT_EXECUTION_MQH

#include <Trade\Trade.mqh>
#include "Config.mqh"
#include "Fib.mqh"
#include "Util.mqh"

CTrade g_trade;

//--- setup ---------------------------------------------------------

void TradeInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFillingBySymbol(_Symbol);   // يمنع 10030 Unsupported filling mode
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
  }

//--- inspection ----------------------------------------------------

int CountMyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      count++;
     }
   return(count);
  }

// تذكرة أول مركز يخص هذا الإكسبيرت على هذا الرمز، أو صفر
ulong FindMyTicket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      return(t);
     }
   return(0);
  }

//--- daily loss guard ----------------------------------------------

// يعيد false = لا تتداول اليوم
bool DailyGuardOk()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayOpen = StructToTime(dt);

   if(dayOpen > g_bot.lastDayTs)
     {
      g_bot.dayStartBalance = balance;
      g_bot.lastDayTs       = dayOpen;
      g_bot.halted          = false;      // يوم جديد يرفع الإيقاف
     }

   if(g_bot.halted)
      return(false);

   if(InpMaxDailyLossPct <= 0 || g_bot.dayStartBalance <= 0)
      return(true);

   double loss  = g_bot.dayStartBalance - equity;
   double limit = g_bot.dayStartBalance * InpMaxDailyLossPct / 100.0;
   if(loss >= limit)
     {
      PrintFormat("%sDaily loss %.2f reached the %.2f limit — halted until tomorrow.",
                  LOG_PREFIX, loss, limit);
      g_bot.halted = true;
      return(false);
     }
   return(true);
  }

//--- opening -------------------------------------------------------

// يفتح المركز من الإعداد المسلَّح. يعيد سعر التنفيذ أو صفراً.
double OpenFromSetup()
  {
   if(!InpEnableTrading)
      return(0);
   if(!DailyGuardOk())
      return(0);
   if(CountMyPositions() > 0)
      return(0);
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
     {
      PrintFormat("%sSpread %d exceeds the %d limit — entry skipped.", LOG_PREFIX,
                  (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPts);
      return(0);
     }

   bool   isBuy = (g_setup.dir > 0);
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);
   if(price <= 0)
      return(0);

   double minDist = MinStopDistance(_Symbol);
   double sl = g_setup.stop;
   double tp = g_setup.tp3;

   // ادفع الوقف والهدف خارج نطاق البروكر الممنوع إن لزم
   if(isBuy)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(sl > bid - minDist)
         sl = bid - minDist;
      if(tp < bid + minDist)
         tp = bid + minDist;
     }
   else
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(sl < ask + minDist)
         sl = ask + minDist;
      if(tp > ask - minDist)
         tp = ask - minDist;
     }
   sl = NormalizePriceTick(_Symbol, sl);
   tp = NormalizePriceTick(_Symbol, tp);

   double stopDistance = MathAbs(price - sl);
   if(stopDistance <= 0)
      return(0);

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lot       = LotsForRisk(_Symbol, riskMoney, stopDistance);
   if(lot <= 0)
     {
      // لا ترفع الحجم إلى الحد الأدنى سراً — ذلك يكسر إدارة المخاطر
      PrintFormat("%sRisk-sized lot is below the broker minimum — entry skipped.", LOG_PREFIX);
      return(0);
     }

   double need = 0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, need) ||
      need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      PrintFormat("%sInsufficient free margin for %.2f lots — entry skipped.", LOG_PREFIX, lot);
      return(0);
     }

   for(int attempt = 0; attempt < RETRY_MAX; attempt++)
     {
      bool ok = isBuy ? g_trade.Buy(lot, _Symbol, 0, sl, tp, "FibBot")
                      : g_trade.Sell(lot, _Symbol, 0, sl, tp, "FibBot");
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
        {
         double fill = g_trade.ResultPrice();
         if(fill <= 0)
            fill = price;
         g_bot.ticket     = FindMyTicket();
         g_bot.posId      = (g_bot.ticket != 0 && PositionSelectByTicket(g_bot.ticket))
                            ? (ulong)PositionGetInteger(POSITION_IDENTIFIER) : 0;
         g_bot.entryPrice = fill;
         g_bot.beDone     = false;
         g_bot.tp1Done    = false;
         g_bot.tp2Done    = false;
         PrintFormat("%sOpened %s %.2f lots at %s, stop %s, final target %s",
                     LOG_PREFIX, isBuy ? "BUY" : "SELL", lot,
                     DoubleToString(fill, _Digits), DoubleToString(sl, _Digits),
                     DoubleToString(tp, _Digits));
         return(fill);
        }
      if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED &&
         rc != TRADE_RETCODE_PRICE_OFF)
         break;
     }

   PrintFormat("%sOpen failed retcode=%u (%s)", LOG_PREFIX,
               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(0);
  }

//--- management ----------------------------------------------------

// إغلاق جزئي آمن: لا يترك بقية أصغر من الحد الأدنى للحجم
bool ClosePartialPct(const ulong ticket, const double percent)
  {
   if(percent <= 0)
      return(false);
   if(!PositionSelectByTicket(ticket))
      return(false);

   double current = PositionGetDouble(POSITION_VOLUME);
   double minV    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double want    = NormalizeVolumeStep(_Symbol, current * percent / 100.0);

   if(want <= 0)
      return(false);
   if(current - want < minV)
      return(false);          // البقية ستكون غير صالحة — اترك المركز كما هو

   return(g_trade.PositionClosePartial(ticket, want));
  }

bool MoveStopToBreakEven(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return(false);

   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSl  = PositionGetDouble(POSITION_SL);
   double curTp  = PositionGetDouble(POSITION_TP);
   long   type   = PositionGetInteger(POSITION_TYPE);
   double newSl  = NormalizePriceTick(_Symbol, entry);

   if(!LevelsDiffer(_Symbol, newSl, curSl))
      return(false);          // لا تغيير حقيقي — يمنع 10025

   double dist = MinStopDistance(_Symbol);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY  && newSl > bid - dist)
      return(false);
   if(type == POSITION_TYPE_SELL && newSl < ask + dist)
      return(false);

   return(g_trade.PositionModify(ticket, newSl, curTp));
  }

// هل بلغ السعر هدفاً؟ يُقاس على السعر الحي في اتجاه الصفقة
bool TargetReached(const double target)
  {
   if(target <= 0)
      return(false);
   double price = SymbolInfoDouble(_Symbol, g_setup.dir > 0 ? SYMBOL_BID : SYMBOL_ASK);
   if(price <= 0)
      return(false);
   return(AdvancedPast(price, target, g_setup.dir));
  }

#endif // FIBBOT_EXECUTION_MQH
//+------------------------------------------------------------------+
