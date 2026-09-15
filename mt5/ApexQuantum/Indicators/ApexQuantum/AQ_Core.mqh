//+------------------------------------------------------------------+
//|                                                      AQ_Core.mqh |
//|              APEX QUANTUM — shared types, helpers, factories     |
//|                                                                  |
//|  Contains: enums, data structures, math/time helpers and the     |
//|  object factories used by every UI and drawing module.           |
//+------------------------------------------------------------------+
#ifndef AQ_CORE_MQH
#define AQ_CORE_MQH

#include "AQ_Theme.mqh"

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
//--- zone side
enum ENUM_AQ_ZONE_KIND
  {
   AQ_ZONE_DEMAND = 0,          // demand / support
   AQ_ZONE_SUPPLY = 1           // supply / resistance
  };

//--- zone quality, ordered weakest -> strongest (order is used by MathMax on merge)
enum ENUM_AQ_GRADE
  {
   AQ_GRADE_WEAK   = 0,         // single (fast-only) fractal, never retested
   AQ_GRADE_BROKEN = 1,         // level flipped side at least once (turncoat)
   AQ_GRADE_FRESH  = 2,         // major fractal, untested
   AQ_GRADE_TESTED = 3,         // 1-3 confirmed retests
   AQ_GRADE_PROVEN = 4          // 4+ confirmed retests
  };

//--- entry model used by the signal engine
enum ENUM_AQ_SIGNAL_MODE
  {
   AQ_SIG_PULLBACK = 0,         // Pullback into a zone in the direction of trend
   AQ_SIG_FLIP     = 1,         // Trend flip (perfect-trend-line reversal)
   AQ_SIG_BOTH     = 2          // Both models
  };

//--- structural events
enum ENUM_AQ_EVENT
  {
   AQ_EV_CHOCH_BEAR = -2,       // change of character, bullish -> bearish
   AQ_EV_BOS_BEAR   = -1,       // break of structure, continuation down
   AQ_EV_NONE       =  0,
   AQ_EV_BOS_BULL   =  1,       // break of structure, continuation up
   AQ_EV_CHOCH_BULL =  2        // change of character, bearish -> bullish
  };

//--- dashboard anchor
enum ENUM_AQ_CORNER
  {
   AQ_CORNER_TL = 0,            // Top left
   AQ_CORNER_TR = 1,            // Top right
   AQ_CORNER_BL = 2,            // Bottom left
   AQ_CORNER_BR = 3             // Bottom right
  };

//+------------------------------------------------------------------+
//| DATA STRUCTURES                                                  |
//+------------------------------------------------------------------+
//--- a supply/demand zone
struct AQZone
  {
   double            hi;              // upper boundary
   double            lo;              // lower boundary
   int               startBar;        // bar index where the zone was born
   datetime          startTime;       // bar time where the zone was born
   int               hits;            // confirmed retests
   bool              flipped;         // level changed side at least once
   int               kind;            // ENUM_AQ_ZONE_KIND
   int               grade;           // ENUM_AQ_GRADE
  };

//--- a confirmed swing point
struct AQPivot
  {
   int               bar;             // bar index of the extreme
   int               confirm;         // bar index where the swing became known
   datetime          time;            // bar time of the extreme
   double            price;           // pivot price
   int               dir;             // +1 swing high, -1 swing low
  };

//--- a structural break (BOS / CHoCH)
struct AQBreak
  {
   int               bar;             // bar that broke the level
   datetime          time;            // its bar time
   double            price;           // level that was broken
   int               ev;              // ENUM_AQ_EVENT
  };

//--- a fair value gap (3-bar imbalance)
struct AQFvg
  {
   int               bar;             // bar index of the third candle
   datetime          time;            // its bar time
   double            hi;              // gap top
   double            lo;              // gap bottom
   int               dir;             // +1 bullish, -1 bearish
   bool              mitigated;       // price has traded back through it
  };

//--- parallel price channel
struct AQChannel
  {
   bool              valid;
   int               bar1;            // anchor bar (older)
   int               bar2;            // anchor bar (newer, right edge)
   double            base1, base2;    // base rail prices at bar1/bar2
   double            off1,  off2;     // opposite rail prices at bar1/bar2
   double            slope;           // price change per bar
   double            width;           // rail separation in price
   double            position;        // 0.0 = lower rail, 1.0 = upper rail
  };

//+------------------------------------------------------------------+
//| MATH / FORMAT HELPERS                                            |
//+------------------------------------------------------------------+
template<typename T>
T AQ_Clamp(T v, T lo, T hi) { return(v < lo ? lo : (v > hi ? hi : v)); }

//--- linear blend of two colours, t in [0..1]  (colour layout is 0x00BBGGRR)
color AQ_Blend(const color a, const color b, double t)
  {
   t = AQ_Clamp(t, 0.0, 1.0);
   int ar =  (int)a        & 0xFF, ag = ((int)a >> 8) & 0xFF, ab = ((int)a >> 16) & 0xFF;
   int br =  (int)b        & 0xFF, bg = ((int)b >> 8) & 0xFF, bb = ((int)b >> 16) & 0xFF;
   int r = (int)MathRound(ar + (br - ar) * t);
   int g = (int)MathRound(ag + (bg - ag) * t);
   int bl= (int)MathRound(ab + (bb - ab) * t);
   return((color)((bl << 16) | (g << 8) | r));
  }

