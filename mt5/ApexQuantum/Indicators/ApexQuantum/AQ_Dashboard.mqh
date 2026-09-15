//+------------------------------------------------------------------+
//|                                                 AQ_Dashboard.mqh |
//|       APEX QUANTUM — animated, clickable control dashboard       |
//|                                                                  |
//|  Screen-anchored pixel UI (never moves with price). Everything   |
//|  is built through the AQ_Ui* factories, every colour comes from  |
//|  THEME and every dimension from METRICS.                         |
//|                                                                  |
//|  Animation runs off the millisecond timer and touches only four  |
//|  objects per frame: the status pulse, the header sweep, the      |
//|  eased score gauge and the bias glow — so it stays smooth        |
//|  without burning CPU on a chart full of zones.                   |
//+------------------------------------------------------------------+
#ifndef AQ_DASHBOARD_MQH
#define AQ_DASHBOARD_MQH

#include "AQ_Core.mqh"

//--- toggleable modules
#define AQ_MOD_ZONES    0
#define AQ_MOD_TREND    1
#define AQ_MOD_CHAN     2
#define AQ_MOD_ZZ       3
#define AQ_MOD_FVG      4
#define AQ_MOD_ARROW    5
#define AQ_MOD_ALERT    6
#define AQ_MOD_COUNT    7

//--- click actions returned to the host program
#define AQ_ACT_NONE     0
#define AQ_ACT_TOGGLE   1
#define AQ_ACT_TF       2
#define AQ_ACT_RESCAN   3
#define AQ_ACT_COLLAPSE 4

//+------------------------------------------------------------------+
//| Everything the panel displays, filled once per calculation       |
//+------------------------------------------------------------------+
struct AQDashData
  {
   string            symbol;
   string            tf;
   int               bias;            // +1 bullish, -1 bearish, 0 flat
   int               score;           // -100 .. +100
   int               trend;           // primary rail
   int               structDir;       // last BOS / CHoCH direction
   string            eventName;
   int               chanSlope;
   double            chanPos;
   int               mtf1, mtf2;
   string            mtf1Name, mtf2Name;
   bool              hasDemand, hasSupply;
   double            demTop, demBot, supTop, supBot;
   string            demGrade, supGrade;
   int               zoneCount;
   double            atrPts, spreadPts;
   string            session;
   int               lastSignal;
   string            lastSignalAt;
   bool              engineOk;
  };

//+------------------------------------------------------------------+
//| CAQDashboard                                                     |
//+------------------------------------------------------------------+
class CAQDashboard
  {
private:
   bool              m_mod[AQ_MOD_COUNT];
   bool              m_created;
   bool              m_collapsed;
   int               m_corner;        // ENUM_AQ_CORNER
   int               m_offX, m_offY;  // requested offset from that corner
   int               m_x, m_y, m_w;   // resolved origin (always CORNER_LEFT_UPPER)
   int               m_h;
   int               m_phase;
   double            m_gaugeShown;
   int               m_gaugeTarget;
   int               m_gaugeX, m_gaugeY, m_gaugeW;
   int               m_sweepY;
   AQDashData        m_d;

   int               CalcHeight(void) const;
   void              ComputeOrigin(void);
   void              BuildHeader(int &y);
   void              BuildBody(int &y);
   string            Fmt(const double price) const { return(DoubleToString(price, _Digits)); }
   string            ArrowGlyph(const int dir) const;
   color             DirColor(const int dir) const;

public:
                     CAQDashboard(void);
   void              Configure(const int corner, const int offX, const int offY);
   void              Create(void);
   void              Destroy(void) { AQ_DeleteGroup("D"); m_created = false; }
   void              Rebuild(void) { Destroy(); Create(); }
   bool              Created(void) const { return(m_created); }
   void              Update(const AQDashData &d);
   void              Animate(void);
   int               OnClick(const string name, int &param);
   bool              Enabled(const int mod) const { return(mod >= 0 && mod < AQ_MOD_COUNT ? m_mod[mod] : false); }
   void              SetEnabled(const int mod, const bool v) { if(mod >= 0 && mod < AQ_MOD_COUNT) m_mod[mod] = v; }
  };

