//+------------------------------------------------------------------+
//|                                                    Execution.mqh |
//|  TRADE layer. Every OrderSend in this project passes through      |
//|  these functions and nowhere else, so validation, retries and     |
//|  logging exist in exactly one place.                              |
//+------------------------------------------------------------------+
#ifndef GFEA_EXECUTION_MQH
#define GFEA_EXECUTION_MQH

#include <Trade\Trade.mqh>
#include "Telemetry.mqh"

CTrade g_trade;

//+------------------------------------------------------------------+
//| Broker filling mode for this symbol.                             |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING SymbolFilling(void)
  {
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

void ExecutionInit(void)
  {
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)MathMax(1, InpSlippagePoints));
   g_trade.SetTypeFillingBySymbol(_Symbol);   // avoids retcode 10030
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
  }

//+------------------------------------------------------------------+
//| Resolve the position a freshly executed deal belongs to.         |
//| Hedging: the deal's position id IS the position ticket.          |
//| Netting: the symbol has exactly one position, so select by symbol.|
//+------------------------------------------------------------------+
ulong ResolvePositionTicket(const ulong dealTicket)
  {
   if(!g_ea.hedging)
     {
      if(PositionSelect(_Symbol))
         return (ulong)PositionGetInteger(POSITION_TICKET);
      return 0;
     }

   if(dealTicket > 0 && HistoryDealSelect(dealTicket))
     {
      ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(posId > 0 && PositionSelectByTicket(posId))
         return posId;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Margin and server-side pre-validation before anything is sent.   |
//+------------------------------------------------------------------+
bool PreflightOrder(const ENUM_ORDER_TYPE type, const double lots,
                    const double price, const double sl, const double tp)
  {
   double need = 0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, need))
     {
      LogError("OrderCalcMargin failed");
      return false;
     }
   if(need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.90)
     {
      LogInfo(StringFormat("Skipped: margin %.2f exceeds 90%% of free margin", need));
      return false;
     }

   MqlTradeRequest req;
   MqlTradeCheckResult chk;
   ZeroMemory(req);
   ZeroMemory(chk);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = lots;
   req.type         = type;
   req.price        = price;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = (ulong)MathMax(1, InpSlippagePoints);
   req.magic        = (ulong)InpMagic;
   req.type_filling = SymbolFilling();

   if(!OrderCheck(req, chk))
     {
      LogError(StringFormat("Pre-check rejected: retcode=%u %s", chk.retcode, chk.comment));
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Open one market position. Returns the position ticket, or 0.     |
//| The dir = +/-1 trick collapses buy and sell into one path.       |
//+------------------------------------------------------------------+
ulong OpenMarket(const int dir, const double lots, const double sl, const double tp,
                 const string tag)
  {
   if(lots <= 0) return 0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string comment = StringFormat("%s-%s", InpTradeComment, tag);

   for(int attempt = 0; attempt < RETRY_MAX; attempt++)
     {
      double price = SymbolInfoDouble(_Symbol, dir > 0 ? SYMBOL_ASK : SYMBOL_BID);
      if(price <= 0) break;

      //--- re-clamp the stops to the CURRENT market on every attempt
      double useSl = (sl > 0) ? ClampStop(dir, sl, true)  : 0.0;
      double useTp = (tp > 0) ? ClampStop(dir, tp, false) : 0.0;

      if(attempt == 0 && !PreflightOrder(type, lots, price, useSl, useTp))
         return 0;

      g_ea.stats.tradesSent++;
      bool ok = (dir > 0) ? g_trade.Buy(lots, _Symbol, 0.0, useSl, useTp, comment)
                          : g_trade.Sell(lots, _Symbol, 0.0, useSl, useTp, comment);
      uint rc = g_trade.ResultRetcode();

      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
         return ResolvePositionTicket(g_trade.ResultDeal());

      if(!IsRetryable(rc)) break;
     }

   g_ea.stats.tradesFailed++;
   LogError(StringFormat("Open %s %.2f failed: retcode=%u (%s)",
                         DirText(dir), lots, g_trade.ResultRetcode(),
                         g_trade.ResultRetcodeDescription()));
   return 0;
  }

//+------------------------------------------------------------------+
//| Modify one position's stop / target, never sending a no-op.      |
//+------------------------------------------------------------------+
bool ModifyPositionLevels(const ulong ticket, const double sl, const double tp)
  {
   if(!PositionSelectByTicket(ticket)) return false;

   double curSl = PositionGetDouble(POSITION_SL);
   double curTp = PositionGetDouble(POSITION_TP);
   int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

   double newSl = (sl > 0) ? ClampStop(dir, sl, true)  : curSl;
   double newTp = (tp > 0) ? ClampStop(dir, tp, false) : curTp;

   //--- retcode 10025 (NO_CHANGES) is an ERROR server-side: skip no-ops
   if(!LevelsDiffer(newSl, curSl) && !LevelsDiffer(newTp, curTp)) return false;

   //--- inside the freeze band the server refuses modifications outright
   double px   = PositionGetDouble(POSITION_PRICE_CURRENT);
   double dist = MinStopDistance();
   if(newSl > 0 && MathAbs(px - newSl) < dist) return false;

   if(!g_trade.PositionModify(ticket, newSl, newTp))
     {
      LogError(StringFormat("Modify #%I64u failed retcode=%u", ticket, g_trade.ResultRetcode()));
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Apply one shared stop to every position of the basket.           |
//+------------------------------------------------------------------+
int SetBasketStop(const double sl)
  {
   int changed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsMine()) continue;
      if(ModifyPositionLevels(t, sl, 0)) changed++;
     }
   return changed;
  }

//+------------------------------------------------------------------+
//| Close one position with retries.                                 |
//+------------------------------------------------------------------+
bool ClosePositionTicket(const ulong ticket)
  {
   for(int attempt = 0; attempt < RETRY_MAX; attempt++)
     {
      if(!PositionSelectByTicket(ticket)) return true;   // already gone
      if(g_trade.PositionClose(ticket) &&
         g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         return true;
      if(!IsRetryable(g_trade.ResultRetcode())) break;
     }
   LogError(StringFormat("Close #%I64u failed retcode=%u", ticket, g_trade.ResultRetcode()));
   return false;
  }

//+------------------------------------------------------------------+
//| Close the whole basket. Descending iteration is mandatory:       |
//| indices shift as positions disappear.                            |
//+------------------------------------------------------------------+
int CloseAllMine(const string why)
  {
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsMine()) continue;
      if(ClosePositionTicket(t)) closed++;
     }

   //--- and any pending order this EA may have left behind
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)  continue;
      g_trade.OrderDelete(t);
     }

   if(closed > 0) LogInfo(StringFormat("Closed %d position(s): %s", closed, why));
   return closed;
  }