//--- DPI-aware pixel size: every metric passes through this on creation
int AQ_Dpi(const int base)
  {
   static int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi <= 0) dpi = 96;
   return(base * dpi / 96);
  }

//--- price distance expressed in broker points
double AQ_ToPoints(const string sym, const double priceDistance)
  {
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(pt <= 0.0) return(0.0);
   return(priceDistance / pt);
  }

//--- short timeframe label, e.g. "H1" (no hand-written switch to drift)
string AQ_TfName(const ENUM_TIMEFRAMES tf)
  {
   ENUM_TIMEFRAMES t = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
   return(StringSubstr(EnumToString(t), 7));
  }

//--- standard timeframe ladder, used for automatic higher-timeframe selection
ENUM_TIMEFRAMES g_aqLadder[9] =
  {
   PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30,
   PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1
  };

//--- timeframe N rungs above 'base' (clamped at MN1) — keeps the system
//--- self-configuring on every chart period
ENUM_TIMEFRAMES AQ_HigherTf(const ENUM_TIMEFRAMES base, const int steps)
  {
   ENUM_TIMEFRAMES b = (base == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : base;
   int secs = PeriodSeconds(b);
   int idx  = 8;                                   // default: already at the top rung
   for(int i = 0; i < 9; i++)
      if(PeriodSeconds(g_aqLadder[i]) >= secs) { idx = i; break; }
   idx = AQ_Clamp(idx + steps, 0, 8);
   return(g_aqLadder[idx]);
  }

//--- trading session label from the server clock (informational only)
string AQ_SessionName()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(h >= 23 || h < 7)  return("ASIA");
   if(h < 12)            return("LONDON");
   if(h < 17)            return("LDN/NY");
   if(h < 21)            return("NEW YORK");
   return("LATE NY");
  }

//+------------------------------------------------------------------+
//| OBJECT NAMESPACE                                                 |
//| Instance-unique prefix: several copies of the system on one      |
//| chart (or on several charts) never collide, and cleanup stays    |
//| surgical.                                                        |
//+------------------------------------------------------------------+
string g_aqPrefix = "AQX_";

void AQ_InitPrefix(const string tag)
  {
   g_aqPrefix = "AQX" + (string)(ChartID() % 100000) + tag + "_";
  }

string AQ_Prefix()                      { return(g_aqPrefix); }
string AQ_N(const string id)            { return(g_aqPrefix + id); }
void   AQ_DeleteGroup(const string grp) { ObjectsDeleteAll(0, g_aqPrefix + grp, 0, -1); }
void   AQ_DeleteAll()                   { ObjectsDeleteAll(0, g_aqPrefix,      0, -1); }

//+------------------------------------------------------------------+
//| UI FACTORIES — pixel-anchored (dashboard)                        |
//| Create once, update many: every factory early-returns when the   |
//| object already exists.                                           |
//+------------------------------------------------------------------+
bool AQ_UiCreate(const string id, const ENUM_OBJECT type, string &outName, const ENUM_BASE_CORNER corner)
  {
   outName = AQ_N(id);
   if(ObjectFind(0, outName) >= 0) return(true);
   if(!ObjectCreate(0, outName, type, 0, 0, 0)) return(false);
   ObjectSetInteger(0, outName, OBJPROP_CORNER,     corner);
   ObjectSetInteger(0, outName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, outName, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, outName, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, outName, OBJPROP_BACK,       false);
   return(true);
  }

bool AQ_UiPanel(const string id, const int x, const int y, const int w, const int h,
                const color bg, const color border, const ENUM_BASE_CORNER corner)
  {
   string n;
   if(!AQ_UiCreate(id, OBJ_RECTANGLE_LABEL, n, corner)) return(false);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      0);
   return(true);
  }

bool AQ_UiLabel(const string id, const int x, const int y, const string text,
                const color clr, const int fs, const string font,
                const ENUM_ANCHOR_POINT anchor, const ENUM_BASE_CORNER corner)
  {
   string n;
   if(!AQ_UiCreate(id, OBJ_LABEL, n, corner)) return(false);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  fs);
   ObjectSetString (0, n, OBJPROP_FONT,      font);
   ObjectSetString (0, n, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,    5);
   return(true);
  }

bool AQ_UiButton(const string id, const int x, const int y, const int w, const int h,
                 const string text, const color bg, const color fg, const int fs,
                 const ENUM_BASE_CORNER corner)
  {
   string n;
   if(!AQ_UiCreate(id, OBJ_BUTTON, n, corner)) return(false);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, AQ_CLR_BORDER);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     fs);
   ObjectSetString (0, n, OBJPROP_FONT,         AQ_FONT);
   ObjectSetString (0, n, OBJPROP_TEXT,         text);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       10);
   ObjectSetInteger(0, n, OBJPROP_STATE,        false);
   return(true);
  }

