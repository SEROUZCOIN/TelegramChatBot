//+------------------------------------------------------------------+
//|                                                    NGZ_Panel.mqh |
//|          Neuro Gann Zones - dashboard (screen/pixel space)         |
//|                                                                   |
//|  Futuristic dark HUD: neon blue + gold, signed gauges, live       |
//|  module read-outs and five layer toggles. Built entirely from     |
//|  the THEME and METRICS libraries of NGZ_Config.mqh.               |
//+------------------------------------------------------------------+
#ifndef __NGZ_PANEL_MQH__
#define __NGZ_PANEL_MQH__

#include "NGZ_Config.mqh"
#include "NGZ_State.mqh"
#include "NGZ_Math.mqh"
#include "NGZ_Draw.mqh"

//--- row slots of the dashboard
#define NGZ_ROW_INST     0
#define NGZ_ROW_BIAS     1
#define NGZ_ROW_FUSED    2
#define NGZ_ROW_NEURO    3
#define NGZ_ROW_MATH     4
#define NGZ_ROW_GANN     5
#define NGZ_ROW_UNIT     6
#define NGZ_ROW_ANCHOR_B 7
#define NGZ_ROW_ANCHOR_S 8
#define NGZ_ROW_RAIL_UP  9
#define NGZ_ROW_RAIL_DN  10
#define NGZ_ROW_SQ9_UP   11
#define NGZ_ROW_SQ9_DN   12
#define NGZ_ROW_CYCLE    13
#define NGZ_ROW_ZONE     14
#define NGZ_ROW_NET      15
#define NGZ_ROW_SIGNAL   16
#define NGZ_ROWS         17

#define NGZ_PANEL_ID     "PNL_"

//+------------------------------------------------------------------+
//| DPI aware metric                                                  |
//+------------------------------------------------------------------+
int NgzDpi(const int base)
  {
   if(!InpPanelDpi) return base;
   if(g_s.dpi <= 0) g_s.dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(g_s.dpi <= 0) return base;
   return base * g_s.dpi / 96;
  }

int NgzPanelW(void) { return NgzDpi(NGZ_UI_PANEL_W); }

int NgzPanelH(void)
  {
   if(g_s.collapsed) return NgzDpi(NGZ_UI_HEAD_H);
   return NgzDpi(NGZ_UI_HEAD_H) + NgzDpi(NGZ_UI_PAD)
          + NGZ_ROWS * NgzDpi(NGZ_UI_ROW_H)
          + NgzDpi(NGZ_UI_PAD) + NgzDpi(NGZ_UI_BTN_H) + NgzDpi(NGZ_UI_PAD);
  }

ENUM_BASE_CORNER NgzCorner(void)
  {
   switch(InpPanelCorner)
     {
      case NGZ_CORNER_RU: return CORNER_RIGHT_UPPER;
      case NGZ_CORNER_LL: return CORNER_LEFT_LOWER;
      case NGZ_CORNER_RL: return CORNER_RIGHT_LOWER;
      default:            return CORNER_LEFT_UPPER;
     }
  }

//+------------------------------------------------------------------+
//| Local panel coordinates -> chart pixel distances for the corner   |
//| in use. All layout code below thinks in a top-left system.        |
//+------------------------------------------------------------------+
void NgzPanelXY(const int lx, const int ly, const int w, const int h, int &x, int &y)
  {
   bool right = (InpPanelCorner == NGZ_CORNER_RU || InpPanelCorner == NGZ_CORNER_RL);
   bool lower = (InpPanelCorner == NGZ_CORNER_LL || InpPanelCorner == NGZ_CORNER_RL);
   int  px = NgzDpi(InpPanelX);
   int  py = NgzDpi(InpPanelY);
   int  PW = NgzPanelW();
   int  PH = NgzPanelH();

   x = right ? (px + PW - lx - w) : (px + lx);
   y = lower ? (py + PH - ly - h) : (py + ly);
  }

