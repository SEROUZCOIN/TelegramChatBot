//+------------------------------------------------------------------+
//|                                                     NGZ_Draw.mqh |
//|           Neuro Gann Zones - chart drawing (price/time space)      |
//|                                                                   |
//|  Everything here lives in TIME/PRICE coordinates and therefore    |
//|  stays glued to the candles. Screen-anchored widgets belong to    |
//|  NGZ_Panel.mqh instead - the two systems are never mixed.         |
//+------------------------------------------------------------------+
#ifndef __NGZ_DRAW_MQH__
#define __NGZ_DRAW_MQH__

#include "NGZ_Config.mqh"
#include "NGZ_State.mqh"
#include "NGZ_Math.mqh"
#include "NGZ_Gann.mqh"

//--- object categories (sub prefixes) so a group can be refreshed alone
#define NGZ_CAT_FAN   "FAN_"
#define NGZ_CAT_SQ9   "SQ9_"
#define NGZ_CAT_DIV   "DIV_"
#define NGZ_CAT_CYC   "CYC_"
#define NGZ_CAT_ZONE  "ZON_"
#define NGZ_CAT_ANC   "ANC_"

//+------------------------------------------------------------------+
//| Short timeframe name ("H1" instead of "PERIOD_H1")                |
//+------------------------------------------------------------------+
string NgzTfName(void)
  {
   string s = EnumToString(_Period);
   int    p = StringFind(s, "PERIOD_");
   return (p == 0) ? StringSubstr(s, 7) : s;
  }

//+------------------------------------------------------------------+
//| Instance-unique object prefix: several charts never collide       |
//+------------------------------------------------------------------+
string NgzPrefix(void)
  {
   if(StringLen(g_s.prefix) == 0)
      g_s.prefix = "NGZ" + IntegerToString((int)ChartID() % 100000) + "_";
   return g_s.prefix;
  }

//+------------------------------------------------------------------+
//| Generic object creators - one per anchor-point count              |
//+------------------------------------------------------------------+
bool NgzObj1(const string id, const ENUM_OBJECT type, const datetime t1, const double p1)
  {
   string n = NgzPrefix() + id;
   if(ObjectFind(0, n) < 0)
     {
      if(!ObjectCreate(0, n, type, 0, t1, p1)) return false;
     }
   else
      ObjectMove(0, n, 0, t1, p1);
   return true;
  }

bool NgzObj2(const string id, const ENUM_OBJECT type,
             const datetime t1, const double p1, const datetime t2, const double p2)
  {
   string n = NgzPrefix() + id;
   if(ObjectFind(0, n) < 0)
     {
      if(!ObjectCreate(0, n, type, 0, t1, p1, t2, p2)) return false;
     }
   else
     {
      ObjectMove(0, n, 0, t1, p1);
      ObjectMove(0, n, 1, t2, p2);
     }
   return true;
  }

bool NgzObj3(const string id, const ENUM_OBJECT type,
             const datetime t1, const double p1, const datetime t2, const double p2,
             const datetime t3, const double p3)
  {
   string n = NgzPrefix() + id;
   if(ObjectFind(0, n) < 0)
     {
      if(!ObjectCreate(0, n, type, 0, t1, p1, t2, p2, t3, p3)) return false;
     }
   else
     {
      ObjectMove(0, n, 0, t1, p1);
      ObjectMove(0, n, 1, t2, p2);
      ObjectMove(0, n, 2, t3, p3);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Common styling applied to every drawn object                      |
//+------------------------------------------------------------------+
void NgzObjStyle(const string id, const color clr, const int width = 1,
                 const ENUM_LINE_STYLE style = STYLE_SOLID,
                 const bool back = false, const bool fill = false)
  {
   string n = NgzPrefix() + id;
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, n, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, n, OBJPROP_BACK,       back);
   ObjectSetInteger(0, n, OBJPROP_FILL,       fill);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,     0);
  }

//+------------------------------------------------------------------+
//| Text label glued to a bar                                         |
//+------------------------------------------------------------------+
void NgzObjText(const string id, const datetime t, const double p, const string text,
                const color clr, const int fontSize = NGZ_UI_FS,
                const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT)
  {
   if(!NgzObj1(id, OBJ_TEXT, t, p)) return;
   string n = NgzPrefix() + id;
   ObjectSetString (0, n, OBJPROP_TEXT,       text);
   ObjectSetString (0, n, OBJPROP_FONT,       NGZ_UI_FONT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,     anchor);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
  }

