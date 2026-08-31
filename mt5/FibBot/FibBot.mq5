//+------------------------------------------------------------------+
//|                                                       FibBot.mq5 |
//|  Fibonacci retracement bot for the Trading Signals Platform.     |
//|                                                                  |
//|  Detects non-repainting swing pivots, arms a retracement setup   |
//|  only when independent non-Fibonacci confluence agrees, waits    |
//|  for a confirmation close, then draws it and (optionally)        |
//|  trades it. Self-contained: it talks to no network service.      |
//|                                                                  |
//|  Method and evidence: docs/education/fibonacci-retracement.md    |
//|  Setup, inputs and caveats: mt5/FibBot/README.md                 |
//|                                                                  |
//|  Attach one instance per chart; it trades only that chart's      |
//|  symbol and timeframe.                                           |
//+------------------------------------------------------------------+
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property description "Fibonacci retracement setups: detect, draw, optionally trade."

#include "Config.mqh"
#include "Util.mqh"
#include "Swing.mqh"
#include "Fib.mqh"
#include "Execution.mqh"
#include "Visuals.mqh"

//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   ZeroMemory(g_bot);
   g_bot.hATR     = INVALID_HANDLE;
   g_bot.hTrendMA = INVALID_HANDLE;
   ArrayFree(g_pivots);
   SetupReset();

   g_bot.hATR = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_bot.hATR == INVALID_HANDLE)
     {
      PrintFormat("%sATR handle failed: %d", LOG_PREFIX, GetLastError());
      return(INIT_FAILED);
     }

   if(InpUseTrendFilter)
     {
      g_bot.hTrendMA = iMA(_Symbol, InpTrendTimeframe, InpTrendMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_bot.hTrendMA == INVALID_HANDLE)
        {
         PrintFormat("%sTrend MA handle failed: %d", LOG_PREFIX, GetLastError());
         return(INIT_FAILED);
        }
     }

   TradeInit();
   g_bot.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_bot.lastDayTs       = 0;

   PrintFormat("%sReady on %s %s. Trading %s.", LOG_PREFIX,
               _Symbol, TimeframeName((ENUM_TIMEFRAMES)_Period),
               InpEnableTrading ? "ENABLED" : "disabled");

   if(InpEnableTrading && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      PrintFormat("%sTrading is enabled in the inputs but AutoTrading is off in the terminal.",
                  LOG_PREFIX);

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_bot.hATR != INVALID_HANDLE)
      IndicatorRelease(g_bot.hATR);
   if(g_bot.hTrendMA != INVALID_HANDLE)
      IndicatorRelease(g_bot.hTrendMA);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ChartRedraw();
  }

void OnTick()
  {
   ManageOpenTrade();                 // الأهداف الجزئية تحتاج كل تيك

   if(!IsNewBar(g_bot.lastBar))
      return;

   ProcessBar();
   VisualsDraw();
  }

//+------------------------------------------------------------------+
//| CORE — the bar pipeline                                          |
//+------------------------------------------------------------------+
void ProcessBar()
  {
   bool newPivot = SwingScanNewBar();

   // تقدّم الإعداد القائم أولاً حتى لا تُلغى ساق صالحة بنقطة جديدة
   if(g_setup.state != SETUP_IDLE)
     {
      SetupAdvanceOnBar();
      HandleSetupOutcome();
     }

   if(g_setup.state == SETUP_IDLE && newPivot && CountMyPositions() == 0)
     {
      SetupTryArm();
      return;
     }

   if(g_setup.state == SETUP_IN_ZONE && SetupTriggerFired())
      EnterFromSetup();
  }

void EnterFromSetup()
  {
   double fill = OpenFromSetup();     // تعيد صفراً عندما يكون التنفيذ مطفأً

   g_setup.state = SETUP_TRIGGERED;

   if(fill <= 0 && !InpEnableTrading)
      PrintFormat("%sTrigger confirmed at %s — execution is off, nothing sent.", LOG_PREFIX,
                  DoubleToString(iClose(_Symbol, _Period, 1), _Digits));
  }

void HandleSetupOutcome()
  {
   if(g_setup.state != SETUP_INVALIDATED && g_setup.state != SETUP_EXPIRED)
      return;

   PrintFormat("%sSetup ended: %s", LOG_PREFIX, EnumToString(g_setup.state));
   SetupReset();
   VisualsClear();
  }

