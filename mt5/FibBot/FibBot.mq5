//+------------------------------------------------------------------+
//|                                                       FibBot.mq5 |
//|  Fibonacci retracement bot for the Trading Signals Platform.     |
//|                                                                  |
//|  Detects non-repainting swing pivots, arms a retracement setup   |
//|  only when independent non-Fibonacci confluence agrees, waits    |
//|  for a confirmation close, then publishes the setup to the       |
//|  platform API and (optionally) trades it.                        |
//|                                                                  |
//|  Method and evidence: docs/education/fibonacci-retracement.md    |
//|  Setup, inputs and caveats: mt5/FibBot/README.md                 |
//|                                                                  |
//|  Attach one instance per chart; it trades only that chart's      |
//|  symbol and timeframe.                                           |
//+------------------------------------------------------------------+
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property description "Fibonacci retracement setups: detect, publish, optionally trade."

#include "Config.mqh"
#include "Util.mqh"
#include "Swing.mqh"
#include "Fib.mqh"
#include "Execution.mqh"
#include "Api.mqh"
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

   EventSetTimer(1);      // تصريف طابور الشبكة فقط — لا منطق تداول هنا

   PrintFormat("%sReady on %s %s. Trading %s, publishing %s.", LOG_PREFIX,
               _Symbol, TimeframeName((ENUM_TIMEFRAMES)_Period),
               InpEnableTrading ? "ENABLED" : "disabled",
               ApiEnabled() ? "enabled" : "disabled");

   if(InpEnableTrading && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      PrintFormat("%sTrading is enabled in the inputs but AutoTrading is off in the terminal.",
                  LOG_PREFIX);

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
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

// المؤقّت لا يتخذ قرار تداول — مهمته الوحيدة تصريف طلبات HTTP الحاجبة
void OnTimer()
  {
   ApiFlush();
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
      if(SetupTryArm() && InpPublishWhen == PUBLISH_ON_SETUP)
         ApiPublishSetup(false, 0);
      return;
     }

   if(g_setup.state == SETUP_IN_ZONE)
     {
      ReportZoneEntryOnce();
      if(SetupTriggerFired())
         EnterFromSetup();
     }
  }

// دخول السعر للنطاق يخص إشارة منشورة مسبقاً كأمر معلّق فقط
void ReportZoneEntryOnce()
  {
   if(g_setup.entryReported || !g_setup.published)
      return;
   if(InpPublishWhen != PUBLISH_ON_SETUP)
      return;
   ApiReportUpdate("ENTRY_HIT", iClose(_Symbol, _Period, 1), "Price reached the entry zone.");
   g_setup.entryReported = true;
  }

void EnterFromSetup()
  {
   double fill = OpenFromSetup();     // تعيد صفراً عندما يكون التنفيذ مطفأً

   if(InpPublishWhen == PUBLISH_ON_ENTRY && !g_setup.published)
     {
      double published = (fill > 0) ? fill : iClose(_Symbol, _Period, 1);
      ApiPublishSetup(true, published);
     }

   g_setup.state = SETUP_TRIGGERED;

   if(fill <= 0 && !InpEnableTrading)
      PrintFormat("%sTrigger confirmed — signal published, execution is off.", LOG_PREFIX);
  }

// الإعداد انتهى دون دخول: ألغِ الإشارة المنشورة إن وُجدت وابدأ من جديد
void HandleSetupOutcome()
  {
   if(g_setup.state != SETUP_INVALIDATED && g_setup.state != SETUP_EXPIRED)
      return;

   if(g_setup.published)
     {
      string why = (g_setup.state == SETUP_INVALIDATED)
                   ? "Price closed beyond the leg origin — setup invalidated."
                   : "The setup expired before price reached the entry zone.";
      ApiReportUpdate("CANCELLED", 0, why);
     }

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
      if(InpTp1ClosePct > 0 && ClosePartialPct(ticket, InpTp1ClosePct))
         PrintFormat("%sTP1 partial closed (%.0f%%).", LOG_PREFIX, InpTp1ClosePct);
      ApiReportUpdate("TP1_HIT", g_setup.tp1, "First target reached.");
      g_bot.tp1Done = true;

      if(InpBeAtTp1 && !g_bot.beDone && MoveStopToBreakEven(ticket))
        {
         // المنصة تحتسب الوقف بعد نقله للتعادل خدشاً لا خسارة — لهذا يُبلَّغ
         ApiReportUpdate("MOVED_TO_BE", g_bot.entryPrice, "Stop moved to break-even.");
         g_bot.beDone = true;
        }
     }

   if(!g_bot.tp2Done && TargetReached(g_setup.tp2))
     {
      if(InpTp2ClosePct > 0 && ClosePartialPct(ticket, InpTp2ClosePct))
         PrintFormat("%sTP2 partial closed (%.0f%%).", LOG_PREFIX, InpTp2ClosePct);
      ApiReportUpdate("TP2_HIT", g_setup.tp2, "Second target reached.");
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

   if(reason == DEAL_REASON_SL)
     {
      // بعد نقل الوقف للتعادل تحتسب المنصة الضربة خدشاً، لذا الحدث نفسه يكفي
      ApiReportUpdate("SL_HIT", price, g_bot.beDone
                      ? "Stopped out at break-even."
                      : "Stop loss hit.");
     }
   else if(reason == DEAL_REASON_TP)
      ApiReportUpdate("TP3_HIT", price, "Final target reached.");
   else
      ApiReportUpdate(pl >= 0 ? "CLOSE_WIN" : "CLOSE_LOSS", price, "Position closed.");

   PrintFormat("%sClosed at %s, P/L %.2f (%s)", LOG_PREFIX, DoubleToString(price, _Digits), pl,
               reason == DEAL_REASON_SL ? "SL" : (reason == DEAL_REASON_TP ? "TP" : "other"));
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
   if(!IsKnownPlan(InpMinPlan))
     {
      PrintFormat("%sMinPlan must be one of FREE, SIGNALS, NORMAL, PRO, ULTRA.", LOG_PREFIX);
      return(false);
     }
   if(InpPublishSignals && !MQLInfoInteger(MQL_TESTER) && StringLen(InpIngestKey) == 0)
      PrintFormat("%sPublishing is on but the ingest key is empty — nothing will be posted.",
                  LOG_PREFIX);
   return(true);
  }

// نسخة من PLAN_CODES في packages/shared/src/domain.ts
bool IsKnownPlan(const string plan)
  {
   return(plan == "FREE" || plan == "SIGNALS" || plan == "NORMAL" ||
          plan == "PRO"  || plan == "ULTRA");
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