//+------------------------------------------------------------------+
//| Delete a whole category (called before each refresh of it)        |
//+------------------------------------------------------------------+
void NgzClearCategory(const string cat)
  {
   ObjectsDeleteAll(0, NgzPrefix() + cat);
  }

//+------------------------------------------------------------------+
//| Future bar time, N bars to the right of the last bar              |
//+------------------------------------------------------------------+
datetime NgzTimeAhead(const datetime lastBarTime, const int bars)
  {
   return lastBarTime + (datetime)((long)PeriodSeconds(_Period) * (long)bars);
  }

//+------------------------------------------------------------------+
//| 1. GANN FAN - nine rays from an anchor                            |
//+------------------------------------------------------------------+
void NgzDrawFan(const NgzAnchor &a, const string tag, const datetime lastBarTime)
  {
   if(!a.valid) return;
   double unit = NgzAnchorUnit(a);
   if(unit <= 0.0) return;

   int      len  = NgzIMax(20, InpFanLength);
   datetime tEnd = NgzTimeAhead(a.time, len);
   datetime tMin = NgzTimeAhead(lastBarTime, NgzIMax(5, InpProjectBars));
   if(tEnd < tMin)                                   // an old anchor still has to
     {                                               // reach the live price area
      tEnd = tMin;
      len  = (int)(((long)tEnd - (long)a.time) / (long)PeriodSeconds(_Period));
     }

   for(int k = 0; k < NGZ_FAN_COUNT; k++)
     {
      string id  = NGZ_CAT_FAN + tag + "R" + IntegerToString(k);
      double end = NgzFanValueAhead(a, unit, g_fanRatio[k], len);

      if(!NgzObj2(id, OBJ_TREND, a.time, a.price, tEnd, end)) continue;

      bool  main = (MathAbs(g_fanRatio[k] - 1.0) < 1.0e-9);   // the 1x1 ray
      color clr  = main ? NGZ_CLR_FAN_MAIN : NGZ_CLR_FAN_SUB;
      NgzObjStyle(id, clr, main ? 2 : 1,
                  (ENUM_LINE_STYLE)(main ? STYLE_SOLID : STYLE_DOT), true, false);
      ObjectSetInteger(0, NgzPrefix() + id, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, NgzPrefix() + id, OBJPROP_RAY_LEFT,  false);

      if(InpShowFanLabels)
         NgzObjText(NGZ_CAT_FAN + tag + "L" + IntegerToString(k), tEnd, end,
                    " " + g_fanName[k] + " (" + DoubleToString(NgzFanAngle(g_fanRatio[k]), 1) + ")",
                    main ? NGZ_CLR_GOLD : NGZ_CLR_TEXT_DIM, NGZ_UI_FS, ANCHOR_LEFT);
     }

   //--- anchor marker
   string aid = NGZ_CAT_ANC + tag;
   if(NgzObj1(aid, OBJ_ARROW, a.time, a.price))
     {
      string n = NgzPrefix() + aid;
      ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 159);              // filled dot
      ObjectSetInteger(0, n, OBJPROP_COLOR, a.isLow ? NGZ_CLR_UP : NGZ_CLR_DOWN);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_TOP);   // ENUM_ARROW_ANCHOR
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   NgzObjText(NGZ_CAT_ANC + tag + "T", a.time, a.price,
              a.isLow ? "GANN LOW" : "GANN HIGH",
              a.isLow ? NGZ_CLR_UP : NGZ_CLR_DOWN, NGZ_UI_FS,
              (ENUM_ANCHOR_POINT)(a.isLow ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER));
  }