//--- update helpers (never re-create)
void AQ_UiText(const string id, const string text)
  { ObjectSetString(0, AQ_N(id), OBJPROP_TEXT, text); }

void AQ_UiTextClr(const string id, const string text, const color clr)
  {
   string n = AQ_N(id);
   ObjectSetString (0, n, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
  }

void AQ_UiColor(const string id, const color clr)
  { ObjectSetInteger(0, AQ_N(id), OBJPROP_COLOR, clr); }

void AQ_UiBg(const string id, const color clr)
  { ObjectSetInteger(0, AQ_N(id), OBJPROP_BGCOLOR, clr); }

void AQ_UiSize(const string id, const int w, const int h)
  {
   string n = AQ_N(id);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
  }

void AQ_UiMove(const string id, const int x, const int y)
  {
   string n = AQ_N(id);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
  }

void AQ_UiButtonState(const string id, const bool on, const bool momentary)
  {
   string n = AQ_N(id);
   ObjectSetInteger(0, n, OBJPROP_STATE,   false);          // never leave a button stuck pressed
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, momentary ? AQ_CLR_BTN_ACT : (on ? AQ_CLR_BTN_ON : AQ_CLR_BTN_OFF));
   ObjectSetInteger(0, n, OBJPROP_COLOR,   momentary ? AQ_CLR_GOLD    : (on ? AQ_CLR_BTN_TXT_ON : AQ_CLR_BTN_TXT_OFF));
  }

//+------------------------------------------------------------------+
//| DRAWING FACTORIES — time/price anchored (market structures)      |
//+------------------------------------------------------------------+
bool AQ_DrawCreate(const string id, const ENUM_OBJECT type,
                   const datetime t1, const double p1, const datetime t2, const double p2,
                   const color clr, const int width, const ENUM_LINE_STYLE style,
                   const bool back, const bool fill)
  {
   string n = AQ_N(id);
   if(ObjectFind(0, n) < 0)
     {
      bool ok = (t2 == 0) ? ObjectCreate(0, n, type, 0, t1, p1)
                          : ObjectCreate(0, n, type, 0, t1, p1, t2, p2);
      if(!ok) return(false);
     }
   else
     {
      ObjectMove(0, n, 0, t1, p1);
      if(t2 != 0) ObjectMove(0, n, 1, t2, p2);
     }
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, n, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, n, OBJPROP_BACK,       back);
   ObjectSetInteger(0, n, OBJPROP_FILL,       fill);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   return(true);
  }

//--- filled zone box (supply/demand, fair value gap)
bool AQ_DrawZone(const string id, const datetime t1, const double pHi,
                 const datetime t2, const double pLo, const color clr,
                 const bool fill, const int width, const ENUM_LINE_STYLE style)
  { return(AQ_DrawCreate(id, OBJ_RECTANGLE, t1, pHi, t2, pLo, clr, width, style, true, fill)); }

//--- straight line between two bars, optionally a right-extending ray
bool AQ_DrawTrend(const string id, const datetime t1, const double p1,
                  const datetime t2, const double p2, const color clr,
                  const int width, const ENUM_LINE_STYLE style, const bool rayRight)
  {
   if(!AQ_DrawCreate(id, OBJ_TREND, t1, p1, t2, p2, clr, width, style, false, false)) return(false);
   ObjectSetInteger(0, AQ_N(id), OBJPROP_RAY_RIGHT, rayRight);
   return(true);
  }

//--- text glued to a bar
bool AQ_DrawText(const string id, const datetime t, const double price, const string text,
                 const color clr, const int fs, const ENUM_ANCHOR_POINT anchor, const string font)
  {
   if(!AQ_DrawCreate(id, OBJ_TEXT, t, price, 0, 0, clr, 1, STYLE_SOLID, false, false)) return(false);
   string n = AQ_N(id);
   ObjectSetString (0, n, OBJPROP_TEXT,     text);
   ObjectSetString (0, n, OBJPROP_FONT,     font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,   anchor);
   return(true);
  }

//--- fibonacci retracement between two swing points
bool AQ_DrawFibo(const string id, const datetime t1, const double p1,
                 const datetime t2, const double p2, const color clr,
                 const ENUM_LINE_STYLE style, const bool rayRight)
  {
   if(!AQ_DrawCreate(id, OBJ_FIBO, t1, p1, t2, p2, clr, 1, style, true, false)) return(false);
   string n = AQ_N(id);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, n, OBJPROP_RAY_LEFT,  false);
   int levels = (int)ObjectGetInteger(0, n, OBJPROP_LEVELS);
   for(int i = 0; i < levels; i++)
     {
      ObjectSetInteger(0, n, OBJPROP_LEVELCOLOR, i, clr);
      ObjectSetInteger(0, n, OBJPROP_LEVELSTYLE, i, STYLE_DOT);
      ObjectSetInteger(0, n, OBJPROP_LEVELWIDTH, i, 1);
     }
   return(true);
  }

#endif // AQ_CORE_MQH
//+------------------------------------------------------------------+