//+------------------------------------------------------------------+
CAQDashboard::CAQDashboard(void) : m_created(false), m_collapsed(false), m_corner(0),
                                   m_offX(12), m_offY(20), m_x(12), m_y(20),
                                   m_w(AQ_PANEL_W), m_h(0), m_phase(0),
                                   m_gaugeShown(0.0), m_gaugeTarget(0),
                                   m_gaugeX(0), m_gaugeY(0), m_gaugeW(0), m_sweepY(0)
  {
   for(int i = 0; i < AQ_MOD_COUNT; i++) m_mod[i] = true;
  }

void CAQDashboard::Configure(const int corner, const int offX, const int offY)
  {
   m_corner = corner;
   m_offX   = offX;
   m_offY   = offY;
  }

string CAQDashboard::ArrowGlyph(const int dir) const
  {
   if(dir > 0) return(CharToString((uchar)AQ_GLYPH_UP));
   if(dir < 0) return(CharToString((uchar)AQ_GLYPH_DN));
   return(CharToString((uchar)AQ_GLYPH_DOT));
  }

color CAQDashboard::DirColor(const int dir) const
  {
   if(dir > 0) return(AQ_CLR_BULL);
   if(dir < 0) return(AQ_CLR_BEAR);
   return(AQ_CLR_FLAT);
  }

//--- panel height, derived from the same metrics BuildBody() lays out with.
//--- Needed BEFORE construction so a bottom-anchored panel lands correctly on
//--- its very first build (the drawn panel is still sized from the real cursor).
int CAQDashboard::CalcHeight(void) const
  {
   int pad = AQ_Dpi(AQ_PAD), row = AQ_Dpi(AQ_ROW_H);
   int bh  = AQ_Dpi(AQ_BTN_H), gap = AQ_Dpi(AQ_BTN_GAP);
   int h   = AQ_Dpi(AQ_HDR_H);
   if(m_collapsed) return(h + pad);
   h += AQ_Dpi(4) + AQ_Dpi(AQ_ROW_BIG);                 // bias headline
   h += AQ_Dpi(AQ_GAUGE_H) + AQ_Dpi(6);                 // gauge
   h += row * 6;                                        // info rows
   h += AQ_Dpi(2) + AQ_Dpi(AQ_SEP_H) + AQ_Dpi(6);       // separator
   h += bh * 2 + gap * 2 + AQ_Dpi(4);                   // toggle rows
   h += bh;                                             // timeframe row
   return(h + pad);
  }

//--- the panel is always laid out left-to-right from a resolved origin, so the
//--- four anchor corners share one code path
void CAQDashboard::ComputeOrigin(void)
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   m_w = AQ_Dpi(AQ_PANEL_W);
   int h = CalcHeight();

   m_x = (m_corner == AQ_CORNER_TR || m_corner == AQ_CORNER_BR)
       ? (int)MathMax(2, cw - m_w - m_offX) : m_offX;
   m_y = (m_corner == AQ_CORNER_BL || m_corner == AQ_CORNER_BR)
       ? (int)MathMax(2, ch - h - m_offY) : m_offY;
  }

//+------------------------------------------------------------------+
//| Construction                                                     |
//+------------------------------------------------------------------+
void CAQDashboard::Create(void)
  {
   ComputeOrigin();
   int pad = AQ_Dpi(AQ_PAD);
   int y   = m_y;

   //--- background (sized for real once the layout is known)
   AQ_UiPanel("DP", m_x, m_y, m_w, CalcHeight(), AQ_CLR_BG, AQ_CLR_BORDER, CORNER_LEFT_UPPER);

   BuildHeader(y);
   if(!m_collapsed) BuildBody(y);

   m_h = y - m_y + pad;
   AQ_UiSize("DP", m_w, m_h);
   m_created = true;
   ChartRedraw(0);
  }

