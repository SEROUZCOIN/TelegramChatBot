//+------------------------------------------------------------------+
//|                                             GridFibonacciEA.mq5  |
//|                                    Grid Fibonacci Pro — MT5 EA    |
//+------------------------------------------------------------------+
//
// WHAT THIS EA DOES
// -----------------
// It trades one thing: a pullback into the Fibonacci retracement of a
// confirmed impulse leg, in a market whose regime says that pullback is
// worth buying. The grid exists to improve the average entry inside that
// same structure — never to average into an idea the market already
// invalidated.
//
//   1. REGIME   Triple MA stack + ATR-normalised slope + higher-timeframe
//               agreement + ADX classify the market as trend, range or chop.
//               Chop opens nothing.
//   2. STRUCTURE A confirmed pivot and the opposing extreme define the
//               impulse leg. Legs smaller than N x ATR are rejected.
//   3. ENTRY    Price must trade into the 0.382-0.786 retracement window
//               and confirm (MA reclaim and/or rejection wick).
//   4. GRID     Further levels are added on the Fibonacci ladder of that
//               same leg, or at ATR distances widened by the Fibonacci
//               sequence, one fill per bar, and NEVER past the structural
//               invalidation.
//   5. EXIT     Partial closes at the 1.272 and 1.618 extensions, the
//               remainder to 2.618, with a basket money target, break-even
//               on the basket average, and ATR or fib-step trailing.
//   6. SURVIVAL Cycle loss ceiling, daily loss and profit limits, total
//               drawdown limit, equity floor, spread and session filters.
//
// INSTALL
// -------
//   1. Copy the whole GridFibonacciEA folder into MQL5\Experts\.
//   2. Open GridFibonacciEA.mq5 in MetaEditor and press F7.
//   3. Attach to one chart. The EA trades that chart's symbol only.
//   4. For Telegram or the Python dashboard: Tools > Options > Expert
//      Advisors > "Allow WebRequest for listed URL" and add
//      https://api.telegram.org and your dashboard's URL.
//
// ACCOUNT MODES
// -------------
// Works on hedging and netting accounts. On netting the ladder shares one
// aggregate position; the basket average the server maintains is the same
// number this EA computes, so the management logic is identical.
//
#property copyright "Grid Fibonacci Pro"
#property link      ""
#property version   "1.00"
#property description "Fibonacci grid EA with an advanced MA regime filter,"
#property description "structural stops, extension targets and a neon dashboard."

#include "Panel.mqh"

//+------------------------------------------------------------------+
//| Input validation — fail loudly in OnInit, never mid-session.     |
//+------------------------------------------------------------------+
bool ValidateInputs(string &problem)
  {
   if(InpMaFast >= InpMaMid || InpMaMid >= InpMaSlow)
     { problem = "MA periods must satisfy fast < mid < slow"; return false; }

   if(InpEntryFibMin <= 0 || InpEntryFibMax <= InpEntryFibMin || InpEntryFibMax > 1.0)
     { problem = "Entry fib window must satisfy 0 < min < max <= 1.0"; return false; }

   if(InpSlFibLevel < InpEntryFibMax)
     { problem = "Structural stop level must sit beyond the entry window"; return false; }

   if(InpTp1Fib <= 1.0 || InpTp2Fib <= InpTp1Fib || InpTp3Fib <= InpTp2Fib)
     { problem = "Extension targets must satisfy 1.0 < TP1 < TP2 < TP3"; return false; }

   if(InpTp1ClosePct + InpTp2ClosePct >= 100.0)
     { problem = "TP1 + TP2 close percentages must leave a runner (< 100%)"; return false; }

   if(InpGridMaxLevels < 1 || InpGridMaxLevels > MAX_GRID_LEVELS)
     { problem = StringFormat("Grid levels must be 1..%d", MAX_GRID_LEVELS); return false; }

   if(InpLotProgression == PROG_GEOMETRIC && InpLotFactor <= 1.0)
     { problem = "Geometric progression needs a factor above 1.0"; return false; }

   if(InpLotMode == LOT_FIXED && InpFixedLot <= 0)
     { problem = "Fixed lot must be positive"; return false; }

   if(InpRiskPercent <= 0 || InpRiskPercent > 10)
     { problem = "Risk percent must be within 0..10"; return false; }

   if(InpMaxTotalRiskPct < InpRiskPercent)
     { problem = "Total risk budget cannot be smaller than the per-entry risk"; return false; }

   if(InpAtrPeriod < 2 || InpAdxPeriod < 2)
     { problem = "ATR and ADX periods must be at least 2"; return false; }

   if(InpPivotStrength < 1 || InpSwingLookback < InpPivotStrength * 6)
     { problem = "Swing lookback must be at least 6x the pivot strength"; return false; }

   return true;
  }

