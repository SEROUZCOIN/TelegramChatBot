//+------------------------------------------------------------------+
//|                                                        Panel.mqh |
//|  UI layer. Two jobs, kept apart:                                  |
//|    * a pixel-anchored neon HUD (panel, rows, buttons)             |
//|    * price-anchored structure drawing (fib ladder, zone, grid)    |
//|                                                                   |
//|  Every colour comes from THEME and every dimension from METRICS   |
//|  in Config.mqh — there is no raw literal below.                   |
//+------------------------------------------------------------------+
#ifndef GFEA_PANEL_MQH
#define GFEA_PANEL_MQH

#include "Grid.mqh"

//--- Object ids. Kept as constants so update calls cannot typo a name.
#define ID_BG        "bg"
#define ID_HEAD      "head"
#define ID_TITLE     "title"
#define ID_SUB       "sub"
#define ID_LED       "led"
#define ID_BTN_TRADE "btnTrade"
#define ID_BTN_GRID  "btnGrid"
#define ID_BTN_CLOSE "btnClose"
#define ID_BTN_PANIC "btnPanic"

//--- Draw-layer ids
#define ID_DRAW_ZONE "zone"
#define ID_DRAW_LEG  "leg"

//+------------------------------------------------------------------+
//| Instance-unique prefix: two charts running this EA must not       |
//| fight over object names, and cleanup must remove only ours.       |
//+------------------------------------------------------------------+
string UiPfx(void)
  {
   static string p = "";
   if(StringLen(p) == 0)
      p = StringFormat("GFEA_%I64d_%I64d_", (long)InpMagic, (long)ChartID());
   return p;
  }

//--- DPI scaling applied once per dimension, at creation time.
int Dpi(const int base)
  {
   static int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi <= 0) return base;
   return base * dpi / 96;
  }

int PanelOriginX(void)
  {
   int pad = Dpi(InpPanelX);
   if(!InpPanelRight) return pad;

   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int x = chartW - Dpi(UI_PANEL_W) - pad;
   return MathMax(pad, x);
  }

//+------------------------------------------------------------------+
//| PIXEL FACTORIES — create once, update many                       |
//+------------------------------------------------------------------+
bool UiCreate(const string id, const ENUM_OBJECT type, string &outName)
  {
   outName = UiPfx() + id;
   if(ObjectFind(0, outName) >= 0) return true;
   if(!ObjectCreate(0, outName, type, 0, 0, 0)) return false;
   //--- always anchored to the upper-left corner. Right-hand docking is done
   //--- by computing the x origin from the live chart width (PanelOriginX),
   //--- which keeps one coordinate convention instead of two mirrored ones.
   ObjectSetInteger(0, outName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, outName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, outName, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, outName, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, outName, OBJPROP_BACK,       false);
   return true;
  }

bool UiPanelBox(const string id, const int x, const int y, const int w, const int h,
                const color bg, const color border, const int z = 0)
  {
   string n;
   if(!UiCreate(id, OBJ_RECTANGLE_LABEL, n)) return false;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      z);
   return true;
  }

bool UiLabel(const string id, const int x, const int y, const string text,
             const color clr, const int fs, const string font,
             const ENUM_ANCHOR_POINT anchor)
  {
   string n;
   if(!UiCreate(id, OBJ_LABEL, n)) return false;
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  fs);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,    20);
   ObjectSetString (0, n, OBJPROP_FONT,      font);
   ObjectSetString (0, n, OBJPROP_TEXT,      text);
   return true;
  }

bool UiButton(const string id, const int x, const int y, const int w, const int h,
              const string text, const color bg, const color fg)
  {
   string n;
   if(!UiCreate(id, OBJ_BUTTON, n)) return false;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, THEME_BORDER);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     UI_FS);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       30);
   ObjectSetInteger(0, n, OBJPROP_STATE,        false);
   ObjectSetString (0, n, OBJPROP_FONT,         UI_FONT);
   ObjectSetString (0, n, OBJPROP_TEXT,         text);
   return true;
  }