void CAQDashboard::BuildHeader(int &y)
  {
   int pad  = AQ_Dpi(AQ_PAD);
   int hdrH = AQ_Dpi(AQ_HDR_H);
   int dot  = AQ_Dpi(AQ_DOT_W);

   AQ_UiPanel("DHBAR", m_x, y, m_w, hdrH, AQ_CLR_HEADER, AQ_CLR_BORDER, CORNER_LEFT_UPPER);

   m_dotX = m_x + pad;
   m_dotY = y + (hdrH - dot) / 2;
   AQ_UiPanel("DHDOT", m_dotX, m_dotY, dot, dot, AQ_CLR_NEON, AQ_CLR_NEON, CORNER_LEFT_UPPER);

   AQ_UiLabel("DHTITLE", m_x + pad + dot + AQ_Dpi(7), y + AQ_Dpi(7), "APEX QUANTUM",
              AQ_CLR_NEON, AQ_FS_TITLE, AQ_FONT, ANCHOR_LEFT_UPPER, CORNER_LEFT_UPPER);

   AQ_UiLabel("DHSYM", m_x + m_w - pad - AQ_Dpi(20), y + AQ_Dpi(8), "",
              AQ_CLR_TEXT_DIM, AQ_FS_SM, AQ_FONT, ANCHOR_RIGHT_UPPER, CORNER_LEFT_UPPER);

   //--- collapse / expand
   AQ_UiButton("DHCOL", m_x + m_w - pad - AQ_Dpi(16), y + AQ_Dpi(6), AQ_Dpi(16), AQ_Dpi(15),
               m_collapsed ? "+" : "-", AQ_CLR_BTN_OFF, AQ_CLR_TEXT_DIM, AQ_FS_SM, CORNER_LEFT_UPPER);

   //--- animated scan sweep along the header base line
   m_sweepY = y + hdrH - AQ_Dpi(2);
   AQ_UiPanel("DHSWEEP", m_x + pad, m_sweepY, AQ_Dpi(AQ_SWEEP_W), AQ_Dpi(2),
              AQ_CLR_GOLD, AQ_CLR_GOLD, CORNER_LEFT_UPPER);

   y += hdrH;
  }