//+------------------------------------------------------------------+
//| Widget factories - create once, update many                       |
//+------------------------------------------------------------------+
bool NgzWidget(const string id, const ENUM_OBJECT type, const int lx, const int ly,
               const int w, const int h)
  {
   string n = NgzPrefix() + NGZ_PANEL_ID + id;
   if(ObjectFind(0, n) < 0 && !ObjectCreate(0, n, type, 0, 0, 0))
      return false;

   int x = 0, y = 0;
   NgzPanelXY(lx, ly, w, h, x, y);

   ObjectSetInteger(0, n, OBJPROP_CORNER,     NgzCorner());
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, n, OBJPROP_BACK,       false);
   return true;
  }

//--- filled rectangle (background, gauge track, gauge fill)
bool NgzRect(const string id, const int lx, const int ly, const int w, const int h,
             const color bg, const color border, const int z = 0)
  {
   if(!NgzWidget(id, OBJ_RECTANGLE_LABEL, lx, ly, w, h)) return false;
   string n = NgzPrefix() + NGZ_PANEL_ID + id;
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      z);
   return true;
  }

//--- read-only text cell. OBJ_EDIT is used instead of OBJ_LABEL because
//--- a label is not guaranteed to paint above a rectangle label, while
//--- an edit box always is - and it supports real text alignment.
bool NgzCell(const string id, const int lx, const int ly, const int w, const int h,
             const string text, const color fg, const color bg,
             const ENUM_ALIGN_MODE align = ALIGN_LEFT, const int fs = NGZ_UI_FS,
             const string font = NGZ_UI_FONT)
  {
   if(!NgzWidget(id, OBJ_EDIT, lx, ly, w, h)) return false;
   string n = NgzPrefix() + NGZ_PANEL_ID + id;
   ObjectSetString (0, n, OBJPROP_TEXT,         text);
   ObjectSetString (0, n, OBJPROP_FONT,         font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     NgzDpi(fs));
   ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_ALIGN,        align);
   ObjectSetInteger(0, n, OBJPROP_READONLY,     true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       5);
   return true;
  }

//--- clickable toggle
bool NgzToggle(const string id, const int lx, const int ly, const int w, const int h,
               const string text, const bool on)
  {
   if(!NgzWidget(id, OBJ_BUTTON, lx, ly, w, h)) return false;
   string n = NgzPrefix() + NGZ_PANEL_ID + id;
   ObjectSetString (0, n, OBJPROP_TEXT,         text);
   ObjectSetString (0, n, OBJPROP_FONT,         NGZ_UI_FONT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     NgzDpi(NGZ_UI_FS));
   ObjectSetInteger(0, n, OBJPROP_COLOR,        on ? NGZ_CLR_BG : NGZ_CLR_TEXT_DIM);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      on ? NGZ_CLR_NEON : NGZ_CLR_BG_ROW);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, NGZ_CLR_BORDER);
   ObjectSetInteger(0, n, OBJPROP_STATE,        false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       10);
   return true;
  }

//+------------------------------------------------------------------+
//| Signed gauge: a track with a fill growing left or right of centre |
//+------------------------------------------------------------------+
void NgzGauge(const string id, const int lx, const int ly, const double value, const color clr)
  {
   int w = NgzDpi(NGZ_UI_GAUGE_W);
   int h = NgzDpi(NGZ_UI_GAUGE_H);
   NgzRect(id + "T", lx, ly, w, h, NGZ_CLR_BG_HEAD, NGZ_CLR_BORDER, 6);

   double v    = NgzClamp(value, -1.0, 1.0);
   int    half = w / 2;
   int    len  = (int)MathRound(MathAbs(v) * (double)half);
   if(len < 1) len = 1;

   int fx = (v >= 0.0) ? (lx + half) : (lx + half - len);
   NgzRect(id + "F", fx, ly, len, h, clr, clr, 7);
  }