//+------------------------------------------------------------------+
//| Close a percentage of every position in the basket.              |
//| Volumes below one step are closed whole rather than left as dust.|
//+------------------------------------------------------------------+
double ClosePartialBasket(const double percent, const string why)
  {
   if(percent <= 0) return 0;
   double pct       = MathMin(percent, 100.0) / 100.0;
   double closed    = 0;
   int    remaining = CountMyPositions();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsMine()) continue;

      double vol  = PositionGetDouble(POSITION_VOLUME);
      double part = NormalizeVolume(vol * pct);

      if(part <= 0 || vol - part < g_ea.volMin)
        {
         //--- This position cannot be split and leave a tradeable remainder.
         //--- With several positions open, closing this one whole IS the
         //--- partial. With only one left, closing it would silently turn a
         //--- 40% take into a 100% exit, so it is left to run to the final
         //--- target instead.
         if(remaining > 1 && ClosePositionTicket(t))
           {
            closed += vol;
            remaining--;
           }
         continue;
        }
      if(g_trade.PositionClosePartial(t, part) &&
         g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         closed += part;
      else
         LogError(StringFormat("Partial close #%I64u failed retcode=%u",
                               t, g_trade.ResultRetcode()));
     }

   if(closed > 0) LogInfo(StringFormat("Partial close %.2f lots: %s", closed, why));
   return closed;
  }

#endif // GFEA_EXECUTION_MQH
//+------------------------------------------------------------------+
