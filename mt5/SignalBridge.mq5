//+------------------------------------------------------------------+
//|                                              SignalBridge.mq5     |
//|  Publishes trades opened on this MT5 terminal to the platform API |
//+------------------------------------------------------------------+
//
// Purpose
// -------
// Turns the trades you actually place into published signals, so the feed is
// driven by your terminal instead of by hand. It posts to the SAME endpoint
// contract the admin composer uses (`signalInputSchema`), which is why adding
// this feed needs no change on the server.
//
// Setup
// -----
//  1. In MetaTrader 5: Tools > Options > Expert Advisors > "Allow WebRequest
//     for listed URL", and add your API's base URL. Without this every
//     WebRequest returns -1 with error 4014.
//  2. Create an ingest key in the admin panel (Settings > MT5 bridge) and paste
//     it into InpIngestKey below. Keys are stored hashed and can be revoked on
//     their own, so a compromised VPS never exposes user accounts.
//  3. Attach to any one chart. The EA watches the whole terminal, not the chart
//     it sits on, so one instance is enough.
//
// Note this EA only *reports*. It never opens, modifies or closes a position.
//
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property strict

#include <Trade\PositionInfo.mqh>

input string InpApiBaseUrl   = "https://api.example.com/api"; // API base URL
input string InpIngestKey    = "";                            // X-Ingest-Key
input string InpMinPlan      = "SIGNALS";                     // Tier that sees these
input string InpTimeframe    = "H1";                          // Label on the signal
input bool   InpPublishNow   = true;                          // Publish immediately
input bool   InpReportUpdates= true;                          // Report BE/TP/SL moves
input int    InpPollSeconds  = 5;                             // Position poll interval

CPositionInfo  m_position;

// Positions already reported, so a restart does not republish open trades.
ulong  g_seen_tickets[];
double g_seen_sl[];
bool   g_seen_be[];

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringLen(InpIngestKey) == 0)
     {
      Print("SignalBridge: InpIngestKey is empty. Create one in the admin panel.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   ArrayResize(g_seen_tickets, 0);
   ArrayResize(g_seen_sl, 0);
   ArrayResize(g_seen_be, 0);

   // Adopt whatever is already open without republishing it: on attach we only
   // want to report trades opened from here on.
   AdoptExistingPositions();

   EventSetTimer(MathMax(1, InpPollSeconds));
   Print("SignalBridge: watching ", PositionsTotal(), " existing position(s).");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { EventKillTimer(); }

//+------------------------------------------------------------------+
//| Poll for new positions and for stop moves on known ones.         |
//+------------------------------------------------------------------+
void OnTimer()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !m_position.SelectByTicket(ticket))
         continue;

      int idx = FindTicket(ticket);
      if(idx < 0)
        {
         PublishSignal(ticket);
         continue;
        }

      if(!InpReportUpdates)
         continue;

      // A stop pulled to (or past) the entry price is the break-even move. It
      // is worth detecting because it changes how a later stop-out is scored:
      // a stop-out at break-even is a scratch, not a loss.
      double entry = m_position.PriceOpen();
      double sl    = m_position.StopLoss();

      if(!g_seen_be[idx] && sl > 0 && IsAtBreakEven(m_position.PositionType(), entry, sl))
        {
         ReportUpdate(m_position.Symbol(), "MOVED_TO_BE", 0.0, "Stop moved to break-even.");
         g_seen_be[idx] = true;
        }

      g_seen_sl[idx] = sl;
     }

   PruneClosedPositions();
  }

//+------------------------------------------------------------------+
bool IsAtBreakEven(const ENUM_POSITION_TYPE type, const double entry, const double sl)
  {
   // Allow a small tolerance: brokers and manual moves rarely land exactly.
   double tolerance = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20;
   if(type == POSITION_TYPE_BUY)
      return(sl >= entry - tolerance);
   return(sl <= entry + tolerance);
  }