//+------------------------------------------------------------------+
//| Build the whole dashboard (idempotent)                            |
//+------------------------------------------------------------------+
void NgzPanelCreate(void)
  {
   int PW    = NgzPanelW();
   int pad   = NgzDpi(NGZ_UI_PAD);
   int headH = NgzDpi(NGZ_UI_HEAD_H);
   int rowH  = NgzDpi(NGZ_UI_ROW_H);
   int btnH  = NgzDpi(NGZ_UI_BTN_H);

   //--- shell
   NgzRect("BG",   0, 0, PW, NgzPanelH(), NGZ_CLR_BG,      NGZ_CLR_BORDER, 0);
   NgzRect("HEAD", 0, 0, PW, headH,       NGZ_CLR_BG_HEAD, NGZ_CLR_NEON,   1);
   NgzCell("TITLE", pad, NgzDpi(5), PW - pad * 2 - NgzDpi(24), headH - NgzDpi(9),
           "NEURO GANN ZONES", NGZ_CLR_NEON, NGZ_CLR_BG_HEAD, ALIGN_LEFT,
           NGZ_UI_FS_HEAD, NGZ_UI_FONT_HEAD);
   NgzToggle("BTN_MIN", PW - pad - NgzDpi(20), NgzDpi(5), NgzDpi(20), headH - NgzDpi(10),
             g_s.collapsed ? "+" : "-", false);

   if(g_s.collapsed)
     {
      //--- hide everything below the header
      for(int i = 0; i < NGZ_ROWS; i++)
        {
         ObjectDelete(0, NgzPrefix() + NGZ_PANEL_ID + "L" + IntegerToString(i));
         ObjectDelete(0, NgzPrefix() + NGZ_PANEL_ID + "V" + IntegerToString(i));
        }
      ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID + "G");
      ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID + "BTN_F");
      ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID + "BTN_S");
      ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID + "BTN_Z");
      ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID + "BTN_C");
      ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID + "BTN_D");
      return;
     }

   //--- rows: [label][value] ; gauge rows insert a bar between them
   int labW = NgzDpi(NGZ_UI_LAB_W);
   int top  = headH + pad;
   for(int i = 0; i < NGZ_ROWS; i++)
     {
      int ly = top + i * rowH;
      NgzCell("L" + IntegerToString(i), pad, ly, labW, rowH - NgzDpi(2), "",
              NGZ_CLR_TEXT_DIM, NGZ_CLR_BG_ROW, ALIGN_LEFT);
      NgzCell("V" + IntegerToString(i), pad + labW + NgzDpi(2), ly,
              PW - pad * 2 - labW - NgzDpi(2), rowH - NgzDpi(2), "",
              NGZ_CLR_TEXT, NGZ_CLR_BG_ROW, ALIGN_RIGHT);
     }

   //--- toggle strip
   int by = top + NGZ_ROWS * rowH + pad;
   int gap = NgzDpi(4);
   int bw  = (PW - pad * 2 - gap * 4) / 5;
   NgzToggle("BTN_FAN", pad,                      by, bw, btnH, "FAN",  g_s.showFan);
   NgzToggle("BTN_SQ9", pad + (bw + gap),         by, bw, btnH, "SQ9",  g_s.showSq9);
   NgzToggle("BTN_ZON", pad + (bw + gap) * 2,     by, bw, btnH, "ZONE", g_s.showZones);
   NgzToggle("BTN_CYC", pad + (bw + gap) * 3,     by, bw, btnH, "CYCL", g_s.showCycles);
   NgzToggle("BTN_DIV", pad + (bw + gap) * 4,     by, bw, btnH, "1/8",  g_s.showRetrace);
  }

//+------------------------------------------------------------------+
//| Row setter helpers                                                |
//+------------------------------------------------------------------+
void NgzRowSet(const int idx, const string label, const string value, const color clr)
  {
   string ln = NgzPrefix() + NGZ_PANEL_ID + "L" + IntegerToString(idx);
   string vn = NgzPrefix() + NGZ_PANEL_ID + "V" + IntegerToString(idx);
   if(ObjectFind(0, ln) >= 0) ObjectSetString(0, ln, OBJPROP_TEXT, label);
   if(ObjectFind(0, vn) >= 0)
     {
      ObjectSetString (0, vn, OBJPROP_TEXT,  value);
      ObjectSetInteger(0, vn, OBJPROP_COLOR, clr);
     }
  }

color NgzScoreColor(const double v)
  {
   if(v >=  InpExitLevel) return NGZ_CLR_UP;
   if(v <= -InpExitLevel) return NGZ_CLR_DOWN;
   return NGZ_CLR_FLAT;
  }

string NgzPct(const double v) { return DoubleToString(v * 100.0, 1) + "%"; }