//+------------------------------------------------------------------+
//| TRADE management — partials, break-even, close detection         |
//+------------------------------------------------------------------+
void ManageOpenTrade()
  {
   ulong ticket = FindMyTicket();

   if(ticket == 0)
     {
      // المركز اختفى: نظّف حالة الصفقة وحرّر مكاناً لإعداد جديد
      if(g_bot.ticket != 0)
        {
         g_bot.ticket     = 0;
         g_bot.posId      = 0;
         g_bot.entryPrice = 0;
         if(g_setup.state == SETUP_TRIGGERED)
           {
            SetupReset();
            VisualsClear();
           }
        }
      return;
     }

   g_bot.ticket = ticket;

   // مركز تبنّاه الإكسبيرت بعد إعادة تشغيل: لا إعداد يصف أهدافه، فاتركه لوقفه وهدفه
   if(g_setup.state != SETUP_TRIGGERED)
      return;

   if(!g_bot.tp1Done && TargetReached(g_setup.tp1))
     {
      PrintFormat("%sTP1 reached at %s.", LOG_PREFIX, DoubleToString(g_setup.tp1, _Digits));
      if(InpTp1ClosePct > 0 && ClosePartialPct(ticket, InpTp1ClosePct))
         PrintFormat("%sTP1 partial closed (%.0f%%).", LOG_PREFIX, InpTp1ClosePct);
      g_bot.tp1Done = true;

      if(InpBeAtTp1 && !g_bot.beDone && MoveStopToBreakEven(ticket))
        {
         PrintFormat("%sStop moved to break-even at %s.", LOG_PREFIX,
                     DoubleToString(g_bot.entryPrice, _Digits));
         g_bot.beDone = true;
        }
     }

   if(!g_bot.tp2Done && TargetReached(g_setup.tp2))
     {
      PrintFormat("%sTP2 reached at %s.", LOG_PREFIX, DoubleToString(g_setup.tp2, _Digits));
      if(InpTp2ClosePct > 0 && ClosePartialPct(ticket, InpTp2ClosePct))
         PrintFormat("%sTP2 partial closed (%.0f%%).", LOG_PREFIX, InpTp2ClosePct);
      g_bot.tp2Done = true;
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   // الصفقات التي يغلقها الخادم قد تصل بسحر صفري — طابِق بمعرّف المركز أيضاً
   long  magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(magic != InpMagic && (g_bot.posId == 0 || posId != g_bot.posId))
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   // إغلاق جزئي: المركز ما زال قائماً، وقد أُبلغ عنه في ManageOpenTrade
   if(posId != 0 && PositionSelectByTicket(posId))
      return;

   long   reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double pl     = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   string how = (reason == DEAL_REASON_SL)
                ? (g_bot.beDone ? "stopped out at break-even" : "stop loss")
                : (reason == DEAL_REASON_TP ? "final target" : "closed");

   PrintFormat("%sPosition %s at %s, P/L %.2f", LOG_PREFIX, how,
               DoubleToString(price, _Digits), pl);
  }

//+------------------------------------------------------------------+
//| CONFIG validation                                                |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpPivotLeft < 1 || InpPivotRight < 1)
     {
      PrintFormat("%sPivot left/right must be at least 1.", LOG_PREFIX);
      return(false);
     }
   if(InpEntryFibNear <= 0.0 || InpEntryFibFar >= 1.0 || InpEntryFibNear >= InpEntryFibFar)
     {
      PrintFormat("%sEntry zone must satisfy 0 < near < far < 1.", LOG_PREFIX);
      return(false);
     }
   if(InpStopFib < InpEntryFibFar)
     {
      // وقف أقرب من حافة النطاق العميقة يُضرب قبل أن يُختبر الإعداد
      PrintFormat("%sStop retracement (%.3f) must be at least the deep zone edge (%.3f).",
                  LOG_PREFIX, InpStopFib, InpEntryFibFar);
      return(false);
     }
   if(InpTp1Extension < 1.0 || InpTp2Extension < InpTp1Extension || InpTp3Extension < InpTp2Extension)
     {
      PrintFormat("%sTargets must satisfy 1.0 <= TP1 <= TP2 <= TP3.", LOG_PREFIX);
      return(false);
     }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 100.0)
     {
      PrintFormat("%sRisk percent must be between 0 and 100.", LOG_PREFIX);
      return(false);
     }
   if(InpTp1ClosePct + InpTp2ClosePct >= 100.0)
     {
      PrintFormat("%sTP1 and TP2 partials must leave something for TP3.", LOG_PREFIX);
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| OnTester — reject samples too small to mean anything             |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 30)
      return(0);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = MathMax(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 1.0);
   return(TesterStatistics(STAT_PROFIT) * pf / dd);
  }
//+------------------------------------------------------------------+