//+------------------------------------------------------------------+
//| 2. GANN FAN ZONES - the bands between key rays, drawn as filled   |
//|    triangles (a band between two rays sharing one origin IS a     |
//|    triangle, so no rectangle approximation is needed).            |
//+------------------------------------------------------------------+
void NgzDrawFanZones(const NgzAnchor &a, const string tag, const datetime lastBarTime)
  {
   if(!a.valid) return;
   double unit = NgzAnchorUnit(a);
   if(unit <= 0.0) return;

   int      len  = NgzIMax(20, InpFanLength);
   datetime tEnd = NgzTimeAhead(a.time, len);
   datetime tMin = NgzTimeAhead(lastBarTime, NgzIMax(5, InpProjectBars));
   if(tEnd < tMin)
     {
      tEnd = tMin;
      len  = (int)(((long)tEnd - (long)a.time) / (long)PeriodSeconds(_Period));
     }

   //--- POWER zone: between 1x1 and 2x1 - trend acceleration area
   double p1x1 = NgzFanValueAhead(a, unit, 1.0, len);
   double p2x1 = NgzFanValueAhead(a, unit, 2.0, len);
   string idP  = NGZ_CAT_ZONE + tag + "POWER";
   if(NgzObj3(idP, OBJ_TRIANGLE, a.time, a.price, tEnd, p1x1, tEnd, p2x1))
      NgzObjStyle(idP, a.isLow ? NGZ_CLR_ZONE_UP : NGZ_CLR_ZONE_DOWN, 1, STYLE_SOLID, true, true);

   //--- BALANCE zone: between 1x2 and 1x1 - the healthy trend channel
   double p1x2 = NgzFanValueAhead(a, unit, 0.5, len);
   string idB  = NGZ_CAT_ZONE + tag + "BAL";
   if(NgzObj3(idB, OBJ_TRIANGLE, a.time, a.price, tEnd, p1x2, tEnd, p1x1))
      NgzObjStyle(idB, a.isLow ? NGZ_CLR_ZONE_DISC : NGZ_CLR_ZONE_PREM, 1, STYLE_SOLID, true, true);
  }

//+------------------------------------------------------------------+
//| 3. SQUARE OF NINE levels                                          |
//+------------------------------------------------------------------+
void NgzDrawSq9(const double anchorPrice, const datetime tStart, const datetime tEnd)
  {
   if(anchorPrice <= 0.0) return;
   int n = NgzIMin(InpSq9Levels, NGZ_SQ9_MAX);

   for(int k = -n; k <= n; k++)
     {
      double deg = InpSq9Step * (double)k;
      double lvl = NgzSq9Level(anchorPrice, deg);
      if(lvl <= 0.0) continue;

      string id = NGZ_CAT_SQ9 + "L" + IntegerToString(k + n);
      if(!NgzObj2(id, OBJ_TREND, tStart, lvl, tEnd, lvl)) continue;

      bool cardinal = (MathMod(MathAbs(deg), 90.0) < 1.0e-6);   // 90/180/270/360
      NgzObjStyle(id, NGZ_CLR_SQ9, cardinal ? 2 : 1,
                  (ENUM_LINE_STYLE)(cardinal ? STYLE_SOLID : STYLE_DOT), true, false);
      ObjectSetInteger(0, NgzPrefix() + id, OBJPROP_RAY_RIGHT, true);

      NgzObjText(NGZ_CAT_SQ9 + "T" + IntegerToString(k + n), tEnd, lvl,
                 " SQ9 " + (k >= 0 ? "+" : "") + DoubleToString(deg, 0) + " " +
                 DoubleToString(lvl, _Digits),
                 NGZ_CLR_SQ9, NGZ_UI_FS, ANCHOR_LEFT);
     }
  }

//+------------------------------------------------------------------+
//| 4. GANN DIVISIONS - eighths and thirds of the master swing        |
//+------------------------------------------------------------------+
void NgzDrawDivisions(const double lo, const double hi, const datetime tStart, const datetime tEnd)
  {
   if(hi - lo <= 1.0e-12) return;

   for(int k = 0; k < NGZ_DIV_COUNT; k++)
     {
      double lvl = NgzDivisionLevel(lo, hi, g_divRatio[k], true);
      string id  = NGZ_CAT_DIV + "L" + IntegerToString(k);
      if(!NgzObj2(id, OBJ_TREND, tStart, lvl, tEnd, lvl)) continue;

      bool key = (MathAbs(g_divRatio[k] - 0.5) < 1.0e-9);       // the 50% pivot
      NgzObjStyle(id, key ? NGZ_CLR_GOLD : NGZ_CLR_FIB, key ? 2 : 1,
                  (ENUM_LINE_STYLE)(key ? STYLE_SOLID : STYLE_DOT), true, false);

      NgzObjText(NGZ_CAT_DIV + "T" + IntegerToString(k), tEnd, lvl,
                 " " + g_divName[k] + "  " + DoubleToString(lvl, _Digits),
                 key ? NGZ_CLR_GOLD : NGZ_CLR_FIB, NGZ_UI_FS, ANCHOR_LEFT);
     }

   //--- the range boundaries themselves
   string idHi = NGZ_CAT_DIV + "HI";
   if(NgzObj2(idHi, OBJ_TREND, tStart, hi, tEnd, hi))
      NgzObjStyle(idHi, NGZ_CLR_DOWN, 1, STYLE_DASH, true, false);
   string idLo = NGZ_CAT_DIV + "LO";
   if(NgzObj2(idLo, OBJ_TREND, tStart, lo, tEnd, lo))
      NgzObjStyle(idLo, NGZ_CLR_UP, 1, STYLE_DASH, true, false);
  }

