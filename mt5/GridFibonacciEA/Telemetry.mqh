//+------------------------------------------------------------------+
//|                                                    Telemetry.mqh |
//|  Outbound channels: terminal alerts, push, Telegram, and the      |
//|  JSON snapshot the Python 3D dashboard consumes.                  |
//|                                                                   |
//|  Every network call here is blocking, so it is only ever reached  |
//|  from OnTimer — never from OnTick — and never from the tester.    |
//+------------------------------------------------------------------+
#ifndef GFEA_TELEMETRY_MQH
#define GFEA_TELEMETRY_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| True when outbound HTTP is possible at all.                      |
//+------------------------------------------------------------------+
bool NetworkAvailable(void)
  {
   if(MQLInfoInteger(MQL_TESTER))     return false;   // WebRequest is disabled in the tester
   if(MQLInfoInteger(MQL_OPTIMIZATION))return false;
   return(TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
  }

//+------------------------------------------------------------------+
//| Telegram — single GET, text is percent-encoded                   |
//+------------------------------------------------------------------+
bool TelegramSend(const string text)
  {
   if(!InpTelegramOn) return false;
   if(StringLen(InpTelegramToken) == 0 || StringLen(InpTelegramChatId) == 0) return false;
   if(!NetworkAvailable()) return false;

   string url = StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",
                             InpTelegramToken, InpTelegramChatId, UrlEncode(text));
   char   post[];
   char   result[];
   string hdrs;

   ResetLastError();
   int code = WebRequest("GET", url, "", TELEMETRY_TIMEOUT, post, result, hdrs);
   if(code == -1)
     {
      int err = GetLastError();
      if(err == 4014 || err == 5203)
         LogError("Telegram blocked - allow https://api.telegram.org in Tools > Options > Expert Advisors", err);
      else
         LogError("Telegram send failed", err);
      return false;
     }
   return(code == 200);
  }

//+------------------------------------------------------------------+
//| Notify — one funnel for every human-facing message               |
//| `important` messages also reach push and Telegram.               |
//+------------------------------------------------------------------+
void Notify(const string headline, const string detail, const bool important = false)
  {
   string msg = StringFormat("%s | %s | %s", GFEA_NAME, _Symbol, headline);
   if(StringLen(detail) > 0) msg += " | " + detail;

   g_ea.lastEvent = headline;
   LogInfo(msg);

   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;

   if(InpAlertsOn && important) Alert(msg);
   if(InpPushOn  && important)  SendNotification(msg);
   if(important)                TelegramSend(msg);
  }

//+------------------------------------------------------------------+
//| The grid ladder as a JSON array — this is what the dashboard     |
//| renders as the 3D level ladder.                                  |
//+------------------------------------------------------------------+
string BuildLevelsJson(void)
  {
   string items = "";
   for(int i = 0; i < g_grid.Total(); i++)
     {
      CGridLevel *gl = (CGridLevel*)g_grid.At(i);
      if(gl == NULL) continue;

      //--- live P/L of this level, taken from the broker where possible
      double pl = gl.closedPL;
      double cur = 0;
      if(!gl.closed && gl.ticket > 0 && PositionSelectByTicket(gl.ticket))
        {
         pl  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         cur = PositionGetDouble(POSITION_PRICE_CURRENT);
        }
      else if(!gl.closed)
        {
         //--- netting: levels share one position, so value the level itself
         cur = SymbolInfoDouble(_Symbol, g_ea.cycle.dir > 0 ? SYMBOL_BID : SYMBOL_ASK);
         pl  = MoneyForPriceDistance(gl.lots, (cur - gl.filled) * g_ea.cycle.dir);
        }

      string one = JObj(JInt("level", gl.level)              + "," +
                        JInt("ticket", (long)gl.ticket)      + "," +
                        JNum("requested", gl.requested, g_ea.digits) + "," +
                        JNum("filled", gl.filled, g_ea.digits)       + "," +
                        JNum("current", cur, g_ea.digits)            + "," +
                        JNum("lots", gl.lots, 2)                     + "," +
                        JNum("pl", pl, 2)                            + "," +
                        JInt("opened", (long)gl.opened)              + "," +
                        JBool("closed", gl.closed));
      items += (StringLen(items) > 0 ? "," : "") + one;
     }
   return JArr(items);
  }