void CAQDashboard::BuildBody(int &y)
  {
   int pad  = AQ_Dpi(AQ_PAD);
   int row  = AQ_Dpi(AQ_ROW_H);
   int xl   = m_x + pad;                          // left text column
   int xr   = m_x + m_w - pad;                    // right text column
   int innerW = m_w - pad * 2;

   //--- bias headline -------------------------------------------------
   y += AQ_Dpi(4);
   AQ_UiLabel("DBBIASG", xl, y + AQ_Dpi(3), ArrowGlyph(0), AQ_CLR_FLAT, AQ_FS_BIG,
              AQ_FONT_ICON, ANCHOR_LEFT_UPPER, CORNER_LEFT_UPPER);
   AQ_UiLabel("DBBIAS", xl + AQ_Dpi(20), y + AQ_Dpi(2), "SCANNING", AQ_CLR_TEXT, AQ_FS_BIG,
              AQ_FONT, ANCHOR_LEFT_UPPER, CORNER_LEFT_UPPER);
   AQ_UiLabel("DBSCORE", xr, y + AQ_Dpi(3), "0", AQ_CLR_TEXT, AQ_FS_BIG,
              AQ_FONT_MONO, ANCHOR_RIGHT_UPPER, CORNER_LEFT_UPPER);
   y += AQ_Dpi(AQ_ROW_BIG);

   //--- score gauge ---------------------------------------------------
   m_gaugeX = xl;
   m_gaugeY = y;
   m_gaugeW = innerW;
   AQ_UiPanel("DBGTRACK", m_gaugeX, m_gaugeY, m_gaugeW, AQ_Dpi(AQ_GAUGE_H),
              AQ_CLR_TRACK, AQ_CLR_BORDER, CORNER_LEFT_UPPER);
   AQ_UiPanel("DBGFILL", m_gaugeX + m_gaugeW / 2, m_gaugeY + 1, 1, AQ_Dpi(AQ_GAUGE_H) - 2,
              AQ_CLR_NEON, AQ_CLR_NEON, CORNER_LEFT_UPPER);
   AQ_UiPanel("DBGMID", m_gaugeX + m_gaugeW / 2, m_gaugeY, 1, AQ_Dpi(AQ_GAUGE_H),
              AQ_CLR_TEXT_MUTE, AQ_CLR_TEXT_MUTE, CORNER_LEFT_UPPER);
   y += AQ_Dpi(AQ_GAUGE_H) + AQ_Dpi(6);

   //--- information rows ----------------------------------------------
   string caps[6] = {"MTF", "STRUCTURE", "DEMAND", "SUPPLY", "MARKET", "LAST SIGNAL"};
   for(int i = 0; i < 6; i++)
     {
      AQ_UiLabel("DBC" + (string)i, xl, y, caps[i], AQ_CLR_TEXT_DIM, AQ_FS_SM,
                 AQ_FONT, ANCHOR_LEFT_UPPER, CORNER_LEFT_UPPER);
      AQ_UiLabel("DBV" + (string)i, xr, y, "--", AQ_CLR_TEXT, AQ_FS,
                 AQ_FONT, ANCHOR_RIGHT_UPPER, CORNER_LEFT_UPPER);
      y += row;
     }

   //--- separator ------------------------------------------------------
   y += AQ_Dpi(2);
   AQ_UiPanel("DBSEP", xl, y, innerW, AQ_Dpi(AQ_SEP_H), AQ_CLR_BORDER, AQ_CLR_BORDER, CORNER_LEFT_UPPER);
   y += AQ_Dpi(6);

   //--- module toggles (two rows of four) -------------------------------
   string mods[7] = {"ZONES", "TREND", "CHAN", "SWING", "FVG", "ARROWS", "ALERT"};
   int bw  = (innerW - AQ_Dpi(AQ_BTN_GAP) * 3) / 4;
   int bh  = AQ_Dpi(AQ_BTN_H);
   for(int i = 0; i < AQ_MOD_COUNT; i++)
     {
      int bx = xl + (i % 4) * (bw + AQ_Dpi(AQ_BTN_GAP));
      int by = y  + (i / 4) * (bh + AQ_Dpi(AQ_BTN_GAP));
      AQ_UiButton("DBM" + (string)i, bx, by, bw, bh, mods[i],
                  m_mod[i] ? AQ_CLR_BTN_ON      : AQ_CLR_BTN_OFF,
                  m_mod[i] ? AQ_CLR_BTN_TXT_ON  : AQ_CLR_BTN_TXT_OFF,
                  AQ_FS_SM, CORNER_LEFT_UPPER);
     }
   //--- eighth slot: momentary "force a full rescan" action
   AQ_UiButton("DBRS", xl + 3 * (bw + AQ_Dpi(AQ_BTN_GAP)), y + bh + AQ_Dpi(AQ_BTN_GAP),
               bw, bh, "RESCAN", AQ_CLR_BTN_ACT, AQ_CLR_GOLD, AQ_FS_SM, CORNER_LEFT_UPPER);
   y += bh * 2 + AQ_Dpi(AQ_BTN_GAP) * 2 + AQ_Dpi(4);

   //--- timeframe switcher ---------------------------------------------
   string tfs[6] = {"M5", "M15", "M30", "H1", "H4", "D1"};
   int tw = (innerW - AQ_Dpi(AQ_BTN_GAP) * 5) / 6;
   for(int i = 0; i < 6; i++)
     {
      int bx = xl + i * (tw + AQ_Dpi(AQ_BTN_GAP));
      bool active = (AQ_TfName((ENUM_TIMEFRAMES)Period()) == tfs[i]);
      AQ_UiButton("DBTF" + (string)i, bx, y, tw, bh, tfs[i],
                  active ? AQ_CLR_BTN_ON : AQ_CLR_BTN_OFF,
                  active ? AQ_CLR_GOLD   : AQ_CLR_BTN_TXT_OFF,
                  AQ_FS_SM, CORNER_LEFT_UPPER);
     }
   y += bh;
  }