//+------------------------------------------------------------------+
//| 5. PREMIUM / DISCOUNT / EQUILIBRIUM zones of the master swing     |
//+------------------------------------------------------------------+
void NgzDrawPremiumDiscount(const double lo, const double hi,
                            const datetime tStart, const datetime tEnd)
  {
   if(hi - lo <= 1.0e-12) return;
   double eq = (hi + lo) * 0.5;

   string idP = NGZ_CAT_ZONE + "PREM";
   if(NgzObj2(idP, OBJ_RECTANGLE, tStart, hi, tEnd, eq))
      NgzObjStyle(idP, NGZ_CLR_ZONE_PREM, 1, STYLE_SOLID, true, true);

   string idD = NGZ_CAT_ZONE + "DISC";
   if(NgzObj2(idD, OBJ_RECTANGLE, tStart, eq, tEnd, lo))
      NgzObjStyle(idD, NGZ_CLR_ZONE_DISC, 1, STYLE_SOLID, true, true);

   string idE = NGZ_CAT_ZONE + "EQ";
   if(NgzObj2(idE, OBJ_TREND, tStart, eq, tEnd, eq))
     {
      NgzObjStyle(idE, NGZ_CLR_NEON, 1, STYLE_DASHDOT, true, false);
      ObjectSetInteger(0, NgzPrefix() + idE, OBJPROP_RAY_RIGHT, true);
     }

   NgzObjText(NGZ_CAT_ZONE + "EQT", tEnd, eq, " EQUILIBRIUM " + DoubleToString(eq, _Digits),
              NGZ_CLR_NEON, NGZ_UI_FS, ANCHOR_LEFT);
  }

//+------------------------------------------------------------------+
//| 6. GANN TIME CYCLES - vertical lines plus tolerance bands         |
//+------------------------------------------------------------------+
void NgzDrawCycles(const NgzAnchor &a, const double lo, const double hi, const int maxAhead)
  {
   if(!a.valid || g_cycleCount <= 0) return;

   double pad  = (hi - lo) * 0.15;
   double top  = hi + pad;
   double bot  = lo - pad;
   int    band = NgzIMax(0, InpCycleBand);
   int    slot = 0;

   for(int k = 0; k < g_cycleCount; k++)
     {
      int len = g_cycles[k];
      if(len <= 0) continue;

      for(int m = 1; m * len <= maxAhead && slot < NGZ_CYCLE_DRAW_MAX; m++)
        {
         int      bars = m * len;
         datetime tc   = NgzTimeAhead(a.time, bars);
         string   sid  = IntegerToString(slot);
         slot++;

         //--- tolerance band around the cycle date
         if(band > 0)
           {
            string idB = NGZ_CAT_CYC + "B" + sid;
            if(NgzObj2(idB, OBJ_RECTANGLE,
                       NgzTimeAhead(a.time, bars - band), top,
                       NgzTimeAhead(a.time, bars + band), bot))
               NgzObjStyle(idB, NGZ_CLR_ZONE_CYCLE, 1, STYLE_SOLID, true, true);
           }

         string idV = NGZ_CAT_CYC + "V" + sid;
         if(NgzObj1(idV, OBJ_VLINE, tc, 0.0))
            NgzObjStyle(idV, NGZ_CLR_GOLD, 1, STYLE_DOT, true, false);

         NgzObjText(NGZ_CAT_CYC + "T" + sid, tc, top,
                    "C" + IntegerToString(len) + (m > 1 ? "x" + IntegerToString(m) : ""),
                    NGZ_CLR_GOLD, NGZ_UI_FS, ANCHOR_LEFT_LOWER);
        }
     }
  }

