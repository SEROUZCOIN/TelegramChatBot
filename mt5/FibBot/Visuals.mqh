//+------------------------------------------------------------------+
//|                                                      Visuals.mqh |
//|  UI: every ObjectCreate in this program lives in this file.      |
//|  Colours come only from the THEME block and sizes only from      |
//|  METRICS, both in Config.mqh.                                    |
//+------------------------------------------------------------------+
#ifndef FIBBOT_VISUALS_MQH
#define FIBBOT_VISUALS_MQH

#include "Config.mqh"
#include "Fib.mqh"

//--- factories -----------------------------------------------------

datetime VisualRightEdge()
  {
   return(iTime(_Symbol, _Period, 0) + (datetime)(PeriodSeconds(_Period) * 30));
  }

void MakeSegment(const string suffix, const datetime t1, const double p1,
                 const datetime t2, const double p2,
                 const color clr, const ENUM_LINE_STYLE style, const int width)
  {
   string name = OBJ_PREFIX + suffix;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

void MakeZone(const string suffix, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr)
  {
   string name = OBJ_PREFIX + suffix;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, METRIC_ZONE_W);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

void MakeLabel(const string suffix, const datetime t, const double p,
               const string text, const color clr)
  {
   string name = OBJ_PREFIX + suffix;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   else
      ObjectMove(0, name, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, METRIC_FONT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//--- drawing -------------------------------------------------------

void VisualsClear()
  {
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ChartRedraw();
  }

void VisualsDraw()
  {
   if(!InpShowVisuals || MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   if(g_setup.state == SETUP_IDLE)
     {
      VisualsClear();
      return;
     }

   color   dirColor = (g_setup.dir > 0) ? THEME_LONG : THEME_SHORT;
   datetime right   = VisualRightEdge();

   MakeSegment("leg", g_setup.anchorFromTime, g_setup.anchorFrom,
               g_setup.anchorToTime, g_setup.anchorTo,
               THEME_ANCHOR, STYLE_SOLID, METRIC_LINE_W);

   MakeZone("zone", g_setup.anchorToTime, g_setup.zoneNear, right, g_setup.zoneFar, THEME_ZONE);

   MakeSegment("stop", g_setup.anchorToTime, g_setup.stop, right, g_setup.stop,
               THEME_STOP, STYLE_DASH, METRIC_LINE_W);
   MakeSegment("tp1", g_setup.anchorToTime, g_setup.tp1, right, g_setup.tp1,
               THEME_TARGET, STYLE_DOT, METRIC_LINE_W);
   MakeSegment("tp2", g_setup.anchorToTime, g_setup.tp2, right, g_setup.tp2,
               THEME_TARGET, STYLE_DOT, METRIC_LINE_W);
   MakeSegment("tp3", g_setup.anchorToTime, g_setup.tp3, right, g_setup.tp3,
               THEME_TARGET, STYLE_DOT, METRIC_LINE_W);

   string state = EnumToString(g_setup.state);
   StringReplace(state, "SETUP_", "");
   string caption = StringFormat("%s %s  %.1f-%.1f%%  confluence %d",
                                 (g_setup.dir > 0 ? "LONG" : "SHORT"), state,
                                 InpEntryFibNear * 100.0, InpEntryFibFar * 100.0,
                                 g_setup.confluence);

   datetime labelTime = g_setup.anchorToTime + (datetime)(PeriodSeconds(_Period) * METRIC_LABEL_SHIFT);
   MakeLabel("caption", labelTime, g_setup.zoneNear, caption, dirColor);
   MakeLabel("legend", labelTime, g_setup.stop, "stop", THEME_TEXT);

   ChartRedraw();
  }

#endif // FIBBOT_VISUALS_MQH
//+------------------------------------------------------------------+