//+------------------------------------------------------------------+
//| Seed the runtime state from the inputs. After this point the EA  |
//| reads STATE, never the inputs, for anything switchable.          |
//+------------------------------------------------------------------+
void SeedStateFromConfig(void)
  {
   g_ea.tradingEnabled = InpEnableTrading;
   g_ea.gridEnabled    = InpGridEnable;
   g_ea.panelVisible   = InpShowPanel && !MQLInfoInteger(MQL_OPTIMIZATION);
   g_ea.telemetryOn    = InpTelemetryOn;

   g_ea.hMaFast = INVALID_HANDLE;
   g_ea.hMaMid  = INVALID_HANDLE;
   g_ea.hMaSlow = INVALID_HANDLE;
   g_ea.hMaHtf  = INVALID_HANDLE;
   g_ea.hAdx    = INVALID_HANDLE;
   g_ea.hAtr    = INVALID_HANDLE;

   g_ea.lastBar       = 0;
   g_ea.lastTelemetry = 0;
   g_ea.lastPanelTick = 0;
   g_ea.ledPhase      = 0;
   g_ea.chartW        = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_ea.lastEvent     = "initialising";

   ZeroMemory(g_ea.swing);
   ZeroMemory(g_ea.view);
   ZeroMemory(g_ea.stats);
   CycleReset();
   g_ea.cycle.closedAt = 0;
  }

//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   string problem = "";
   if(!ValidateInputs(problem))
     {
      PrintFormat("[%s] Invalid configuration: %s", LOG_TAG, problem);
      return INIT_PARAMETERS_INCORRECT;
     }

   SeedStateFromConfig();

   if(!CacheSymbolSpec())
     {
      PrintFormat("[%s] %s: incomplete symbol specification from the broker",
                  LOG_TAG, _Symbol);
      return INIT_FAILED;
     }

   ExecutionInit();

   if(!InitIndicators())
      return INIT_FAILED;

   //--- the strategy needs enough history to find a leg at all
   int need = MathMax(InpSwingLookback, InpMaSlow) + InpPivotStrength + 10;
   if(Bars(_Symbol, SignalTF()) < need)
      PrintFormat("[%s] Warning: only %d bars available, %d wanted. "
                  "The first cycle will wait for history.",
                  LOG_TAG, Bars(_Symbol, SignalTF()), need);

   GuardInit();
   RefreshMarketView(g_ea.view);      // may legitimately fail while history loads
   AdoptExistingBasket();

   PanelBuild();
   PanelUpdate();

   EventSetTimer(1);

   LogInfo(StringFormat("%s v%s ready | %s | %s | magic %I64d | %s account",
                        GFEA_NAME, GFEA_VERSION, _Symbol,
                        EnumToString(SignalTF()), InpMagic,
                        g_ea.hedging ? "hedging" : "netting"));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   if(InpCloseOnDeinit && reason != REASON_CHARTCHANGE && reason != REASON_PARAMETERS)
      CloseAllMine("EA removed");

   ReleaseIndicators();
   PanelDestroy();
   GridClear();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1. Protection first. This may close everything and halt the EA.
   bool mayOpen = GuardAllowsTrading();

   //--- 2. Whatever is open is always managed, halted or not.
   if(g_ea.cycle.active)
      ManageCycle();

   if(!mayOpen) return;

   //--- 3. Signal work happens once per closed bar.
   if(!IsNewSignalBar()) return;

   if(!RefreshMarketView(g_ea.view)) return;

   SSwing found;
   ZeroMemory(found);
   if(DetectSwing(found)) g_ea.swing = found;
   else                   g_ea.swing.valid = false;

   if(CanOpenNewCycle() && g_ea.swing.valid)
     {
      int sig = EntrySignal(g_ea.swing, g_ea.view);
      if(sig != 0)
         OpenCycle(sig, g_ea.swing);
     }

   //--- 4. Redraw the market layer once per bar, not per tick.
   DrawStructure();
   DrawGridLevels();
  }