//+------------------------------------------------------------------+
//| Refresh every live read-out                                       |
//+------------------------------------------------------------------+
void NgzPanelUpdate(const double lastClose)
  {
   if(g_s.collapsed) return;

   int pad  = NgzDpi(NGZ_UI_PAD);
   int rowH = NgzDpi(NGZ_UI_ROW_H);
   int top  = NgzDpi(NGZ_UI_HEAD_H) + pad;
   int gx   = pad + NgzDpi(NGZ_UI_LAB_W) + NgzDpi(4);   // left half of the value cell

   //--- instrument
   NgzRowSet(NGZ_ROW_INST, "SYMBOL", _Symbol + "  " + NgzTfName(), NGZ_CLR_TEXT);

   //--- direction
   string bias = (g_s.bias > 0) ? "UP  /  LONG" : (g_s.bias < 0 ? "DOWN  /  SHORT" : "NEUTRAL");
   NgzRowSet(NGZ_ROW_BIAS, "BIAS", bias, NgzScoreColor((double)g_s.bias));
   NgzRowSet(NGZ_ROW_FUSED, "SCORE", NgzPct(g_s.fused), NgzScoreColor(g_s.fused));

   //--- module scores with signed gauges
   NgzRowSet(NGZ_ROW_NEURO, "NEURO", NgzPct(g_s.neuro), NgzScoreColor(g_s.neuro));
   NgzRowSet(NGZ_ROW_MATH,  "MATH",  NgzPct(g_s.maths), NgzScoreColor(g_s.maths));
   NgzRowSet(NGZ_ROW_GANN,  "GANN",  NgzPct(g_s.gann),  NgzScoreColor(g_s.gann));
   NgzGauge("G0", gx, top + NGZ_ROW_NEURO * rowH + NgzDpi(5), g_s.neuro, NgzScoreColor(g_s.neuro));
   NgzGauge("G1", gx, top + NGZ_ROW_MATH  * rowH + NgzDpi(5), g_s.maths, NgzScoreColor(g_s.maths));
   NgzGauge("G2", gx, top + NGZ_ROW_GANN  * rowH + NgzDpi(5), g_s.gann,  NgzScoreColor(g_s.gann));

   //--- geometry
   double unitPts = (_Point > 0.0) ? g_s.unit / _Point : 0.0;
   NgzRowSet(NGZ_ROW_UNIT, "1x1 UNIT", DoubleToString(unitPts, 1) + " pt/bar", NGZ_CLR_GOLD);

   if(g_s.bullAnchor.valid)
      NgzRowSet(NGZ_ROW_ANCHOR_B, "LOW ANCH",
                DoubleToString(g_s.bullAnchor.price, _Digits) + "  " +
                TimeToString(g_s.bullAnchor.time, TIME_DATE | TIME_MINUTES), NGZ_CLR_UP);
   else
      NgzRowSet(NGZ_ROW_ANCHOR_B, "LOW ANCH", "searching...", NGZ_CLR_TEXT_DIM);

   if(g_s.bearAnchor.valid)
      NgzRowSet(NGZ_ROW_ANCHOR_S, "HIGH ANCH",
                DoubleToString(g_s.bearAnchor.price, _Digits) + "  " +
                TimeToString(g_s.bearAnchor.time, TIME_DATE | TIME_MINUTES), NGZ_CLR_DOWN);
   else
      NgzRowSet(NGZ_ROW_ANCHOR_S, "HIGH ANCH", "searching...", NGZ_CLR_TEXT_DIM);

   //--- the two rails, i.e. the tradable "up line" and "down line"
   NgzRowSet(NGZ_ROW_RAIL_UP, "UP 1x1",
             (g_s.railUp > 0.0) ? DoubleToString(g_s.railUp, _Digits) : "-",
             (g_s.railUp > 0.0 && lastClose >= g_s.railUp) ? NGZ_CLR_UP : NGZ_CLR_TEXT_DIM);
   NgzRowSet(NGZ_ROW_RAIL_DN, "DOWN 1x1",
             (g_s.railDn > 0.0) ? DoubleToString(g_s.railDn, _Digits) : "-",
             (g_s.railDn > 0.0 && lastClose <= g_s.railDn) ? NGZ_CLR_DOWN : NGZ_CLR_TEXT_DIM);

   //--- Square of 9 brackets
   NgzRowSet(NGZ_ROW_SQ9_UP, "SQ9 RES",
             (g_s.sq9Above > 0.0) ? DoubleToString(g_s.sq9Above, _Digits) : "-", NGZ_CLR_SQ9);
   NgzRowSet(NGZ_ROW_SQ9_DN, "SQ9 SUP",
             (g_s.sq9Below > 0.0) ? DoubleToString(g_s.sq9Below, _Digits) : "-", NGZ_CLR_SQ9);

   //--- time cycles
   if(g_s.nextCycleBars >= 0)
      NgzRowSet(NGZ_ROW_CYCLE, "NEXT CYC",
                IntegerToString(g_s.nextCycleBars) + " bars  (C" +
                IntegerToString(g_s.nextCycleLen) + ")",
                (g_s.nextCycleBars <= InpCycleBand) ? NGZ_CLR_GOLD : NGZ_CLR_TEXT);
   else
      NgzRowSet(NGZ_ROW_CYCLE, "NEXT CYC", "-", NGZ_CLR_TEXT_DIM);

   //--- premium / discount
   string zone = "-";
   color  zclr = NGZ_CLR_TEXT_DIM;
   if(g_s.swingHi - g_s.swingLo > 1.0e-12)
     {
      double pos = NgzRangePos(lastClose, g_s.swingLo, g_s.swingHi);
      if(pos > 0.15)      { zone = "PREMIUM "  + NgzPct(pos);  zclr = NGZ_CLR_DOWN; }
      else if(pos < -0.15){ zone = "DISCOUNT " + NgzPct(-pos); zclr = NGZ_CLR_UP;   }
      else                { zone = "EQUILIBRIUM";              zclr = NGZ_CLR_NEON; }
     }
   NgzRowSet(NGZ_ROW_ZONE, "ZONE", zone, zclr);

   //--- network diagnostics
   if(!InpUseNeuro)
      NgzRowSet(NGZ_ROW_NET, "NETWORK", "disabled", NGZ_CLR_TEXT_DIM);
   else
      if(g_s.netReady)
         NgzRowSet(NGZ_ROW_NET, "NETWORK",
                   IntegerToString(g_net.samples) + "s  hit " +
                   DoubleToString(g_net.accuracy * 100.0, 1) + "%", NGZ_CLR_NEON);
      else
         NgzRowSet(NGZ_ROW_NET, "NETWORK", "training...", NGZ_CLR_GOLD);

   //--- last confirmed signal
   if(g_s.lastAlertBar > 0)
      NgzRowSet(NGZ_ROW_SIGNAL, "SIGNAL",
                (g_s.lastAlertDir > 0 ? "BUY  " : "SELL ") +
                TimeToString(g_s.lastAlertBar, TIME_DATE | TIME_MINUTES),
                (g_s.lastAlertDir > 0) ? NGZ_CLR_UP : NGZ_CLR_DOWN);
   else
      NgzRowSet(NGZ_ROW_SIGNAL, "SIGNAL", "waiting", NGZ_CLR_TEXT_DIM);
  }