//+------------------------------------------------------------------+
//| Data refresh                                                     |
//+------------------------------------------------------------------+
void CAQDashboard::Update(const AQDashData &d)
  {
   m_d = d;
   if(!m_created) return;

   AQ_UiText("DHSYM", d.symbol + " " + d.tf);
   if(m_collapsed) return;

   //--- headline
   string biasTxt = (d.bias > 0) ? "BULLISH" : (d.bias < 0) ? "BEARISH" : "NEUTRAL";
   if(!d.engineOk) biasTxt = "LOADING";
   AQ_UiTextClr("DBBIAS",  biasTxt, DirColor(d.bias));
   AQ_UiTextClr("DBBIASG", ArrowGlyph(d.bias), DirColor(d.bias));
   AQ_UiTextClr("DBSCORE", (d.score > 0 ? "+" : "") + (string)d.score, DirColor(d.bias));
   m_gaugeTarget = d.score;

   //--- MTF (plain font: the row carries timeframe names, so no glyph font here)
   string mtfTxt = d.mtf1Name + " " + (d.mtf1 > 0 ? "UP" : d.mtf1 < 0 ? "DOWN" : "--") + "   " +
                   d.mtf2Name + " " + (d.mtf2 > 0 ? "UP" : d.mtf2 < 0 ? "DOWN" : "--");
   int agree = d.mtf1 + d.mtf2;
   AQ_UiTextClr("DBV0", mtfTxt, agree > 0 ? AQ_CLR_BULL : agree < 0 ? AQ_CLR_BEAR : AQ_CLR_FLAT);

   //--- structure
   string st = (d.trend > 0 ? "RAIL UP" : "RAIL DN");
   st += " | " + (d.eventName == "" ? "--" : d.eventName);
   st += " | CH " + (d.chanSlope > 0 ? "UP" : d.chanSlope < 0 ? "DN" : "FLAT");
   AQ_UiTextClr("DBV1", st, DirColor(d.trend));

   //--- zones
   if(d.hasDemand) AQ_UiTextClr("DBV2", Fmt(d.demBot) + " - " + Fmt(d.demTop) + "  " + d.demGrade, AQ_CLR_BULL);
   else            AQ_UiTextClr("DBV2", "none in range", AQ_CLR_TEXT_MUTE);

   if(d.hasSupply) AQ_UiTextClr("DBV3", Fmt(d.supBot) + " - " + Fmt(d.supTop) + "  " + d.supGrade, AQ_CLR_BEAR);
   else            AQ_UiTextClr("DBV3", "none in range", AQ_CLR_TEXT_MUTE);

   //--- market stats
   AQ_UiTextClr("DBV4", StringFormat("ATR %.0f  SPR %.1f  %s  Z%d",
                                     d.atrPts, d.spreadPts, d.session, d.zoneCount), AQ_CLR_TEXT);

   //--- last signal
   if(d.lastSignal != 0)
      AQ_UiTextClr("DBV5", (d.lastSignal > 0 ? "BUY  " : "SELL ") + d.lastSignalAt, DirColor(d.lastSignal));
   else
      AQ_UiTextClr("DBV5", "waiting", AQ_CLR_TEXT_MUTE);
  }

