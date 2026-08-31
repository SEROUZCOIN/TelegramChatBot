//+------------------------------------------------------------------+
//|                                                          Api.mqh |
//|  Platform integration. Posts the SAME `signalInputSchema` the    |
//|  admin composer and SignalBridge.mq5 post, so this bot is one    |
//|  more caller of an existing contract, not a second definition    |
//|  of what a signal is.                                            |
//|                                                                  |
//|  WebRequest BLOCKS, so nothing here is ever called from OnTick:  |
//|  requests are queued and drained one per OnTimer cycle. The      |
//|  whole module no-ops in the Strategy Tester, which is what lets  |
//|  the strategy be backtested unchanged.                           |
//+------------------------------------------------------------------+
#ifndef FIBBOT_API_MQH
#define FIBBOT_API_MQH

#include "Config.mqh"
#include "Fib.mqh"
#include "Util.mqh"

struct SApiJob
  {
   string path;
   string body;
   int    attempts;
  };

SApiJob g_apiQueue[];

//--- gating --------------------------------------------------------

bool ApiEnabled()
  {
   if(!InpPublishSignals)
      return(false);
   if(MQLInfoInteger(MQL_TESTER))     // WebRequest معطّل في الاختبار أصلاً
      return(false);
   if(StringLen(InpIngestKey) == 0 || StringLen(InpApiBaseUrl) == 0)
      return(false);
   return(true);
  }

//--- queue ---------------------------------------------------------

void ApiQueue(const string path, const string body)
  {
   if(!ApiEnabled())
      return;

   int n = ArraySize(g_apiQueue);
   if(n >= API_QUEUE_MAX)
     {
      // أسقط الأقدم بدل أن ينمو الطابور بلا حد
      for(int i = 0; i < n - 1; i++)
         g_apiQueue[i] = g_apiQueue[i + 1];
      n--;
      ArrayResize(g_apiQueue, n);
     }

   ArrayResize(g_apiQueue, n + 1);
   g_apiQueue[n].path     = path;
   g_apiQueue[n].body     = body;
   g_apiQueue[n].attempts = 0;
  }

void ApiQueuePopFront()
  {
   int n = ArraySize(g_apiQueue);
   if(n <= 0)
      return;
   for(int i = 0; i < n - 1; i++)
      g_apiQueue[i] = g_apiQueue[i + 1];
   ArrayResize(g_apiQueue, n - 1);
  }

//--- transport -----------------------------------------------------

bool ApiPost(const string path, const string body)
  {
   string url     = InpApiBaseUrl + path;
   string headers = "Content-Type: application/json\r\nX-Ingest-Key: " + InpIngestKey + "\r\n";

   char post[], result[];
   string resultHeaders;

   // العدد المعاد يشمل المحرف الصفري الختامي — أسقطه وإلا رفض الخادم الجسم
   int copied = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(copied < 1)
      return(false);
   ArrayResize(post, copied - 1);

   ResetLastError();
   int status = WebRequest("POST", url, headers, HTTP_TIMEOUT, post, result, resultHeaders);

   if(status == -1)
     {
      int err = GetLastError();
      if(err == 4014 || err == 5203)
         PrintFormat("%s%s is not in the allowed WebRequest list "
                     "(Tools > Options > Expert Advisors).", LOG_PREFIX, url);
      else
         PrintFormat("%sWebRequest failed, error %d", LOG_PREFIX, err);
      return(false);
     }

   if(status < 200 || status >= 300)
     {
      PrintFormat("%sAPI returned HTTP %d — %s", LOG_PREFIX, status,
                  CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8));
      // 4xx = طلب مرفوض بذاته: إعادة إرساله ستُرفض مثله، فاعتبره منتهياً وأسقطه
      // 5xx = عطل مؤقت في الخادم: يستحق إعادة المحاولة
      if(status >= 400 && status < 500)
         return(true);
      return(false);
     }

   return(true);
  }

// طلب واحد لكل دورة مؤقّت: WebRequest حاجب فلا يُستدعى مرتين في نبضة
void ApiFlush()
  {
   if(!ApiEnabled() || ArraySize(g_apiQueue) == 0)
      return;

   if(ApiPost(g_apiQueue[0].path, g_apiQueue[0].body))
     {
      ApiQueuePopFront();
      return;
     }

   g_apiQueue[0].attempts++;
   if(g_apiQueue[0].attempts >= API_RETRY_MAX)
     {
      PrintFormat("%sDropping %s after %d attempts.", LOG_PREFIX,
                  g_apiQueue[0].path, g_apiQueue[0].attempts);
      ApiQueuePopFront();
     }
  }

//--- payloads ------------------------------------------------------

// نطاق الدخول هو منطقة فيبوناتشي نفسها — لهذا يحمل العقد entryLow و entryHigh
void ApiPublishSetup(const bool asMarketFill, const double fillPrice)
  {
   if(!ApiEnabled() || g_setup.state == SETUP_IDLE)
      return;

   double entryLow, entryHigh;
   string orderType;

   if(asMarketFill && fillPrice > 0)
     {
      entryLow  = fillPrice;
      entryHigh = fillPrice;
      orderType = "MARKET";
     }
   else
     {
      entryLow  = MathMin(g_setup.zoneNear, g_setup.zoneFar);
      entryHigh = MathMax(g_setup.zoneNear, g_setup.zoneFar);
      orderType = "LIMIT";
     }

   string body = JsonObj(
      JsonStr("symbol", _Symbol) + "," +
      JsonStr("direction", g_setup.dir > 0 ? "BUY" : "SELL") + "," +
      JsonStr("orderType", orderType) + "," +
      JsonNum("entryLow", entryLow, _Digits) + "," +
      JsonNum("entryHigh", entryHigh, _Digits) + "," +
      JsonNum("sl", g_setup.stop, _Digits) + "," +
      JsonNum("tp1", g_setup.tp1, _Digits) + "," +
      JsonNum("tp2", g_setup.tp2, _Digits) + "," +
      JsonNum("tp3", g_setup.tp3, _Digits) + "," +
      JsonNum("beTrigger", g_setup.tp1, _Digits) + "," +
      JsonStr("timeframe", TimeframeName((ENUM_TIMEFRAMES)_Period)) + "," +
      JsonNum("riskPercent", InpRiskPercent, 2) + "," +
      JsonStr("minPlan", InpMinPlan) + "," +
      JsonBool("publishNow", InpPublishNow) + "," +
      JsonStr("analysisText", SetupAnalysisText()));

   ApiQueue("/ingest/signals", body);
   g_setup.published = true;
  }

void ApiReportUpdate(const string updateType, const double price, const string note)
  {
   if(!ApiEnabled() || !InpReportUpdates)
      return;

   string body = JsonStr("symbol", _Symbol) + "," +
                 JsonStr("type", updateType) + "," +
                 JsonStr("note", note);
   if(price > 0)
      body += "," + JsonNum("price", price, _Digits);

   ApiQueue("/ingest/signals/updates", JsonObj(body));
  }

#endif // FIBBOT_API_MQH
//+------------------------------------------------------------------+