void UiText(const string id, const string text, const color clr = clrNONE)
  {
   string n = UiPfx() + id;
   if(ObjectFind(0, n) < 0) return;
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   if(clr != clrNONE) ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
  }

void UiBtnStyle(const string id, const string text, const color bg, const color fg)
  {
   string n = UiPfx() + id;
   if(ObjectFind(0, n) < 0) return;
   ObjectSetString (0, n, OBJPROP_TEXT,    text);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,   fg);
   ObjectSetInteger(0, n, OBJPROP_STATE,   false);   // buttons must never stick
  }

//+------------------------------------------------------------------+
//| LAYOUT — a running cursor, so no row hard-codes its own y         |
//+------------------------------------------------------------------+
int g_uiY = 0;   // layout cursor, only used while building

void UiSection(const string id, const string caption)
  {
   int x = PanelOriginX();
   UiPanelBox("sec_" + id, x, g_uiY, Dpi(UI_PANEL_W), Dpi(UI_SEC_H),
              THEME_BG_HEAD, THEME_BORDER, 5);
   UiLabel("secl_" + id, x + Dpi(UI_PAD), g_uiY + Dpi(UI_SEC_H) / 2, caption,
           THEME_GOLD, UI_FS, UI_FONT_TITLE, ANCHOR_LEFT);
   g_uiY += Dpi(UI_SEC_H) + Dpi(2);
  }

void UiRow(const string id, const string caption)
  {
   int x = PanelOriginX();
   int w = Dpi(UI_PANEL_W);
   UiLabel("k_" + id, x + Dpi(UI_PAD), g_uiY + Dpi(UI_ROW_H) / 2, caption,
           THEME_TEXT_DIM, UI_FS, UI_FONT, ANCHOR_LEFT);
   UiLabel("v_" + id, x + w - Dpi(UI_PAD), g_uiY + Dpi(UI_ROW_H) / 2, "-",
           THEME_TEXT, UI_FS, UI_FONT, ANCHOR_RIGHT);
   g_uiY += Dpi(UI_ROW_H);
  }

void UiValue(const string id, const string text, const color clr = clrNONE)
  {
   UiText("v_" + id, text, clr);
  }