//+------------------------------------------------------------------+
//| POST a newly opened position as a signal.                        |
//+------------------------------------------------------------------+
void PublishSignal(const ulong ticket)
  {
   if(!m_position.SelectByTicket(ticket))
      return;

   string symbol = m_position.Symbol();
   double entry  = m_position.PriceOpen();
   double sl     = m_position.StopLoss();
   double tp     = m_position.TakeProfit();

   // The API requires a stop and at least one target; a position without them
   // is not a publishable signal.
   if(sl <= 0 || tp <= 0)
     {
      Print("SignalBridge: skipping ", symbol, " #", ticket, " (needs both SL and TP)");
      return;
     }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string dir = (m_position.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   string body = StringFormat(
      "{\"symbol\":\"%s\",\"direction\":\"%s\",\"orderType\":\"MARKET\","
      "\"entryLow\":%s,\"entryHigh\":%s,\"sl\":%s,\"tp1\":%s,"
      "\"timeframe\":\"%s\",\"minPlan\":\"%s\",\"publishNow\":%s,"
      "\"analysisText\":\"Published automatically from MetaTrader 5.\"}",
      symbol, dir,
      DoubleToString(entry, digits), DoubleToString(entry, digits),
      DoubleToString(sl, digits), DoubleToString(tp, digits),
      InpTimeframe, InpMinPlan,
      InpPublishNow ? "true" : "false");

   if(PostJson("/ingest/signals", body))
     {
      RememberTicket(ticket, sl);
      Print("SignalBridge: published ", dir, " ", symbol, " #", ticket);
     }
  }

//+------------------------------------------------------------------+
void ReportUpdate(const string symbol, const string type, const double price, const string note)
  {
   string priceField = (price > 0)
      ? StringFormat(",\"price\":%s", DoubleToString(price, 5))
      : "";

   string body = StringFormat(
      "{\"symbol\":\"%s\",\"type\":\"%s\",\"note\":\"%s\"%s}",
      symbol, type, note, priceField);

   if(PostJson("/ingest/signals/updates", body))
      Print("SignalBridge: reported ", type, " on ", symbol);
  }

//+------------------------------------------------------------------+
//| Shared WebRequest wrapper.                                       |
//+------------------------------------------------------------------+
bool PostJson(const string path, const string body)
  {
   string url     = InpApiBaseUrl + path;
   string headers = "Content-Type: application/json\r\nX-Ingest-Key: " + InpIngestKey + "\r\n";

   char post[], result[];
   string resultHeaders;

   StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   ArrayResize(post, StringLen(body)); // drop the trailing null StringToCharArray adds

   ResetLastError();
   int status = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);

   if(status == -1)
     {
      int err = GetLastError();
      if(err == 4014)
         Print("SignalBridge: ", url, " is not in the allowed WebRequest list ",
               "(Tools > Options > Expert Advisors).");
      else
         Print("SignalBridge: WebRequest failed, error ", err);
      return(false);
     }

   if(status < 200 || status >= 300)
     {
      Print("SignalBridge: API returned HTTP ", status, " — ", CharArrayToString(result));
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Ticket bookkeeping.                                              |
//+------------------------------------------------------------------+
int FindTicket(const ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_seen_tickets); i++)
      if(g_seen_tickets[i] == ticket)
         return(i);
   return(-1);
  }

void RememberTicket(const ulong ticket, const double sl)
  {
   int n = ArraySize(g_seen_tickets);
   ArrayResize(g_seen_tickets, n + 1);
   ArrayResize(g_seen_sl, n + 1);
   ArrayResize(g_seen_be, n + 1);
   g_seen_tickets[n] = ticket;
   g_seen_sl[n]      = sl;
   g_seen_be[n]      = false;
  }

void AdoptExistingPositions()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && m_position.SelectByTicket(ticket))
         RememberTicket(ticket, m_position.StopLoss());
     }
  }

// Drop tickets that are no longer open so the arrays do not grow without bound.
void PruneClosedPositions()
  {
   ulong  keptTickets[];
   double keptSl[];
   bool   keptBe[];

   for(int i = 0; i < ArraySize(g_seen_tickets); i++)
     {
      if(!PositionSelectByTicket(g_seen_tickets[i]))
         continue;

      int n = ArraySize(keptTickets);
      ArrayResize(keptTickets, n + 1);
      ArrayResize(keptSl, n + 1);
      ArrayResize(keptBe, n + 1);
      keptTickets[n] = g_seen_tickets[i];
      keptSl[n]      = g_seen_sl[i];
      keptBe[n]      = g_seen_be[i];
     }

   ArrayCopy(g_seen_tickets, keptTickets);
   ArrayCopy(g_seen_sl, keptSl);
   ArrayCopy(g_seen_be, keptBe);
   ArrayResize(g_seen_tickets, ArraySize(keptTickets));
   ArrayResize(g_seen_sl, ArraySize(keptSl));
   ArrayResize(g_seen_be, ArraySize(keptBe));
  }
//+------------------------------------------------------------------+