//+------------------------------------------------------------------+
//| 7. CONFLUENCE ZONES - where a Square of 9 level meets a fan ray   |
//|    These are the highest quality Gann levels: price and time      |
//|    geometry agree on the same number.                             |
//+------------------------------------------------------------------+
void NgzDrawConfluence(const NgzAnchor &a, const double anchorPrice, const int lastBar,
                       const datetime lastBarTime, const double atrNow)
  {
   if(!a.valid || anchorPrice <= 0.0 || atrNow <= 0.0) return;

   double unit = NgzAnchorUnit(a);
   if(unit <= 0.0) return;

   double tol   = atrNow * InpConfluenceATR;
   int    ahead = NgzIMax(5, InpProjectBars);
   int    bar   = lastBar + ahead;
   int    found = 0;
   int    n     = NgzIMin(InpSq9Levels, NGZ_SQ9_MAX);

   for(int f = 0; f < NGZ_FAN_COUNT && found < 6; f++)
     {
      double rayNow = NgzFanValueAhead(a, unit, g_fanRatio[f], bar - a.bar);

      for(int k = -n; k <= n && found < 6; k++)
        {
         double lvl = NgzSq9Level(anchorPrice, InpSq9Step * (double)k);
         if(lvl <= 0.0) continue;
         if(MathAbs(lvl - rayNow) > tol) continue;

         string id = NGZ_CAT_ZONE + "CONF" + IntegerToString(found);
         if(NgzObj2(id, OBJ_RECTANGLE,
                    NgzTimeAhead(lastBarTime, ahead - 6), lvl + tol * 0.5,
                    NgzTimeAhead(lastBarTime, ahead + 6), lvl - tol * 0.5))
            NgzObjStyle(id, NGZ_CLR_CONFLUENCE, 1, STYLE_SOLID, true, true);

         NgzObjText(NGZ_CAT_ZONE + "CONFT" + IntegerToString(found),
                    NgzTimeAhead(lastBarTime, ahead + 6), lvl,
                    " CONFLUENCE " + g_fanName[f] + " x SQ9 " + DoubleToString(lvl, _Digits),
                    NGZ_CLR_CONFLUENCE, NGZ_UI_FS, ANCHOR_LEFT);
         found++;
        }
     }
  }

//+------------------------------------------------------------------+
//| 8. PROJECTION ZONE - where the fused score points next            |
//+------------------------------------------------------------------+
void NgzDrawProjection(const datetime lastBarTime, const double lastClose,
                       const double fused, const double unit)
  {
   if(unit <= 0.0) return;

   int      ahead = NgzIMax(5, InpProjectBars);
   datetime t2    = NgzTimeAhead(lastBarTime, ahead);
   double   move  = fused * unit * (double)ahead;      // score scaled by Gann travel
   double   target= lastClose + move;

   string id = NGZ_CAT_ZONE + "PROJ";
   if(NgzObj2(id, OBJ_RECTANGLE, lastBarTime, lastClose, t2, target))
      NgzObjStyle(id, (fused >= 0.0) ? NGZ_CLR_ZONE_UP : NGZ_CLR_ZONE_DOWN,
                  1, STYLE_SOLID, true, true);

   string idL = NGZ_CAT_ZONE + "PROJL";
   if(NgzObj2(idL, OBJ_TREND, lastBarTime, lastClose, t2, target))
      NgzObjStyle(idL, (fused >= 0.0) ? NGZ_CLR_UP : NGZ_CLR_DOWN, 2, STYLE_DASH, false, false);

   NgzObjText(NGZ_CAT_ZONE + "PROJT", t2, target,
              (fused >= 0.0 ? " TARGET UP " : " TARGET DOWN ") + DoubleToString(target, _Digits),
              (fused >= 0.0) ? NGZ_CLR_UP : NGZ_CLR_DOWN, NGZ_UI_FS, ANCHOR_LEFT);
  }

#endif // __NGZ_DRAW_MQH__
//+------------------------------------------------------------------+