//+------------------------------------------------------------------+
//| Build the HUD once.                                              |
//+------------------------------------------------------------------+
void PanelBuild(void)
  {
   if(!g_ea.panelVisible) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;   // chart services are no-ops there

   int x = PanelOriginX();
   int w = Dpi(UI_PANEL_W);

   //--- background first: creation order decides what paints underneath
   int totalH = Dpi(UI_HEAD_H) + Dpi(UI_SEC_H) * 5 + Dpi(UI_ROW_H) * 21
              + Dpi(UI_BTN_H) * 2 + Dpi(UI_PAD) * 4;
   UiPanelBox(ID_BG, x, Dpi(InpPanelY), w, totalH, THEME_BG, THEME_NEON_DIM, 0);

   g_uiY = Dpi(InpPanelY);

   //--- header
   UiPanelBox(ID_HEAD, x, g_uiY, w, Dpi(UI_HEAD_H), THEME_BG_HEAD, THEME_NEON, 1);
   UiLabel(ID_TITLE, x + Dpi(UI_PAD) + Dpi(UI_LED) + Dpi(6), g_uiY + Dpi(UI_HEAD_H) / 2 - Dpi(5),
           GFEA_NAME, THEME_NEON, UI_FS_TITLE, UI_FONT_TITLE, ANCHOR_LEFT);
   UiLabel(ID_SUB, x + Dpi(UI_PAD) + Dpi(UI_LED) + Dpi(6), g_uiY + Dpi(UI_HEAD_H) / 2 + Dpi(7),
           StringFormat("v%s  %s", GFEA_VERSION, _Symbol),
           THEME_TEXT_DIM, UI_FS, UI_FONT, ANCHOR_LEFT);
   UiPanelBox(ID_LED, x + Dpi(UI_PAD), g_uiY + Dpi(UI_HEAD_H) / 2 - Dpi(UI_LED) / 2,
              Dpi(UI_LED), Dpi(UI_LED), THEME_BUY, THEME_BUY, 10);
   UiLabel("clock", x + w - Dpi(UI_PAD), g_uiY + Dpi(UI_HEAD_H) / 2,
           "--:--:--", THEME_GOLD, UI_FS, UI_FONT, ANCHOR_RIGHT);
   g_uiY += Dpi(UI_HEAD_H) + Dpi(UI_PAD);

   //--- sections
   UiSection("mkt", "MARKET  /  REGIME");
   UiRow("regime",  "Regime");
   UiRow("bias",    "MA bias / stack");
   UiRow("adx",     "ADX  +DI / -DI");
   UiRow("slope",   "Slope (ATR)");
   UiRow("atr",     "ATR / Spread");

   UiSection("fib", "FIBONACCI STRUCTURE");
   UiRow("leg",     "Leg");
   UiRow("legpx",   "High / Low");
   UiRow("retr",    "Retracement");
   UiRow("zone",    "Entry zone");
   UiRow("tps",     "TP 1.272 / 1.618");

   UiSection("cyc", "GRID CYCLE");
   UiRow("cdir",    "Direction / levels");
   UiRow("cavg",    "Avg price / lots");
   UiRow("cfloat",  "Floating / realised");
   UiRow("cnext",   "Next grid level");
   UiRow("cstop",   "Basket stop");
   UiRow("ctp",     "Final target");

   UiSection("acc", "ACCOUNT");
   UiRow("aeq",     "Equity / balance");
   UiRow("aday",    "Day P/L");
   UiRow("add",     "Drawdown / peak");
   UiRow("amargin", "Margin level");

   UiSection("sts", "PERFORMANCE");
   UiRow("scyc",    "Cycles / win rate");
   UiRow("spl",     "Realised total");
   UiRow("sevent",  "Last event");

   //--- controls
   g_uiY += Dpi(UI_PAD) / 2;
   int bw = (w - Dpi(UI_PAD) * 2 - Dpi(UI_BTN_GAP)) / 2;
   UiButton(ID_BTN_TRADE, x + Dpi(UI_PAD), g_uiY, bw, Dpi(UI_BTN_H),
            "TRADING ON", THEME_BUY, THEME_BG);
   UiButton(ID_BTN_GRID, x + Dpi(UI_PAD) + bw + Dpi(UI_BTN_GAP), g_uiY, bw, Dpi(UI_BTN_H),
            "GRID ON", THEME_NEON, THEME_BG);
   g_uiY += Dpi(UI_BTN_H) + Dpi(UI_BTN_GAP);
   UiButton(ID_BTN_CLOSE, x + Dpi(UI_PAD), g_uiY, bw, Dpi(UI_BTN_H),
            "CLOSE BASKET", THEME_GOLD, THEME_BG);
   UiButton(ID_BTN_PANIC, x + Dpi(UI_PAD) + bw + Dpi(UI_BTN_GAP), g_uiY, bw, Dpi(UI_BTN_H),
            "PANIC HALT", THEME_SELL, THEME_TEXT);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Refresh the values. Never recreates an object.                   |
//+------------------------------------------------------------------+
void PanelUpdate(void)
  {
   if(!g_ea.panelVisible) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;

   //--- header: animated status LED
   g_ea.ledPhase = (g_ea.ledPhase + 1) % 2;
   color led = THEME_TEXT_DIM;
   if(g_ea.guard.halted)          led = THEME_SELL;
   else if(!g_ea.tradingEnabled)  led = THEME_WARN;
   else if(g_ea.cycle.active)     led = (g_ea.ledPhase == 0) ? THEME_NEON : THEME_BG_HEAD;
   else                           led = (g_ea.ledPhase == 0) ? THEME_BUY : THEME_BG_HEAD;

   string ledName = UiPfx() + ID_LED;
   ObjectSetInteger(0, ledName, OBJPROP_BGCOLOR, led);
   ObjectSetInteger(0, ledName, OBJPROP_COLOR,   led);
   UiText("clock", TimeToString(TimeCurrent(), TIME_MINUTES | TIME_SECONDS));

   //--- market
   SMarketView v = g_ea.view;
   color regClr = (v.regime == REG_TREND_UP)   ? THEME_BUY
                : (v.regime == REG_TREND_DOWN) ? THEME_SELL
                : (v.regime == REG_RANGE)      ? THEME_GOLD : THEME_TEXT_DIM;
   UiValue("regime", RegimeText(v.regime), regClr);
   UiValue("bias", StringFormat("%s / %s", DirText(v.bias), DirText(v.stackDir)),
           DirColor(v.bias));
   UiValue("adx", StringFormat("%.1f   %.1f / %.1f", v.adx, v.diPlus, v.diMinus),
           v.adx >= InpAdxTrendMin ? THEME_NEON : THEME_TEXT_DIM);
   UiValue("slope", StringFormat("%+.3f", v.slopeAtr), PnlColor(v.slopeAtr));
   UiValue("atr", StringFormat("%s / %d pts", FmtPrice(v.atr), SpreadPoints()),
           SpreadOK() ? THEME_TEXT : THEME_WARN);

   //--- structure
   SSwing s = g_ea.swing;
   if(s.valid)
     {
      double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double r  = RetracementOf(s, px);
      double zn, zf;
      EntryZone(s, zn, zf);
      UiValue("leg", StringFormat("%s  %.1f ATR", s.dir > 0 ? "IMPULSE UP" : "IMPULSE DOWN",
                                  s.atr > 0 ? s.range / s.atr : 0), DirColor(s.dir));
      UiValue("legpx", StringFormat("%s / %s", FmtPrice(s.hi), FmtPrice(s.lo)));
      UiValue("retr", StringFormat("%.1f%%", r * 100.0),
              (r >= InpEntryFibMin && r <= InpEntryFibMax) ? THEME_GOLD : THEME_TEXT);
      UiValue("zone", StringFormat("%s - %s", FmtPrice(zf), FmtPrice(zn)));
      UiValue("tps", StringFormat("%s / %s", FmtPrice(FibExtend(s, InpTp1Fib)),
                                  FmtPrice(FibExtend(s, InpTp2Fib))));
     }
   else
     {
      UiValue("leg",   "no qualified leg", THEME_TEXT_DIM);
      UiValue("legpx", "-", THEME_TEXT_DIM);
      UiValue("retr",  "-", THEME_TEXT_DIM);
      UiValue("zone",  "-", THEME_TEXT_DIM);
      UiValue("tps",   "-", THEME_TEXT_DIM);
     }

   //--- cycle
   if(g_ea.cycle.active)
     {
      double floating = BasketProfit();
      UiValue("cdir", StringFormat("%s  /  %d of %d", DirText(g_ea.cycle.dir),
                                   g_ea.cycle.levels, InpGridMaxLevels),
              DirColor(g_ea.cycle.dir));
      UiValue("cavg", StringFormat("%s / %s", FmtPrice(BasketAvgPrice()),
                                   FmtLots(BasketVolume())));
      UiValue("cfloat", StringFormat("%s / %s", FmtMoney(floating),
                                     FmtMoney(g_ea.cycle.realised)), PnlColor(floating));
      UiValue("cnext", g_ea.cycle.nextPrice > 0 ? FmtPrice(g_ea.cycle.nextPrice)
                                                : "ladder closed",
              g_ea.cycle.nextPrice > 0 ? THEME_NEON : THEME_TEXT_DIM);
      UiValue("cstop", StringFormat("%s%s", FmtPrice(g_ea.cycle.stopPrice),
                                    g_ea.cycle.beDone ? "  BE" : ""),
              g_ea.cycle.beDone ? THEME_BUY : THEME_SELL);
      UiValue("ctp", StringFormat("%s%s%s", FmtPrice(g_ea.cycle.tp3),
                                  g_ea.cycle.tp1Done ? "  T1" : "",
                                  g_ea.cycle.tp2Done ? " T2" : ""), THEME_GOLD);
     }
   else
     {
      UiValue("cdir",   "FLAT", THEME_TEXT_DIM);
      UiValue("cavg",   "-", THEME_TEXT_DIM);
      UiValue("cfloat", "-", THEME_TEXT_DIM);
      UiValue("cnext",  "-", THEME_TEXT_DIM);
      UiValue("cstop",  "-", THEME_TEXT_DIM);
      UiValue("ctp",    "-", THEME_TEXT_DIM);
     }

   //--- account
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dayPL   = equity - g_ea.guard.dayStartBalance;
   double ddPct   = (g_ea.guard.peakEquity > 0)
                    ? (g_ea.guard.peakEquity - equity) / g_ea.guard.peakEquity * 100.0 : 0;
   double mlevel  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   UiValue("aeq", StringFormat("%.2f / %.2f", equity, balance));
   UiValue("aday", StringFormat("%s  (%.2f%%)", FmtMoney(dayPL),
                                g_ea.guard.dayStartBalance > 0
                                ? dayPL / g_ea.guard.dayStartBalance * 100.0 : 0),
           PnlColor(dayPL));
   UiValue("add", StringFormat("%.2f%% / %.2f", ddPct, g_ea.guard.peakEquity),
           ddPct >= InpMaxTotalDDPct * 0.5 ? THEME_WARN : THEME_TEXT);
   UiValue("amargin", mlevel > 0 ? StringFormat("%.0f%%", mlevel) : "n/a",
           (mlevel > 0 && mlevel < 300) ? THEME_SELL : THEME_TEXT);

   //--- performance
   double wr = (g_ea.stats.cyclesTotal > 0)
               ? (double)g_ea.stats.cyclesWon / g_ea.stats.cyclesTotal * 100.0 : 0;
   UiValue("scyc", StringFormat("%d  /  %.0f%%", g_ea.stats.cyclesTotal, wr));
   UiValue("spl", FmtMoney(g_ea.stats.realisedTotal), PnlColor(g_ea.stats.realisedTotal));
   UiValue("sevent", StringLen(g_ea.lastEvent) > 0 ? g_ea.lastEvent : "idle", THEME_NEON);

   //--- controls reflect STATE, never the inputs
   UiBtnStyle(ID_BTN_TRADE, g_ea.tradingEnabled ? "TRADING ON" : "TRADING OFF",
              g_ea.tradingEnabled ? THEME_BUY : THEME_BORDER,
              g_ea.tradingEnabled ? THEME_BG : THEME_TEXT_DIM);
   UiBtnStyle(ID_BTN_GRID, g_ea.gridEnabled ? "GRID ON" : "GRID OFF",
              g_ea.gridEnabled ? THEME_NEON : THEME_BORDER,
              g_ea.gridEnabled ? THEME_BG : THEME_TEXT_DIM);
   UiBtnStyle(ID_BTN_PANIC, g_ea.guard.halted ? "HALTED" : "PANIC HALT",
              g_ea.guard.halted ? THEME_BORDER : THEME_SELL,
              g_ea.guard.halted ? THEME_SELL : THEME_TEXT);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Button clicks. Returns true when the click was ours.             |
//+------------------------------------------------------------------+
bool PanelHandleClick(const string objName)
  {
   string pfx = UiPfx();
   if(StringFind(objName, pfx) != 0) return false;
   string id = StringSubstr(objName, StringLen(pfx));

   if(id == ID_BTN_TRADE)
     {
      g_ea.tradingEnabled = !g_ea.tradingEnabled;
      Notify(g_ea.tradingEnabled ? "TRADING ENABLED" : "TRADING DISABLED", "panel", false);
     }
   else if(id == ID_BTN_GRID)
     {
      g_ea.gridEnabled = !g_ea.gridEnabled;
      Notify(g_ea.gridEnabled ? "GRID ENABLED" : "GRID DISABLED", "panel", false);
     }
   else if(id == ID_BTN_CLOSE)
     {
      if(g_ea.cycle.active) CloseCycle("closed from panel");
      else                  CloseAllMine("closed from panel");
     }
   else if(id == ID_BTN_PANIC)
     {
      if(g_ea.guard.halted)
        {
         g_ea.guard.halted     = false;
         g_ea.guard.haltReason = "";
         g_ea.tradingEnabled   = true;
         Notify("HALT CLEARED", "panel", true);
        }
      else
         GuardBreach("Manual panic halt", true);
     }
   else
      return false;

   PanelUpdate();
   return true;
  }

void PanelDestroy(void)
  {
   ObjectsDeleteAll(0, UiPfx());
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| A right-docked panel has to follow the chart width. Rebuilding on |
//| every CHART_CHANGE would flicker on each scroll, so the width is  |
//| remembered and the rebuild only happens when it actually changed. |
//+------------------------------------------------------------------+
void PanelRelayout(void)
  {
   if(!g_ea.panelVisible || !InpPanelRight) return;

   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(chartW == g_ea.chartW) return;

   g_ea.chartW = chartW;
   PanelDestroy();
   PanelBuild();
   PanelUpdate();
  }

//+------------------------------------------------------------------+
//| PRICE-ANCHORED DRAWING — the market layer, not the app layer     |
//+------------------------------------------------------------------+
bool DrawSegment(const string id, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr,
                 const int width, const ENUM_LINE_STYLE style)
  {
   string n = UiPfx() + id;
   if(ObjectFind(0, n) < 0)
     {
      if(!ObjectCreate(0, n, OBJ_TREND, 0, t1, p1, t2, p2)) return false;
     }
   else
     {
      ObjectMove(0, n, 0, t1, p1);
      ObjectMove(0, n, 1, t2, p2);
     }
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, n, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   return true;
  }

bool DrawZoneBox(const string id, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr)
  {
   string n = UiPfx() + id;
   if(ObjectFind(0, n) < 0)
     {
      if(!ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return false;
     }
   else
     {
      ObjectMove(0, n, 0, t1, p1);
      ObjectMove(0, n, 1, t2, p2);
     }
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_FILL,       true);
   ObjectSetInteger(0, n, OBJPROP_BACK,       true);   // behind the candles
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   return true;
  }

bool DrawTag(const string id, const datetime t, const double price,
             const string text, const color clr)
  {
   string n = UiPfx() + id;
   if(ObjectFind(0, n) < 0)
     {
      if(!ObjectCreate(0, n, OBJ_TEXT, 0, t, price)) return false;
     }
   else
      ObjectMove(0, n, 0, t, price);

   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   UI_FS);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,     ANCHOR_LEFT);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   ObjectSetString (0, n, OBJPROP_FONT,       UI_FONT);
   ObjectSetString (0, n, OBJPROP_TEXT,       text);
   return true;
  }

//--- Right-hand edge the structure is drawn out to.
datetime DrawRightEdge(const int extraBars = 14)
  {
   int sec = PeriodSeconds(SignalTF());
   return (datetime)((long)iTime(_Symbol, SignalTF(), 0) + (long)extraBars * sec);
  }

void DrawStructure(void)
  {
   if(!InpDrawFib || MQLInfoInteger(MQL_OPTIMIZATION)) return;

   SSwing s = g_ea.swing;
   if(!s.valid) return;

   datetime t0 = (s.hiTime < s.loTime) ? s.hiTime : s.loTime;   // the leg's origin bar
   if(t0 <= 0) t0 = iTime(_Symbol, SignalTF(), 1);
   datetime t1 = DrawRightEdge();

   //--- the impulse leg itself
   DrawSegment(ID_DRAW_LEG, s.loTime, s.lo, s.hiTime, s.hi,
               s.dir > 0 ? THEME_BUY : THEME_SELL, 2, STYLE_SOLID);

   //--- retracement ladder
   for(int i = 0; i < ArraySize(FIB_RETRACE); i++)
     {
      double r  = FIB_RETRACE[i];
      double px = FibRetrace(s, r);
      bool  key = (MathAbs(r - 0.618) < 1e-6 || MathAbs(r - 0.5) < 1e-6);
      DrawSegment(StringFormat("fr%d", i), t0, px, t1, px,
                  key ? THEME_GOLD : THEME_GRID_LINE, key ? 2 : 1,
                  key ? STYLE_SOLID : STYLE_DOT);
      DrawTag(StringFormat("frt%d", i), t1, px, StringFormat("  %.3f", r),
              key ? THEME_GOLD : THEME_TEXT_DIM);
     }

   //--- extension targets
   double tps[3];
   tps[0] = InpTp1Fib; tps[1] = InpTp2Fib; tps[2] = InpTp3Fib;
   for(int i = 0; i < 3; i++)
     {
      double px = FibExtend(s, tps[i]);
      DrawSegment(StringFormat("fe%d", i), t0, px, t1, px, THEME_NEON, 1, STYLE_DASH);
      DrawTag(StringFormat("fet%d", i), t1, px, StringFormat("  TP%d %.3f", i + 1, tps[i]),
              THEME_NEON);
     }

   //--- the entry zone as a filled box
   double zn, zf;
   EntryZone(s, zn, zf);
   DrawZoneBox(ID_DRAW_ZONE, t0, zn, t1, zf,
               s.dir > 0 ? THEME_ZONE_BULL : THEME_ZONE_BEAR);
  }

void DrawGridLevels(void)
  {
   if(!InpDrawGrid || MQLInfoInteger(MQL_OPTIMIZATION)) return;

   datetime t0 = (g_ea.cycle.started > 0) ? g_ea.cycle.started : iTime(_Symbol, SignalTF(), 20);
   datetime t1 = DrawRightEdge();

   //--- filled levels
   for(int i = 0; i < g_grid.Total(); i++)
     {
      CGridLevel *gl = (CGridLevel*)g_grid.At(i);
      if(gl == NULL) continue;
      DrawSegment(StringFormat("gl%d", gl.level), t0, gl.filled, t1, gl.filled,
                  DirColor(g_ea.cycle.dir), 1, STYLE_SOLID);
      DrawTag(StringFormat("glt%d", gl.level), t1, gl.filled,
              StringFormat("  L%d  %s", gl.level, FmtLots(gl.lots)), DirColor(g_ea.cycle.dir));
     }

   //--- the pending next step
   if(g_ea.cycle.active && g_ea.cycle.nextPrice > 0)
     {
      DrawSegment("glnext", t0, g_ea.cycle.nextPrice, t1, g_ea.cycle.nextPrice,
                  THEME_WARN, 1, STYLE_DASHDOT);
      DrawTag("glnextt", t1, g_ea.cycle.nextPrice, "  NEXT", THEME_WARN);
     }

   //--- basket stop and average
   if(g_ea.cycle.active)
     {
      if(g_ea.cycle.stopPrice > 0)
        {
         DrawSegment("glstop", t0, g_ea.cycle.stopPrice, t1, g_ea.cycle.stopPrice,
                     THEME_SELL, 2, STYLE_SOLID);
         DrawTag("glstopt", t1, g_ea.cycle.stopPrice, "  BASKET SL", THEME_SELL);
        }
      double avg = BasketAvgPrice();
      if(avg > 0)
        {
         DrawSegment("glavg", t0, avg, t1, avg, THEME_GOLD, 2, STYLE_DOT);
         DrawTag("glavgt", t1, avg, "  AVG", THEME_GOLD);
        }
     }
  }

//--- Remove only the price-anchored objects, leaving the HUD in place.
void DrawClearCycle(void)
  {
   ObjectsDeleteAll(0, UiPfx() + "gl");
  }

#endif // GFEA_PANEL_MQH
//+------------------------------------------------------------------+