//+------------------------------------------------------------------+
//| Animation frame — four objects, nothing else                     |
//+------------------------------------------------------------------+
void CAQDashboard::Animate(void)
  {
   if(!m_created) return;
   m_phase++;

   //--- 1. status pulse (breathes faster when a signal is live)
   double speed = (m_d.lastSignal != 0) ? 0.34 : 0.14;
   double t     = (MathSin(m_phase * speed) + 1.0) * 0.5;
   color  base  = (m_d.bias > 0) ? AQ_CLR_BULL : (m_d.bias < 0) ? AQ_CLR_BEAR : AQ_CLR_NEON;
   AQ_UiBg("DHDOT", AQ_Blend(AQ_CLR_NEON_DIM, base, t));
   AQ_UiColor("DHDOT", AQ_Blend(AQ_CLR_NEON_DIM, base, t));

   //--- 2. header sweep, ping-ponging across the panel
   int pad  = AQ_Dpi(AQ_PAD);
   int span = m_w - pad * 2 - AQ_Dpi(AQ_SWEEP_W);
   if(span > 4)
     {
      int p = (m_phase * 3) % (span * 2);
      if(p > span) p = span * 2 - p;
      AQ_UiMove("DHSWEEP", m_x + pad + p, m_sweepY);
      AQ_UiBg("DHSWEEP", AQ_Blend(AQ_CLR_GOLD_DIM, AQ_CLR_GOLD, t));
     }

   if(m_collapsed) { ChartRedraw(0); return; }

   //--- 3. score gauge easing toward the live score
   m_gaugeShown += ((double)m_gaugeTarget - m_gaugeShown) * 0.18;
   int half = m_gaugeW / 2;
   int fill = (int)MathRound(MathAbs(m_gaugeShown) / 100.0 * half);
   fill = AQ_Clamp(fill, 1, half);
   int gx = (m_gaugeShown >= 0.0) ? m_gaugeX + half : m_gaugeX + half - fill;
   AQ_UiMove("DBGFILL", gx, m_gaugeY + 1);
   AQ_UiSize("DBGFILL", fill, AQ_Dpi(AQ_GAUGE_H) - 2);
   color gc = (m_gaugeShown >= 0.0) ? AQ_CLR_BULL : AQ_CLR_BEAR;
   AQ_UiBg("DBGFILL", AQ_Blend(gc, AQ_CLR_GOLD, t * 0.35));
   AQ_UiColor("DBGFILL", AQ_Blend(gc, AQ_CLR_GOLD, t * 0.35));

   //--- 4. bias glow
   if(m_d.bias != 0)
      AQ_UiColor("DBBIASG", AQ_Blend(DirColor(m_d.bias), AQ_CLR_TEXT, t * 0.5));

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Click routing                                                    |
//+------------------------------------------------------------------+
int CAQDashboard::OnClick(const string name, int &param)
  {
   param = 0;
   string p = AQ_Prefix();
   if(StringFind(name, p) != 0) return(AQ_ACT_NONE);
   string id = StringSubstr(name, StringLen(p));

   //--- collapse / expand
   if(id == "DHCOL")
     {
      m_collapsed = !m_collapsed;
      Rebuild();
      Update(m_d);
      return(AQ_ACT_COLLAPSE);
     }

   //--- forced rescan
   if(id == "DBRS")
     {
      AQ_UiButtonState("DBRS", true, true);
      return(AQ_ACT_RESCAN);
     }

   //--- module toggles
   if(StringFind(id, "DBM") == 0)
     {
      int mod = (int)StringToInteger(StringSubstr(id, 3));
      if(mod < 0 || mod >= AQ_MOD_COUNT) return(AQ_ACT_NONE);
      m_mod[mod] = !m_mod[mod];
      AQ_UiButtonState(id, m_mod[mod], false);
      param = mod;
      return(AQ_ACT_TOGGLE);
     }

   //--- timeframe switcher
   if(StringFind(id, "DBTF") == 0)
     {
      int idx = (int)StringToInteger(StringSubstr(id, 4));
      ENUM_TIMEFRAMES tfs[6] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
      if(idx < 0 || idx > 5) return(AQ_ACT_NONE);
      AQ_UiButtonState(id, true, false);
      param = (int)tfs[idx];
      return(AQ_ACT_TF);
     }

   return(AQ_ACT_NONE);
  }

#endif // AQ_DASHBOARD_MQH
//+------------------------------------------------------------------+