//+------------------------------------------------------------------+
//| One-second heartbeat: UI refresh and the blocking network calls. |
//+------------------------------------------------------------------+
void OnTimer()
  {
   PanelUpdate();

   if(!g_ea.telemetryOn) return;

   //--- GetTickCount64 is monotonic; TimeCurrent stalls when ticks stop,
   //--- which would freeze telemetry exactly when a market goes quiet.
   static ulong lastPush = 0;
   ulong now = GetTickCount64();
   ulong gap = (ulong)MathMax(1, InpTelemetrySeconds) * 1000;
   if(lastPush != 0 && now - lastPush < gap) return;

   lastPush = now;
   TelemetryPush();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(PanelHandleClick(sparam))
         ChartRedraw();
      return;
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      //--- a right-docked HUD follows the chart width; the structure
      //--- drawing is re-extended to the new right edge either way
      PanelRelayout();
      DrawStructure();
      DrawGridLevels();
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| Reliable close detection.                                        |
//|                                                                   |
//| Exit deals produced by the SERVER (stop loss, take profit, stop   |
//| out) can carry magic 0 with some brokers, so the position id is   |
//| matched against the tickets this EA recorded rather than trusting |
//| the magic on the way out.                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long  entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
      return;

   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   long  magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

   CGridLevel *gl = GridFind(posId);
   if(gl == NULL && magic != InpMagic) return;      // not ours

   double pl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
             + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
             + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   g_ea.cycle.realised += pl;

   if(gl != NULL && !PositionSelectByTicket(gl.ticket))
     {
      gl.closed   = true;
      gl.closedPL = pl;
     }

   long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string why  = (reason == DEAL_REASON_SL) ? "stop loss"
               : (reason == DEAL_REASON_TP) ? "take profit"
               : (reason == DEAL_REASON_SO) ? "stop out" : "closed";

   LogInfo(StringFormat("Level exit (%s) P/L %s | cycle realised %s",
                        why, FmtMoney(pl), FmtMoney(g_ea.cycle.realised)));

   //--- A server-side stop out ends the cycle: nothing of ours is left.
   if(g_ea.cycle.active && CountMyPositions() == 0)
      FinishCycle(why);
  }

//+------------------------------------------------------------------+
//| Optimisation criterion.                                          |
//|                                                                   |
//| A grid system optimised on net profit alone always converges on   |
//| the deepest, most fragile ladder. This scores profit against BOTH |
//| relative drawdown and the recovery factor, and refuses passes     |
//| with too few cycles to mean anything.                             |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 40) return 0;

   double profit = TesterStatistics(STAT_PROFIT);
   if(profit <= 0) return 0;

   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = MathMax(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 1.0);
   double rf = TesterStatistics(STAT_RECOVERY_FACTOR);

   //--- reward consistency, punish depth of drawdown quadratically
   return (profit * MathMin(pf, 5.0) * MathMax(rf, 0.1)) / (dd * dd);
  }
//+------------------------------------------------------------------+