//+------------------------------------------------------------------+
//| Click routing. Returns true when the click was ours.              |
//+------------------------------------------------------------------+
bool NgzPanelClick(const string sparam)
  {
   string base = NgzPrefix() + NGZ_PANEL_ID;
   if(StringFind(sparam, base) != 0) return false;

   //--- a button must never stay latched
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   string id = StringSubstr(sparam, StringLen(base));

   if(id == "BTN_MIN") g_s.collapsed   = !g_s.collapsed;
   else if(id == "BTN_FAN") g_s.showFan     = !g_s.showFan;
   else if(id == "BTN_SQ9") g_s.showSq9     = !g_s.showSq9;
   else if(id == "BTN_ZON") g_s.showZones   = !g_s.showZones;
   else if(id == "BTN_CYC") g_s.showCycles  = !g_s.showCycles;
   else if(id == "BTN_DIV") g_s.showRetrace = !g_s.showRetrace;
   else return true;                        // our object, nothing to toggle

   g_s.needRedraw = true;
   return true;
  }

//+------------------------------------------------------------------+
void NgzPanelDestroy(void)
  {
   ObjectsDeleteAll(0, NgzPrefix() + NGZ_PANEL_ID);
  }

#endif // __NGZ_PANEL_MQH__
//+------------------------------------------------------------------+