//+------------------------------------------------------------------+
//| Full snapshot: account, regime, structure, cycle, grid, stats    |
//+------------------------------------------------------------------+
string BuildTelemetryJson(void)
  {
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPct   = (g_ea.guard.peakEquity > 0)
                    ? (g_ea.guard.peakEquity - equity) / g_ea.guard.peakEquity * 100.0 : 0;
   double dayPL   = equity - g_ea.guard.dayStartBalance;

   string account = JObj(JStr("company", AccountInfoString(ACCOUNT_COMPANY))   + "," +
                         JStr("currency", AccountInfoString(ACCOUNT_CURRENCY)) + "," +
                         JInt("login", AccountInfoInteger(ACCOUNT_LOGIN))      + "," +
                         JNum("balance", balance, 2)                           + "," +
                         JNum("equity", equity, 2)                             + "," +
                         JNum("margin", AccountInfoDouble(ACCOUNT_MARGIN), 2)  + "," +
                         JNum("free_margin", AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "," +
                         JNum("margin_level", AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + "," +
                         JBool("hedging", g_ea.hedging));

   string market  = JObj(JStr("symbol", _Symbol)                               + "," +
                         JStr("timeframe", EnumToString(SignalTF()))           + "," +
                         JNum("bid", SymbolInfoDouble(_Symbol, SYMBOL_BID), g_ea.digits) + "," +
                         JNum("ask", SymbolInfoDouble(_Symbol, SYMBOL_ASK), g_ea.digits) + "," +
                         JInt("spread_points", SpreadPoints())                 + "," +
                         JInt("digits", g_ea.digits));

   //--- contract spec: the dashboard needs it to turn price moves into money
   string spec    = JObj(JNum("point", g_ea.point, 8)                         + "," +
                         JNum("tick_size", g_ea.tickSize, 8)                  + "," +
                         JNum("tick_value", g_ea.tickValue, 5)                + "," +
                         JNum("volume_min", g_ea.volMin, 2)                   + "," +
                         JNum("volume_step", g_ea.volStep, 2)                 + "," +
                         JNum("volume_max", g_ea.volMax, 2)                   + "," +
                         JInt("max_levels", MathMin(InpGridMaxLevels, MAX_GRID_LEVELS)) + "," +
                         JNum("cycle_max_loss_pct", InpCycleMaxLossPct, 2)    + "," +
                         JNum("max_dd_pct", InpMaxTotalDDPct, 2)              + "," +
                         JNum("max_daily_loss_pct", InpMaxDailyLossPct, 2));

   string regime  = JObj(JStr("regime", RegimeText(g_ea.view.regime))          + "," +
                         JInt("bias", g_ea.view.bias)                          + "," +
                         JInt("stack_dir", g_ea.view.stackDir)                 + "," +
                         JInt("htf_dir", g_ea.view.htfDir)                     + "," +
                         JNum("ma_fast", g_ea.view.fast, g_ea.digits)          + "," +
                         JNum("ma_mid", g_ea.view.mid, g_ea.digits)            + "," +
                         JNum("ma_slow", g_ea.view.slow, g_ea.digits)          + "," +
                         JNum("ma_htf", g_ea.view.htf, g_ea.digits)            + "," +
                         JNum("slope_atr", g_ea.view.slopeAtr, 4)              + "," +
                         JNum("adx", g_ea.view.adx, 2)                         + "," +
                         JNum("di_plus", g_ea.view.diPlus, 2)                  + "," +
                         JNum("di_minus", g_ea.view.diMinus, 2)                + "," +
                         JNum("atr", g_ea.view.atr, g_ea.digits));

   string swing   = JObj(JBool("valid", g_ea.swing.valid)                      + "," +
                         JInt("dir", g_ea.swing.dir)                           + "," +
                         JNum("high", g_ea.swing.hi, g_ea.digits)              + "," +
                         JNum("low", g_ea.swing.lo, g_ea.digits)               + "," +
                         JNum("range", g_ea.swing.range, g_ea.digits)          + "," +
                         JInt("high_time", (long)g_ea.swing.hiTime)            + "," +
                         JInt("low_time", (long)g_ea.swing.loTime));

   string cycle   = JObj(JBool("active", g_ea.cycle.active)                    + "," +
                         JInt("dir", g_ea.cycle.dir)                           + "," +
                         JInt("levels", g_ea.cycle.levels)                     + "," +
                         JNum("avg_price", BasketAvgPrice(), g_ea.digits)      + "," +
                         JNum("volume", BasketVolume(), 2)                     + "," +
                         JNum("floating", BasketProfit(), 2)                   + "," +
                         JNum("realised", g_ea.cycle.realised, 2)              + "," +
                         JNum("next_price", g_ea.cycle.nextPrice, g_ea.digits) + "," +
                         JNum("stop_price", g_ea.cycle.stopPrice, g_ea.digits) + "," +
                         JNum("tp1", g_ea.cycle.tp1, g_ea.digits)              + "," +
                         JNum("tp2", g_ea.cycle.tp2, g_ea.digits)              + "," +
                         JNum("tp3", g_ea.cycle.tp3, g_ea.digits)              + "," +
                         JBool("tp1_done", g_ea.cycle.tp1Done)                 + "," +
                         JBool("tp2_done", g_ea.cycle.tp2Done)                 + "," +
                         JBool("be_done", g_ea.cycle.beDone)                   + "," +
                         JInt("started", (long)g_ea.cycle.started));

   string guard   = JObj(JBool("trading_enabled", g_ea.tradingEnabled)         + "," +
                         JBool("grid_enabled", g_ea.gridEnabled)               + "," +
                         JBool("halted", g_ea.guard.halted)                    + "," +
                         JBool("daily_target_hit", g_ea.guard.dailyTargetHit)  + "," +
                         JStr("halt_reason", g_ea.guard.haltReason)            + "," +
                         JNum("day_pl", dayPL, 2)                              + "," +
                         JNum("day_start_balance", g_ea.guard.dayStartBalance, 2) + "," +
                         JNum("peak_equity", g_ea.guard.peakEquity, 2)         + "," +
                         JNum("dd_pct", ddPct, 2));

   string stats   = JObj(JInt("cycles_total", g_ea.stats.cyclesTotal)          + "," +
                         JInt("cycles_won", g_ea.stats.cyclesWon)              + "," +
                         JNum("realised_total", g_ea.stats.realisedTotal, 2)   + "," +
                         JNum("best_cycle", g_ea.stats.bestCycle, 2)           + "," +
                         JNum("worst_cycle", g_ea.stats.worstCycle, 2)         + "," +
                         JNum("max_dd_pct", g_ea.stats.maxDDPct, 2)            + "," +
                         JInt("trades_sent", g_ea.stats.tradesSent)            + "," +
                         JInt("trades_failed", g_ea.stats.tradesFailed));

   return JObj(JStr("ea", GFEA_NAME)                    + "," +
               JStr("version", GFEA_VERSION)            + "," +
               JInt("magic", InpMagic)                  + "," +
               JInt("ts", (long)TimeCurrent())          + "," +
               JStr("last_event", g_ea.lastEvent)       + "," +
               "\"account\":" + account                 + "," +
               "\"market\":"  + market                  + "," +
               "\"spec\":"    + spec                    + "," +
               "\"regime\":"  + regime                  + "," +
               "\"swing\":"   + swing                   + "," +
               "\"cycle\":"   + cycle                   + "," +
               "\"guard\":"   + guard                   + "," +
               "\"stats\":"   + stats                   + "," +
               "\"levels\":"  + BuildLevelsJson());
  }

//+------------------------------------------------------------------+
//| Push one snapshot to the dashboard ingest endpoint.              |
//+------------------------------------------------------------------+
bool TelemetryPush(void)
  {
   if(!g_ea.telemetryOn)   return false;
   if(!NetworkAvailable()) return false;
   if(StringLen(InpTelemetryUrl) == 0) return false;

   string json = BuildTelemetryJson();
   string hdrs = "Content-Type: application/json\r\n";
   if(StringLen(InpTelemetryKey) > 0)
      hdrs += "X-Ingest-Key: " + InpTelemetryKey + "\r\n";

   char post[];
   //--- count = StringLen keeps the terminating NUL out of the body,
   //--- which strict JSON parsers reject.
   StringToCharArray(json, post, 0, StringLen(json), CP_UTF8);

   char   result[];
   string rhdrs;
   ResetLastError();
   int code = WebRequest("POST", InpTelemetryUrl, hdrs, TELEMETRY_TIMEOUT, post, result, rhdrs);

   if(code == -1)
     {
      int err = GetLastError();
      if(err == 4014 || err == 5203)
         LogError("Telemetry blocked - add the dashboard URL in Tools > Options > Expert Advisors", err);
      else
         LogError("Telemetry POST failed", err);
      return false;
     }
   if(code != 200 && code != 201 && code != 204)
     {
      LogError(StringFormat("Telemetry HTTP %d", code));
      return false;
     }
   return true;
  }

#endif // GFEA_TELEMETRY_MQH
//+------------------------------------------------------------------+
