//+------------------------------------------------------------------+
//|                                              AdrenalineB1000.mq5 |
//|                                        Copyright 2026, Serro Deriv|
//|                                                                  |
//|   Gann Fan + Auto Trendlines + Fibonacci OTE Block Zone          |
//|   + Gann Square of 9 + Classic Pivots + MTF Dashboard            |
//|                                                                  |
//|  مؤشر احترافي: يكتشف الموجة (Impulse Leg) تلقائياً من قمم وقيعان |
//|  مؤكدة، ثم يبني عليها مروحة جان + مستويات فيبوناتشي + كتلة       |
//|  الشراء الشفافة، ويصدر إشارات بنظام نقاط توافقي.                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Serro Deriv"
#property link      ""
#property version   "2.10"
#property description "Adrenaline B1000 — by Serro Deriv"
#property description "Gann Fan + Auto Trendlines + Fibonacci OTE Block Zone + Square of 9 + Pivots"
#property description "Levels stay hidden until price reaches them, then a 40% Buy/Sell block appears"
#property description "with Fibonacci-based SL and TP, plus the ADRENALINE trend banner."
#property description "Arrows are non-repainting: closed bars only, and the MTF filter reads a closed HTF bar."

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

#property indicator_label1  "ADR Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  3

#property indicator_label2  "ADR Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrGold
#property indicator_width2  3

#property indicator_label3  "ADR Signal"      // +1 buy / -1 sell / 0 none  (EA reads via iCustom)
#property indicator_type3   DRAW_NONE

#property indicator_label4  "ADR Score"       // confluence score 0..8      (EA reads via iCustom)
#property indicator_type4   DRAW_NONE

//--- البافرات 5..8 تُصدّر حالة الموجة والمنطقة الذهبية لأي إكسبيرت عبر iCustom
#property indicator_label5  "ADR LegDir"      // +1 up leg / -1 down leg / 0 none
#property indicator_type5   DRAW_NONE

#property indicator_label6  "ADR ZoneHigh"    // Golden Zone upper price (0 = none)
#property indicator_type6   DRAW_NONE

#property indicator_label7  "ADR ZoneLow"     // Golden Zone lower price (0 = none)
#property indicator_type7   DRAW_NONE

#property indicator_label8  "ADR LegOrigin"   // leg 1.000 level = invalidation price (0 = none)
#property indicator_type8   DRAW_NONE

//+------------------------------------------------------------------+
//| TYPES — التعدادات المستخدمة في الإدخالات                          |
//+------------------------------------------------------------------+
enum ENUM_GANN_RATIO
  {
   GR_1x8 = 0,   // 1x8  (7.50 deg)
   GR_1x4,       // 1x4  (15.00 deg)
   GR_1x3,       // 1x3  (18.75 deg)
   GR_1x2,       // 1x2  (26.25 deg)
   GR_1x1,       // 1x1  (45.00 deg) - main angle
   GR_2x1,       // 2x1  (63.75 deg)
   GR_3x1,       // 3x1  (71.25 deg)
   GR_4x1,       // 4x1  (75.00 deg)
   GR_8x1        // 8x1  (82.50 deg)
  };

enum ENUM_SQ9_ANCHOR
  {
   SQ9_LEG_END = 0,   // Last swing extreme (leg end)
   SQ9_LEG_START,     // Leg origin pivot
   SQ9_CURRENT        // Current price
  };

enum ENUM_PANEL_CORNER
  {
   PC_LEFT_UPPER = 0, // Top Left
   PC_RIGHT_UPPER,    // Top Right
   PC_LEFT_LOWER,     // Bottom Left
   PC_RIGHT_LOWER     // Bottom Right
  };

//+------------------------------------------------------------------+
//| CONFIG — الإدخالات                                                |
//+------------------------------------------------------------------+
input group "=========  0. RUN MODE  ========="
//--- أول إدخال عمداً: الإكسبيرت يمرره وحده عبر iCustom(sym, tf, name, true)
input bool              InpEaMode            = false;    // EA mode: no drawings, no dashboard (for iCustom)

input group "=========  1. STRUCTURE / SWING ENGINE  ========="
input int               InpSwingN            = 5;        // Swing strength (bars each side)
input int               InpMaxBars           = 3000;     // Max bars to calculate (0 = all)
input int               InpExtendBars        = 30;       // Extend levels N bars to the right

input group "=========  2. FIBONACCI LEVELS  ========="
input bool              InpShowFib           = true;     // Show Fibonacci retracements
input bool              InpShowFibExt        = true;     // Show Fibonacci extensions (targets)
input double            InpGZ_Start          = 0.618;    // Golden Zone start (shallow)
input double            InpGZ_End            = 0.786;    // Golden Zone end (deep)
input bool              InpShowGoldenPocket  = true;     // Show Golden Pocket 0.618-0.650
input bool              InpShowOTE           = true;     // Show 0.705 OTE sweet-spot line
input bool              InpShowEquilibrium   = true;     // Show 0.500 Equilibrium (Premium/Discount)

input group "=========  3. GANN FAN  ========="
input bool              InpShowGann          = true;     // Show Gann Fan from leg pivot
input bool              InpGannAutoUnit      = true;     // Auto price-unit (leg range / leg bars)
input double            InpGannManualUnit    = 0.0;      // Manual price unit (used if auto = false)
input ENUM_GANN_RATIO   InpGannFilterRatio   = GR_1x2;   // Fan line used as trend filter

input group "=========  4. GANN SQUARE OF 9  ========="
input bool              InpShowSq9           = true;     // Show Square of 9 levels
input ENUM_SQ9_ANCHOR   InpSq9Anchor         = SQ9_LEG_END; // Square of 9 anchor
input int               InpSq9Steps          = 4;        // Levels above / below
input double            InpSq9Degrees        = 45.0;     // Degrees per step (45 / 90 / 120 / 180)
input double            InpSq9Scale          = 0.0;      // Price scale (0 = auto)

input group "=========  5. AUTO TRENDLINES  ========="
input bool              InpShowTrendlines    = true;     // Show auto trendlines (last 2 swings)
input bool              InpTL_Ray            = true;     // Extend trendlines to the right

input group "=========  6. PIVOT LEVELS (Daily)  ========="
input bool              InpShowPivots        = false;    // Show classic daily pivots (PP/R1-R3/S1-S3)

input group "=========  7. SIGNAL ENGINE  ========="
input bool              InpShowArrows        = true;     // Show Buy / Sell arrows
input int               InpMinScore          = 5;        // Minimum confluence score (max 8)
input int               InpMaxSignalsPerLeg  = 1;        // Max signals per impulse leg
input int               InpMinBarsBetween    = 5;        // Min bars between two signals
input int               InpEmaFast           = 21;       // EMA fast (trend filter)
input int               InpEmaSlow           = 50;       // EMA slow (trend filter)
input int               InpRsiPeriod         = 14;       // RSI period
input double            InpRsiBuyMax         = 68.0;     // Buy loses a point above this RSI
input double            InpRsiSellMin        = 32.0;     // Sell loses a point below this RSI
input bool              InpUseMtfFilter      = true;     // Use higher timeframe confirmation
input ENUM_TIMEFRAMES   InpMtfTimeframe      = PERIOD_H1;// Higher timeframe for confirmation
input int               InpAtrPeriod         = 14;       // ATR period (arrow offset / leg filter)
input double            InpArrowOffsetAtr    = 0.60;     // Arrow offset (x ATR)
input double            InpMinLegAtr         = 2.0;      // Min impulse size (x ATR) to accept a leg

input group "=========  8. MTF DASHBOARD  ========="
input bool              InpShowPanel         = true;     // Show dashboard
input ENUM_PANEL_CORNER InpPanelCorner       = PC_LEFT_UPPER; // Dashboard corner
input int               InpPanelX            = 14;       // Dashboard X offset (px)
input int               InpPanelY            = 22;       // Dashboard Y offset (px)
input bool              InpPanelAnimate      = true;     // Animated live status dot

input group "=========  9. ALERTS  ========="
input bool              InpAlertPopup        = true;     // Popup alert on new signal
input bool              InpAlertPush         = false;    // Push notification (mobile)
input bool              InpAlertSound        = true;     // Play sound on new signal
input string            InpAlertSoundFile    = "alert2.wav"; // Sound file

input group "=========  10. SIGNAL VISUALS  ========="
input bool              InpRevealOnTouch     = true;     // Fibonacci + OTE invisible until price reaches them
input bool              InpShowBlockZone     = true;     // Draw the semi-transparent Buy / Sell block
input double            InpBlockOpacity      = 40.0;     // Block opacity over the chart background (%)
input bool              InpShowTradePlan     = true;     // Entry / SL / TP lines on the last signal
input double            InpPlanSlFib         = 1.000;    // SL at this retracement level
input double            InpPlanTp1Fib        = 1.272;    // TP1 at this extension level
input double            InpPlanTp2Fib        = 1.618;    // TP2 at this extension level
input bool              InpShowApproachArrow = true;     // "GANN BUY" arrow before price touches Gann / trendline
input double            InpApproachAtr       = 0.35;     // Approach distance (x ATR)
input bool              InpAnimate           = true;     // Animate the levels and the banner
input int               InpAnimMs            = 120;      // Animation frame time (ms)

input group "=========  11. ADRENALINE TREND BANNER  ========="
input bool              InpShowAdrenaline    = true;     // Show the ADRENALINE ON / OFF banner
input int               InpAdrenalineFlashSec = 8;       // Seconds of strong flashing after a trend flip
input ENUM_PANEL_CORNER InpAdrenalineCorner   = PC_RIGHT_LOWER; // Banner corner
input int               InpAdrenalineX        = 14;      // Banner X offset from that corner (px)
input int               InpAdrenalineY        = 30;      // Banner Y offset from that corner (px)

//+------------------------------------------------------------------+
//| THEME — مكتبة الألوان: لا يوجد لون خام خارج هذه الكتلة            |
//+------------------------------------------------------------------+
#define THEME_BG              C'11,15,23'      // panel background (deep space)
#define THEME_BG_ALT          C'17,23,34'      // alternating row background
#define THEME_HEADER          C'8,11,18'       // header bar
#define THEME_NEON            C'0,229,255'     // neon blue accent
#define THEME_NEON_DIM        C'0,120,140'     // dimmed neon (panel border)
#define THEME_GOLD            C'255,193,7'     // gold accent
#define THEME_GOLD_DIM        C'138,104,10'    // dimmed gold
#define THEME_TEXT            C'226,232,240'   // primary text
#define THEME_TEXT_DIM        C'118,131,150'   // secondary text
#define THEME_BUY             C'0,230,168'     // bullish
#define THEME_SELL            C'255,82,102'    // bearish
#define THEME_NEUTRAL         C'128,140,158'   // neutral
#define THEME_BORDER          C'31,41,58'      // borders / separators
#define THEME_TP              C'0,230,168'     // take-profit levels
#define THEME_TP_HOT          C'120,255,214'   // take-profit pulse
#define THEME_SL              C'255,82,102'    // stop-loss level
#define THEME_ADR_ON          C'0,255,180'     // ADRENALINE ON
#define THEME_ADR_OFF         C'255,72,96'     // ADRENALINE OFF
#define THEME_FIB             C'88,101,124'    // fib line default
#define THEME_FIB_KEY         C'0,178,205'     // key fib line
#define THEME_GANN            C'126,87,194'    // gann fan lines
#define THEME_GANN_MAIN       C'186,104,255'   // gann 1x1
#define THEME_SQ9             C'184,134,11'    // square of 9 levels
#define THEME_TL_SUP          C'0,200,140'     // support trendline
#define THEME_TL_RES          C'235,90,110'    // resistance trendline
#define THEME_PIVOT           C'150,160,180'   // pivot lines

//+------------------------------------------------------------------+
//| METRICS — مكتبة الأبعاد: لا يوجد رقم بكسل خام خارج هذه الكتلة    |
//+------------------------------------------------------------------+
#define UI_PANEL_W            346
#define UI_PAD                8
#define UI_ROW_H              21
#define UI_ROW_SM             18              // UI_ROW_H - 3
#define UI_ROW_GAP            2
#define UI_HEAD_H             30
#define UI_SEP_H              1
#define UI_BTN_W              22
#define UI_KEY_W              104
#define UI_SIG_H              29              // UI_ROW_H + 8
#define UI_ADR_W              240             // عرض لافتة الأدرينالين
#define UI_ADR_H              30              // ارتفاعها
#define UI_FONT               "Segoe UI"
#define UI_FONT_MONO          "Consolas"
#define UI_FS                 8
#define UI_FS_SM              7
#define UI_FS_TITLE           10
#define UI_FS_BIG             12
#define UI_ZBACK              0
#define UI_ZFRONT             10

#define ADR_TF_COUNT          6
#define ADR_FAN_COUNT         9
#define ADR_FIB_COUNT         8
#define ADR_EXT_COUNT         5
#define ADR_DETAIL_ROWS       5
#define ADR_MAX_SCORE         8
#define ADR_FAN_MAIN_IDX      4               // index of 1x1 in g_fanRatio
#define ADR_FIB_EQ_IDX        2               // index of 0.500
#define ADR_FIB_618_IDX       3               // index of 0.618
#define ADR_FIB_OTE_IDX       5               // index of 0.705
#define ARROW_BUY_CODE        233
#define ARROW_SELL_CODE       234

//+------------------------------------------------------------------+
//| STATE — كل حالة البرنامج داخل بنية واحدة                          |
//+------------------------------------------------------------------+
struct SGfpState
  {
   //--- swing tracking (absolute, non-series bar indices)
   int               lastHiBar, lastLoBar, prevHiBar, prevLoBar;
   double            lastHiPrice, lastLoPrice, prevHiPrice, prevLoPrice;
   datetime          lastHiTime, lastLoTime, prevHiTime, prevLoTime;
   bool              lastSwingIsHigh;
   int               checkedBar;          // آخر شمعة فُحصت كمرشّح قمة/قاع
   //--- active impulse leg
   bool              legValid;
   bool              zoneTouched;         // بلغ السعر المنطقة الذهبية على هذه الموجة
   double            lastAtr;             // ATR آخر شمعة — لقياسات الرسم
   int               legDir;              // +1 = up leg (low->high), -1 = down leg
   int               legStartBar, legEndBar;
   double            legStartPrice, legEndPrice;
   datetime          legStartTime, legEndTime;
   double            gannUnit;            // price units per bar
   int               legSignals;          // signals already issued on this leg
   //--- signals
   int               lastSignalBar;
   int               lastSignalDir;
   double            lastSignalPrice;
   int               lastSignalScore;
   datetime          lastSignalTime;
   datetime          lastAlertBar;
   //--- housekeeping
   datetime          lastBarTime;
   bool              collapsed;
   int               pulse;
   bool              uiBuilt;
   int               animFrame;           // عدّاد إطارات الحركة
   int               trendDir;            // آخر اتجاه معلن (لكشف الانقلاب)
   int               adrState;            // +1 = ADRENALINE ON، -1 = OFF، 0 = لا شيء
   int               adrFlash;            // إطارات الوميض المتبقية بعد الانقلاب
   bool              adrShown;            // اللافتة معروضة حالياً
   datetime          planBar;             // شمعة الإشارة التي تخصّها خطة التداول المرسومة
   bool              apprActive;          // علامة الاقتراب معروضة حالياً

   //--- إعادة ضبط حالة التحليل فقط (حالة الواجهة تبقى)
   void Reset()
     {
      lastHiBar = lastLoBar = prevHiBar = prevLoBar = -1;
      lastHiPrice = lastLoPrice = prevHiPrice = prevLoPrice = 0.0;
      lastHiTime = lastLoTime = prevHiTime = prevLoTime = 0;
      lastSwingIsHigh = false;
      checkedBar = -1;
      legValid = false;
      zoneTouched = false;
      trendDir = 0;
      lastAtr = 0.0;
      legDir = 0;
      legStartBar = legEndBar = -1;
      legStartPrice = legEndPrice = 0.0;
      legStartTime = legEndTime = 0;
      gannUnit = 0.0;
      legSignals = 0;
      lastSignalBar = -1;
      lastSignalDir = 0;
      lastSignalPrice = 0.0;
      lastSignalScore = 0;
      lastSignalTime = 0;
     }
  };

SGfpState g_st;

//--- indicator buffers
double g_bufBuy[];
double g_bufSell[];
double g_bufSignal[];
double g_bufScore[];
double g_bufLegDir[];      // اتجاه الموجة النشطة عند كل شمعة
double g_bufZoneHi[];      // الحد الأعلى للمنطقة الذهبية
double g_bufZoneLo[];      // الحد الأدنى للمنطقة الذهبية
double g_bufLegOrig[];     // مستوى 1.000 (نقطة إبطال الموجة)

//--- cached indicator series of the CHART timeframe (indexed by absolute bar)
double g_emaF[];
double g_emaS[];
double g_rsi[];
double g_atr[];
double g_tmpCopy[];   // مخزن مؤقت لنسخ بافرات المؤشرات (يُعاد استخدامه بلا إعادة تخصيص)

//--- handles: chart timeframe
int    g_hEmaF = INVALID_HANDLE;
int    g_hEmaS = INVALID_HANDLE;
int    g_hRsi  = INVALID_HANDLE;
int    g_hAtr  = INVALID_HANDLE;
int    g_hMtfF = INVALID_HANDLE;     // higher timeframe EMA fast
int    g_hMtfS = INVALID_HANDLE;     // higher timeframe EMA slow

//--- handles: dashboard timeframes
ENUM_TIMEFRAMES g_tf[ADR_TF_COUNT] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4};
int    g_hTfEmaF[ADR_TF_COUNT];
int    g_hTfEmaS[ADR_TF_COUNT];
int    g_hTfRsi [ADR_TF_COUNT];

//--- gann fan definition (price units per bar)
double g_fanRatio[ADR_FAN_COUNT] = {0.125, 0.25, 0.3333333, 0.5, 1.0, 2.0, 3.0, 4.0, 8.0};
string g_fanName [ADR_FAN_COUNT] = {"1x8", "1x4", "1x3", "1x2", "1x1", "2x1", "3x1", "4x1", "8x1"};

//--- fibonacci definition
double g_fibRet[ADR_FIB_COUNT] = {0.236, 0.382, 0.500, 0.618, 0.650, 0.705, 0.786, 0.886};
double g_fibExt[ADR_EXT_COUNT] = {1.272, 1.414, 1.618, 2.000, 2.618};

//--- dashboard table column widths
int    g_colW[5] = {46, 66, 50, 82, 84};

//--- runtime state that is not part of the analysis STATE
string g_prefix    = "ADR_";
int    g_warmup    = 100;
double g_sq9Scale  = 1.0;
bool   g_uiEnabled = false;
int    g_baseX     = 0;      // panel origin (base units, left-upper anchored)
int    g_baseY     = 0;
int    g_chartW    = 0;      // cached chart size, to detect real resizes
int    g_chartH    = 0;

//+------------------------------------------------------------------+
//|                        U T I L I T I E S                         |
//+------------------------------------------------------------------+

//--- بادئة كائنات فريدة لكل شارت
string Prefix()
  {
   return g_prefix;
  }

//--- دقة الشاشة (تُقرأ مرة واحدة)
int ScreenDpi()
  {
   static int dpi = 0;
   if(dpi <= 0)
      dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi <= 0)
      dpi = 96;
   return dpi;
  }

//--- تحويل وحدة تصميم إلى بكسل حقيقي
int Dpi(const int base)
  {
   return (int)MathRound((double)base * (double)ScreenDpi() / 96.0);
  }

//--- تحويل بكسل حقيقي إلى وحدة تصميم
int Undpi(const int px)
  {
   return (int)MathRound((double)px * 96.0 / (double)ScreenDpi());
  }

//--- تقييد قيمة ضمن مجال
template<typename T>
T Clamp(T v, T lo, T hi)
  {
   return (v < lo) ? lo : ((v > hi) ? hi : v);
  }

//--- تسجيل موحّد للأخطاء
void LogErr(const string context, const int code = -1)
  {
   PrintFormat("[ADR][%s] %s | err=%d", _Symbol, context, (code >= 0 ? code : GetLastError()));
   ResetLastError();
  }

//--- اسم مختصر للإطار الزمني
string TfName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
  }

//--- نسبة زاوية جان المستخدمة كمرشّح
double GannFilterRatioValue()
  {
   int idx = Clamp((int)InpGannFilterRatio, 0, ADR_FAN_COUNT - 1);
   return g_fanRatio[idx];
  }

//--- معامل تحجيم مربع التسعة (يضع السعر في مجال 10000..100000)
double Sq9Scale(const double price)
  {
   if(InpSq9Scale > 0.0)
      return InpSq9Scale;
   if(price <= 0.0)
      return 1.0;
   double s = 1.0;
   double p = price;
   while(p < 10000.0 && s < 1.0e8)  { p *= 10.0; s *= 10.0; }
   while(p >= 100000.0 && s > 1.0e-8) { p /= 10.0; s /= 10.0; }
   return s;
  }

//--- مكوّنات اللون (color في MQL5 مخزّن بالشكل 0x00BBGGRR)
int ColR(const color c) { return (int)((uint)c        & 0xFF); }
int ColG(const color c) { return (int)(((uint)c >>  8) & 0xFF); }
int ColB(const color c) { return (int)(((uint)c >> 16) & 0xFF); }

//--- تركيب لون من مكوّناته
color ColMake(const int r, const int g, const int b)
  {
   int rr = Clamp(r, 0, 255), gg = Clamp(g, 0, 255), bb = Clamp(b, 0, 255);
   return (color)((uint)((bb << 16) | (gg << 8) | rr));
  }

//--- مزج لونين: alpha = وزن اللون الأمامي (0..1)
//    كائنات الشارت في MT5 بلا قناة شفافية، لذا نحاكي الشفافية بالمزج مع خلفية الشارت
color ColBlend(const color fg, const color bg, const double alpha)
  {
   double a = (alpha < 0.0) ? 0.0 : ((alpha > 1.0) ? 1.0 : alpha);
   return ColMake((int)MathRound(ColR(fg) * a + ColR(bg) * (1.0 - a)),
                  (int)MathRound(ColG(fg) * a + ColG(bg) * (1.0 - a)),
                  (int)MathRound(ColB(fg) * a + ColB(bg) * (1.0 - a)));
  }

//--- لون خلفية الشارت الحالي
color ChartBg()
  {
   return (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
  }

//--- لون الكتلة بنسبة الشفافية المطلوبة فوق خلفية الشارت
color BlockColor(const color base)
  {
   return ColBlend(base, ChartBg(), InpBlockOpacity / 100.0);
  }

//--- سعر منسّق للعرض
string PriceStr(const double p)
  {
   return DoubleToString(p, _Digits);
  }

//+------------------------------------------------------------------+
//|            C O R E  —  SWING / LEG / LEVEL ENGINE                |
//+------------------------------------------------------------------+

//--- قمة مؤكدة: أعلى قيمة ضمن نافذة [c-n, c+n]
bool IsSwingHigh(const double &high[], const int c, const int n)
  {
   double h = high[c];
   for(int k = c - n; k <= c + n; k++)
      if(k != c && high[k] >= h)
         return false;
   return true;
  }

//--- قاع مؤكد: أدنى قيمة ضمن نافذة [c-n, c+n]
bool IsSwingLow(const double &low[], const int c, const int n)
  {
   double l = low[c];
   for(int k = c - n; k <= c + n; k++)
      if(k != c && low[k] <= l)
         return false;
   return true;
  }

//--- تثبيت موجة جديدة + حساب وحدة سعر جان
void SetLeg(const int dir, const int sBar, const double sPrice, const datetime sTime,
            const int eBar, const double ePrice, const datetime eTime)
  {
   int bars = eBar - sBar;
   if(bars <= 0)
      return;
   double range = MathAbs(ePrice - sPrice);
   if(range <= 0.0)
      return;

   g_st.legValid      = true;
   g_st.legDir        = dir;
   g_st.legStartBar   = sBar;
   g_st.legStartPrice = sPrice;
   g_st.legStartTime  = sTime;
   g_st.legEndBar     = eBar;
   g_st.legEndPrice   = ePrice;
   g_st.legEndTime    = eTime;
   g_st.legSignals    = 0;
   g_st.zoneTouched   = false;          // منطقة ذهبية جديدة — تعود مخفية
   g_st.gannUnit      = (InpGannAutoUnit || InpGannManualUnit <= 0.0)
                        ? range / (double)bars
                        : InpGannManualUnit;
  }

//--- تسجيل قمة/قاع مؤكد وتحديث الموجة النشطة
void RegisterSwing(const bool isHigh, const int bar, const double price, const datetime t)
  {
   if(isHigh)
     {
      if(g_st.lastSwingIsHigh && g_st.lastHiBar >= 0)
        {
         if(price <= g_st.lastHiPrice)
            return;                         // ليست أكثر تطرفاً — تجاهل
        }
      else
        {
         g_st.prevHiBar   = g_st.lastHiBar;
         g_st.prevHiPrice = g_st.lastHiPrice;
         g_st.prevHiTime  = g_st.lastHiTime;
        }
      g_st.lastHiBar       = bar;
      g_st.lastHiPrice     = price;
      g_st.lastHiTime      = t;
      g_st.lastSwingIsHigh = true;
      if(g_st.lastLoBar >= 0 && g_st.lastLoBar < bar)
         SetLeg(+1, g_st.lastLoBar, g_st.lastLoPrice, g_st.lastLoTime, bar, price, t);
      return;
     }

   if(!g_st.lastSwingIsHigh && g_st.lastLoBar >= 0)
     {
      if(price >= g_st.lastLoPrice)
         return;
     }
   else
     {
      g_st.prevLoBar   = g_st.lastLoBar;
      g_st.prevLoPrice = g_st.lastLoPrice;
      g_st.prevLoTime  = g_st.lastLoTime;
     }
   g_st.lastLoBar       = bar;
   g_st.lastLoPrice     = price;
   g_st.lastLoTime      = t;
   g_st.lastSwingIsHigh = false;
   if(g_st.lastHiBar >= 0 && g_st.lastHiBar < bar)
      SetLeg(-1, g_st.lastHiBar, g_st.lastHiPrice, g_st.lastHiTime, bar, price, t);
  }

//--- مدى الموجة النشطة
double LegRange()
  {
   return MathAbs(g_st.legEndPrice - g_st.legStartPrice);
  }

//--- سعر مستوى تصحيح فيبوناتشي (0 = نهاية الموجة، 1 = بدايتها)
double FibRetPrice(const double r)
  {
   double range = LegRange();
   if(g_st.legDir > 0)
      return g_st.legEndPrice - r * range;   // موجة صاعدة: التصحيح للأسفل
   return g_st.legEndPrice + r * range;      // موجة هابطة: التصحيح للأعلى
  }

//--- سعر امتداد فيبوناتشي (هدف خارج الموجة)
double FibExtPrice(const double e)
  {
   double range = LegRange();
   if(g_st.legDir > 0)
      return g_st.legStartPrice + e * range;
   return g_st.legStartPrice - e * range;
  }

//--- قيمة خط مروحة جان بنسبة q عند شمعة رقم bar
double GannValueAt(const double q, const int bar)
  {
   if(!g_st.legValid || g_st.gannUnit <= 0.0)
      return 0.0;
   double d = (double)(bar - g_st.legStartBar);
   if(d < 0.0)
      d = 0.0;
   return g_st.legStartPrice + (double)g_st.legDir * g_st.gannUnit * q * d;
  }

//--- مستوى مربع التسعة على بعد step خطوة من سعر الارتكاز
double Sq9Level(const double anchor, const int step)
  {
   if(anchor <= 0.0)
      return 0.0;
   double root = MathSqrt(anchor * g_sq9Scale);
   double v = root + (double)step * (InpSq9Degrees / 180.0);
   if(v <= 0.0)
      return 0.0;
   return (v * v) / g_sq9Scale;
  }

//--- قيمة خط اتجاه يمر بنقطتين، عند شمعة رقم bar
double TrendlineValueAt(const int b1, const double p1, const int b2, const double p2, const int bar)
  {
   if(b2 == b1)
      return p2;
   double slope = (p2 - p1) / (double)(b2 - b1);
   return p1 + slope * (double)(bar - b1);
  }

//--- توفر خطي الاتجاه
bool HasResTrendline() { return (g_st.prevHiBar >= 0 && g_st.lastHiBar > g_st.prevHiBar); }
bool HasSupTrendline() { return (g_st.prevLoBar >= 0 && g_st.lastLoBar > g_st.prevLoBar); }

//+------------------------------------------------------------------+
//|         M T F   H E L P E R S  (higher timeframe reads)          |
//+------------------------------------------------------------------+

//--- قراءة قيمة مؤشر واحدة بأمان
bool ReadOne(const int handle, const int buffer, const int shift, double &out)
  {
   out = 0.0;
   if(handle == INVALID_HANDLE)
      return false;
   double v[1];
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1)
      return false;
   out = v[0];
   return true;
  }

//--- اتجاه الإطار الأعلى عند لحظة زمنية معينة (+1 / -1 / 0)
int MtfTrendAt(const datetime t)
  {
   if(!InpUseMtfFilter)
      return 0;
   int shift = iBarShift(_Symbol, InpMtfTimeframe, t, false);
   if(shift < 0)
      return 0;

   //--- منع إعادة الرسم: الشمعة رقم shift هي التي تحتوي اللحظة t، وكانت لا تزال
   //--- قيد التكوّن عند إغلاق شمعة الإشارة؛ قيمتها اللحظية آنذاك تختلف عن قيمتها
   //--- النهائية بعد إغلاقها، فتتغيّر النقاط عند إعادة حساب التاريخ ويظهر/يختفي
   //--- السهم. لذلك نقرأ دائماً الشمعة الأعلى السابقة — المغلقة يقيناً وقت t.
   shift += 1;

   double f = 0.0, s = 0.0;
   if(!ReadOne(g_hMtfF, 0, shift, f) || !ReadOne(g_hMtfS, 0, shift, s))
      return 0;
   if(f > s) return +1;
   if(f < s) return -1;
   return 0;
  }

//--- تحميل نطاق من مؤشر إلى مصفوفة مفهرسة بأرقام الشموع المطلقة
bool LoadRange(const int handle, const int from, const int ratesTotal, double &dst[])
  {
   int cnt = ratesTotal - from;
   if(cnt <= 0)
      return true;
   if(ArraySize(dst) != ratesTotal && ArrayResize(dst, ratesTotal) != ratesTotal)
      return false;

   int got = CopyBuffer(handle, 0, 0, cnt, g_tmpCopy);
   if(got < cnt)
      return false;                          // التاريخ لم يجهز بعد — أعد المحاولة لاحقاً

   for(int k = 0; k < cnt; k++)
      dst[from + k] = g_tmpCopy[k];
   return true;
  }

//+------------------------------------------------------------------+
//|                  S I G N A L   E N G I N E                       |
//+------------------------------------------------------------------+

//--- تأكيد شمعة انعكاسية في اتجاه dir
bool CandleConfirms(const int dir, const int i, const double &open[], const double &high[],
                    const double &low[], const double &close[])
  {
   double range = high[i] - low[i];
   if(range <= 0.0)
      return false;

   if(dir > 0)
     {
      bool bullBody  = (close[i] > open[i]);
      bool lowerWick = ((MathMin(open[i], close[i]) - low[i]) / range) > 0.40;
      bool closeTop  = ((close[i] - low[i]) / range) > 0.55;
      return (bullBody && closeTop) || lowerWick;
     }

   bool bearBody  = (close[i] < open[i]);
   bool upperWick = ((high[i] - MathMax(open[i], close[i])) / range) > 0.40;
   bool closeBot  = ((high[i] - close[i]) / range) > 0.55;
   return (bearBody && closeBot) || upperWick;
  }

//--- تقييم الإشارة على شمعة مغلقة i؛ يرجع النقاط ويحدّد الاتجاه
int EvaluateSignal(const int i, const datetime &time[], const double &open[], const double &high[],
                   const double &low[], const double &close[], int &dirOut)
  {
   dirOut = 0;
   if(!g_st.legValid)
      return 0;
   if(i <= g_st.legEndBar)                    // الإشارة بعد اكتمال الموجة فقط
      return 0;
   if(g_st.legSignals >= InpMaxSignalsPerLeg)
      return 0;
   if(g_st.lastSignalBar >= 0 && (i - g_st.lastSignalBar) < InpMinBarsBetween)
      return 0;
   if(i >= ArraySize(g_atr))
      return 0;

   double atr = g_atr[i];
   if(atr <= 0.0)
      return 0;
   if(LegRange() < InpMinLegAtr * atr)         // موجة ضعيفة — تجاهل
      return 0;

   int dir = g_st.legDir;                      // تداول مع اتجاه الموجة (Continuation)
   double zShallow = FibRetPrice(InpGZ_Start); // 0.618
   double zDeep    = FibRetPrice(InpGZ_End);   // 0.786
   double zHi = MathMax(zShallow, zDeep);
   double zLo = MathMin(zShallow, zDeep);

   //--- 1) تفاعل مع المنطقة الذهبية — شرط إلزامي بوزن نقطتين
   if(!(low[i] <= zHi && high[i] >= zLo))
      return 0;
   //--- الإغلاق يجب أن يبقى داخل الموجة (لم يُكسر مستوى 1.000)
   if(dir > 0 && close[i] <= g_st.legStartPrice)
      return 0;
   if(dir < 0 && close[i] >= g_st.legStartPrice)
      return 0;

   int score = 2;

   //--- 2) تأكيد الشمعة
   if(CandleConfirms(dir, i, open, high, low, close))
      score++;

   //--- 3) اتجاه المتوسطات على الإطار الحالي
   if(i < ArraySize(g_emaF) && i < ArraySize(g_emaS))
     {
      if(dir > 0 && g_emaF[i] > g_emaS[i]) score++;
      if(dir < 0 && g_emaF[i] < g_emaS[i]) score++;
     }

   //--- 4) مرشّح مروحة جان (السعر فوق/تحت الزاوية المختارة)
   double gv = GannValueAt(GannFilterRatioValue(), i);
   if(gv > 0.0)
     {
      if(dir > 0 && close[i] > gv) score++;
      if(dir < 0 && close[i] < gv) score++;
     }

   //--- 5) خط الاتجاه التلقائي
   if(dir > 0 && HasSupTrendline())
     {
      double tl = TrendlineValueAt(g_st.prevLoBar, g_st.prevLoPrice, g_st.lastLoBar, g_st.lastLoPrice, i);
      if(tl > 0.0 && close[i] > tl) score++;
     }
   if(dir < 0 && HasResTrendline())
     {
      double tl = TrendlineValueAt(g_st.prevHiBar, g_st.prevHiPrice, g_st.lastHiBar, g_st.lastHiPrice, i);
      if(tl > 0.0 && close[i] < tl) score++;
     }

   //--- 6) مرشّح القوة النسبية (لا شراء في تشبع شرائي)
   if(i < ArraySize(g_rsi))
     {
      if(dir > 0 && g_rsi[i] < InpRsiBuyMax)  score++;
      if(dir < 0 && g_rsi[i] > InpRsiSellMin) score++;
     }

   //--- 7) توافق الإطار الأعلى
   if(InpUseMtfFilter)
     {
      if(MtfTrendAt(time[i]) == dir)
         score++;
     }
   else
      score++;                                 // بلا مرشّح: النقطة ممنوحة

   if(score < InpMinScore)
      return 0;

   dirOut = dir;
   return score;
  }

//+------------------------------------------------------------------+
//|            D R A W  —  price/time anchored objects               |
//+------------------------------------------------------------------+

//--- هل النوع يدعم التعبئة؟
bool TypeSupportsFill(const ENUM_OBJECT type)
  {
   return (type == OBJ_RECTANGLE || type == OBJ_ELLIPSE || type == OBJ_TRIANGLE);
  }

//--- هل النوع خط (يدعم العرض والنمط)؟
bool TypeIsLine(const ENUM_OBJECT type)
  {
   return (type == OBJ_TREND || type == OBJ_HLINE || type == OBJ_VLINE ||
           type == OBJ_RECTANGLE || type == OBJ_ELLIPSE || type == OBJ_TRIANGLE);
  }

//--- المُنشئ العام لكل كائنات السعر/الزمن
bool DrawObj(const string id, const ENUM_OBJECT type,
             const datetime t1, const double p1, const datetime t2, const double p2,
             const color clr, const int width, const ENUM_LINE_STYLE style,
             const bool back, const bool fill)
  {
   string n = Prefix() + id;
   if(ObjectFind(0, n) < 0)
     {
      bool ok = (t2 == 0) ? ObjectCreate(0, n, type, 0, t1, p1)
                : ObjectCreate(0, n, type, 0, t1, p1, t2, p2);
      if(!ok)
         return false;
     }
   else
     {
      ObjectMove(0, n, 0, t1, p1);
      if(t2 != 0)
         ObjectMove(0, n, 1, t2, p2);
     }
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_BACK,       back);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   if(TypeIsLine(type))
     {
      ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, n, OBJPROP_STYLE, style);
     }
   if(TypeSupportsFill(type))
      ObjectSetInteger(0, n, OBJPROP_FILL, fill);
   return true;
  }

//--- قطعة أفقية محدودة (مستوى) بين زمنين
bool DrawSegment(const string id, const datetime t1, const datetime t2, const double price,
                 const color clr, const int width, const ENUM_LINE_STYLE style)
  {
   if(!DrawObj(id, OBJ_TREND, t1, price, t2, price, clr, width, style, false, false))
      return false;
   string n = Prefix() + id;
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_RAY_LEFT,  false);
   return true;
  }

//--- شعاع اتجاه (خط اتجاه / زاوية جان)
bool DrawRay(const string id, const datetime t1, const double p1, const datetime t2, const double p2,
             const color clr, const int width, const ENUM_LINE_STYLE style, const bool ray)
  {
   if(!DrawObj(id, OBJ_TREND, t1, p1, t2, p2, clr, width, style, false, false))
      return false;
   string n = Prefix() + id;
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, n, OBJPROP_RAY_LEFT,  false);
   return true;
  }

//--- منطقة سعرية (مستطيل معبأ خلف الشموع)
bool DrawBox(const string id, const datetime t1, const double pHi, const datetime t2,
             const double pLo, const color clr)
  {
   return DrawObj(id, OBJ_RECTANGLE, t1, pHi, t2, pLo, clr, 1, STYLE_SOLID, true, true);
  }

//--- نص ملتصق بمستوى سعري
bool DrawLabel(const string id, const datetime t, const double price, const string text,
               const color clr, const int fs = UI_FS)
  {
   if(!DrawObj(id, OBJ_TEXT, t, price, 0, 0.0, clr, 1, STYLE_SOLID, false, false))
      return false;
   string n = Prefix() + id;
   ObjectSetString (0, n, OBJPROP_TEXT,     text);
   ObjectSetString (0, n, OBJPROP_FONT,     UI_FONT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,   ANCHOR_RIGHT);
   return true;
  }

//--- سهم Wingdings على الشارت
bool DrawArrowObj(const string id, const datetime t, const double price, const uchar code,
                  const color clr, const int width, const ENUM_ARROW_ANCHOR anchor)
  {
   if(!DrawObj(id, OBJ_ARROW, t, price, 0, 0.0, clr, width, STYLE_SOLID, false, false))
      return false;
   string n = Prefix() + id;
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, n, OBJPROP_WIDTH,     width);
   return true;
  }

//--- نص على الشارت بخط اختياري ومحاذاة اختيارية
bool DrawTag(const string id, const datetime t, const double price, const string text,
             const color clr, const int fs, const ENUM_ANCHOR_POINT anchor)
  {
   if(!DrawObj(id, OBJ_TEXT, t, price, 0, 0.0, clr, 1, STYLE_SOLID, false, false))
      return false;
   string n = Prefix() + id;
   ObjectSetString (0, n, OBJPROP_TEXT,     text);
   ObjectSetString (0, n, OBJPROP_FONT,     UI_FONT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,   anchor);
   return true;
  }

//+------------------------------------------------------------------+
//|            A N I M A T I O N   H E L P E R S                     |
//+------------------------------------------------------------------+

//--- عدد إطارات الحركة في الثانية
int FramesPerSecond()
  {
   return (int)MathMax(1, 1000 / (int)MathMax(50, InpAnimMs));
  }

//--- إزاحة متذبذبة
double AnimBob(const double amplitude)
  {
   if(!InpAnimate)
      return 0.0;
   return MathSin((double)g_st.animFrame * 0.30) * amplitude;
  }

//--- نبضة عرض الخط بين قيمتين
int AnimWidth(const int lo, const int hi)
  {
   if(!InpAnimate)
      return lo;
   return ((g_st.animFrame / 4) % 2 == 0) ? lo : hi;
  }

//--- نبضة لون بين لونين
color AnimColor(const color a, const color b)
  {
   if(!InpAnimate)
      return a;
   return ((g_st.animFrame / 4) % 2 == 0) ? a : b;
  }

//--- هل بلغ السعر المنطقة الذهبية على الموجة النشطة؟
bool ZoneReachedNow()
  {
   if(!g_st.legValid)
      return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
      return false;
   double a = FibRetPrice(InpGZ_Start);
   double b = FibRetPrice(InpGZ_End);
   if(g_st.legDir > 0)
      return (bid <= MathMax(a, b));      // هبط إلى حافة 0.618
   return (bid >= MathMin(a, b));         // صعد إلى حافة 0.618
  }

//--- حذف مجموعة رسومات حسب بادئة فرعية
void ClearGroup(const string sub)
  {
   ObjectsDeleteAll(0, Prefix() + sub);
  }

//--- الحد الأيمن الزمني لكل المستويات
datetime RightEdge()
  {
   return (datetime)(g_st.lastBarTime + (datetime)(PeriodSeconds() * InpExtendBars));
  }

//--- رسم مستويات فيبوناتشي + المنطقة الذهبية + الامتدادات
void DrawFibonacci()
  {
   ClearGroup("FIB_");
   if(!g_st.legValid)
      return;

   //--- الطبقة كلها (فيبوناتشي + OTE) مخفية حتى يبلغها السعر
   if(InpRevealOnTouch && !g_st.zoneTouched)
      return;

   datetime tR = RightEdge();
   int      dir = g_st.legDir;

   //--- كتلة الشراء/البيع الشفافة 40% فوق منطقة OTE
   if(InpShowBlockZone)
     {
      double a = FibRetPrice(InpGZ_Start);
      double b = FibRetPrice(InpGZ_End);
      color  block = BlockColor(dir > 0 ? THEME_BUY : THEME_SELL);
      DrawBox("FIB_BLOCK", g_st.legEndTime, MathMax(a, b), tR, MathMin(a, b), block);
      DrawLabel("FIB_BLOCKL", tR, (a + b) / 2.0,
                StringFormat("%s BLOCK  %s - %s", (dir > 0 ? "BUY" : "SELL"),
                             PriceStr(MathMin(a, b)), PriceStr(MathMax(a, b))),
                (dir > 0 ? THEME_BUY : THEME_SELL), UI_FS);
     }

   //--- الجيب الذهبي 0.618 - 0.650 داخل الكتلة (أغمق قليلاً)
   if(InpShowGoldenPocket)
     {
      double a = FibRetPrice(g_fibRet[ADR_FIB_618_IDX]);
      double b = FibRetPrice(g_fibRet[ADR_FIB_618_IDX + 1]);
      color  pocket = ColBlend(THEME_GOLD, ChartBg(), MathMin(1.0, InpBlockOpacity / 100.0 + 0.15));
      DrawBox("FIB_POCKET", g_st.legEndTime, MathMax(a, b), tR, MathMin(a, b), pocket);
     }

   //--- مستويات التصحيح
   if(InpShowFib)
     {
      for(int k = 0; k < ADR_FIB_COUNT; k++)
        {
         if(k == ADR_FIB_EQ_IDX  && !InpShowEquilibrium) continue;
         if(k == ADR_FIB_OTE_IDX && !InpShowOTE)         continue;

         double r = g_fibRet[k];
         double p = FibRetPrice(r);
         bool  key = (k == ADR_FIB_EQ_IDX || k == ADR_FIB_618_IDX || k == ADR_FIB_OTE_IDX);
         color c   = key ? THEME_FIB_KEY : THEME_FIB;
         int   w   = key ? 2 : 1;
         ENUM_LINE_STYLE s = (k == ADR_FIB_OTE_IDX) ? STYLE_DASHDOT : STYLE_DOT;

         string id  = StringFormat("FIB_R%d", (int)MathRound(r * 1000.0));
         string tag = (k == ADR_FIB_EQ_IDX)  ? "0.500 EQ"
                      : ((k == ADR_FIB_OTE_IDX) ? "0.705 OTE" : DoubleToString(r, 3));

         DrawSegment(id, g_st.legEndTime, tR, p, c, w, s);
         DrawLabel(id + "L", tR, p, tag + "  " + PriceStr(p), c, UI_FS_SM);
        }

      //--- حدود الموجة 0.000 و 1.000
      DrawSegment("FIB_R0",    g_st.legEndTime,   tR, g_st.legEndPrice,   THEME_FIB_KEY, 2, STYLE_SOLID);
      DrawSegment("FIB_R1000", g_st.legStartTime, tR, g_st.legStartPrice, THEME_FIB_KEY, 2, STYLE_SOLID);
      DrawLabel("FIB_R0L",    tR, g_st.legEndPrice,
                "0.000  " + PriceStr(g_st.legEndPrice),   THEME_FIB_KEY, UI_FS_SM);
      DrawLabel("FIB_R1000L", tR, g_st.legStartPrice,
                "1.000  " + PriceStr(g_st.legStartPrice), THEME_FIB_KEY, UI_FS_SM);
     }

   //--- الامتدادات (الأهداف)
   if(InpShowFibExt)
     {
      for(int k = 0; k < ADR_EXT_COUNT; k++)
        {
         double e  = g_fibExt[k];
         double p  = FibExtPrice(e);
         string id = StringFormat("FIB_E%d", (int)MathRound(e * 1000.0));
         DrawSegment(id, g_st.legEndTime, tR, p, THEME_GOLD_DIM, 1, STYLE_DASH);
         DrawLabel(id + "L", tR, p, "TP " + DoubleToString(e, 3) + "  " + PriceStr(p),
                   THEME_GOLD_DIM, UI_FS_SM);
        }
     }

   //--- تمييز نقطتي الموجة A و B
   DrawLabel("FIB_PA", g_st.legStartTime, g_st.legStartPrice, "A", THEME_NEON, UI_FS);
   DrawLabel("FIB_PB", g_st.legEndTime,   g_st.legEndPrice,   "B", THEME_NEON, UI_FS);
  }

//--- رسم مروحة جان من نقطة ارتكاز الموجة
void DrawGannFan()
  {
   ClearGroup("GANN_");
   if(!InpShowGann || !g_st.legValid || g_st.gannUnit <= 0.0)
      return;

   datetime tR = RightEdge();
   int legBars   = (int)MathMax(1, g_st.legEndBar - g_st.legStartBar);
   int barsRight = InpExtendBars + legBars;

   for(int k = 0; k < ADR_FAN_COUNT; k++)
     {
      double q  = g_fanRatio[k];
      double p2 = g_st.legStartPrice + (double)g_st.legDir * g_st.gannUnit * q * (double)barsRight;
      bool  main = (k == ADR_FAN_MAIN_IDX);
      color c    = main ? THEME_GANN_MAIN : THEME_GANN;
      int   w    = main ? 2 : 1;
      ENUM_LINE_STYLE s = main ? STYLE_SOLID : STYLE_DOT;

      string id = "GANN_" + g_fanName[k];
      DrawRay(id, g_st.legStartTime, g_st.legStartPrice, tR, p2, c, w, s, false);
      DrawLabel(id + "L", tR, p2, g_fanName[k], c, UI_FS_SM);
     }
  }

//--- سعر ارتكاز مربع التسعة حسب الإعداد
double Sq9Anchor()
  {
   if(InpSq9Anchor == SQ9_LEG_START)
      return g_st.legStartPrice;
   if(InpSq9Anchor == SQ9_CURRENT)
      return SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return g_st.legEndPrice;
  }

//--- رسم مستويات مربع التسعة
void DrawSquareOf9()
  {
   ClearGroup("SQ9_");
   if(!InpShowSq9 || !g_st.legValid)
      return;

   double anchor = Sq9Anchor();
   if(anchor <= 0.0)
      return;

   g_sq9Scale = Sq9Scale(anchor);
   datetime tL = g_st.legEndTime;
   datetime tR = RightEdge();

   for(int s = -InpSq9Steps; s <= InpSq9Steps; s++)
     {
      double p = Sq9Level(anchor, s);
      if(p <= 0.0)
         continue;
      bool  zero = (s == 0);
      string id  = StringFormat("SQ9_%d", s + InpSq9Steps);
      DrawSegment(id, tL, tR, p, zero ? THEME_GOLD : THEME_SQ9, zero ? 2 : 1,
                  zero ? STYLE_SOLID : STYLE_DOT);
      DrawLabel(id + "L", tR, p, StringFormat("Sq9 %+d (%.0f deg)", s, s * InpSq9Degrees),
                zero ? THEME_GOLD : THEME_SQ9, UI_FS_SM);
     }
  }

//--- رسم خطي الاتجاه التلقائيين
void DrawTrendlines()
  {
   ClearGroup("TL_");
   if(!InpShowTrendlines)
      return;

   if(HasResTrendline())
     {
      DrawRay("TL_RES", g_st.prevHiTime, g_st.prevHiPrice, g_st.lastHiTime, g_st.lastHiPrice,
              THEME_TL_RES, 2, STYLE_SOLID, InpTL_Ray);
      DrawLabel("TL_RESL", g_st.lastHiTime, g_st.lastHiPrice, "RES", THEME_TL_RES, UI_FS_SM);
     }
   if(HasSupTrendline())
     {
      DrawRay("TL_SUP", g_st.prevLoTime, g_st.prevLoPrice, g_st.lastLoTime, g_st.lastLoPrice,
              THEME_TL_SUP, 2, STYLE_SOLID, InpTL_Ray);
      DrawLabel("TL_SUPL", g_st.lastLoTime, g_st.lastLoPrice, "SUP", THEME_TL_SUP, UI_FS_SM);
     }
  }

//--- رسم نقاط البيفوت الكلاسيكية من شمعة اليوم السابق
void DrawPivots()
  {
   ClearGroup("PIV_");
   if(!InpShowPivots)
      return;

   double h = iHigh (_Symbol, PERIOD_D1, 1);
   double l = iLow  (_Symbol, PERIOD_D1, 1);
   double c = iClose(_Symbol, PERIOD_D1, 1);
   if(h <= 0.0 || l <= 0.0 || c <= 0.0)
      return;

   datetime tL = iTime(_Symbol, PERIOD_D1, 0);
   if(tL <= 0)
      return;
   datetime tR = RightEdge();

   double pp = (h + l + c) / 3.0;
   double rg = h - l;
   double lv[7];
   string nm[7];
   lv[0] = l - 2.0 * (h - pp); nm[0] = "S3";
   lv[1] = pp - rg;            nm[1] = "S2";
   lv[2] = 2.0 * pp - h;       nm[2] = "S1";
   lv[3] = pp;                 nm[3] = "PP";
   lv[4] = 2.0 * pp - l;       nm[4] = "R1";
   lv[5] = pp + rg;            nm[5] = "R2";
   lv[6] = h + 2.0 * (pp - l); nm[6] = "R3";

   for(int k = 0; k < 7; k++)
     {
      bool  mainLine = (k == 3);
      string id = "PIV_" + nm[k];
      DrawSegment(id, tL, tR, lv[k], mainLine ? THEME_GOLD : THEME_PIVOT,
                  mainLine ? 2 : 1, mainLine ? STYLE_SOLID : STYLE_DOT);
      DrawLabel(id + "L", tR, lv[k], nm[k] + "  " + PriceStr(lv[k]),
                mainLine ? THEME_GOLD : THEME_PIVOT, UI_FS_SM);
     }
  }

//+------------------------------------------------------------------+
//|   T R A D E   P L A N  —  rocket + entry / SL / TP (animated)    |
//+------------------------------------------------------------------+
void DrawTradePlan()
  {
   //--- لا خطة: نظّف مرة واحدة فقط ثم اخرج
   bool revealed = (!InpRevealOnTouch || g_st.zoneTouched);
   bool valid = (InpShowTradePlan && revealed && g_st.legValid &&
                 g_st.lastSignalDir != 0 && g_st.lastSignalTime > 0 &&
                 g_st.lastSignalBar >= g_st.legEndBar);
   if(!valid)
     {
      if(g_st.planBar != 0)
        {
         ClearGroup("PLAN_");
         g_st.planBar = 0;
        }
      return;
     }

   //--- إشارة جديدة: امسح خطة الإشارة السابقة
   if(g_st.planBar != g_st.lastSignalTime)
     {
      ClearGroup("PLAN_");
      g_st.planBar = g_st.lastSignalTime;
     }

   int      dir   = g_st.lastSignalDir;
   double   entry = g_st.lastSignalPrice;
   double   sl    = FibRetPrice(InpPlanSlFib);
   double   tp1   = FibExtPrice(InpPlanTp1Fib);
   double   tp2   = FibExtPrice(InpPlanTp2Fib);
   datetime tL    = g_st.lastSignalTime;
   datetime tR    = RightEdge();
   double   atr   = (g_st.lastAtr > 0.0) ? g_st.lastAtr : MathAbs(entry) * 0.001;

   //--- خط الدخول
   DrawSegment("PLAN_ENTRY", tL, tR, entry, THEME_NEON, 2, STYLE_SOLID);
   DrawLabel("PLAN_ENTRYL", tR, entry,
             StringFormat("%s  %s", (dir > 0 ? "BUY" : "SELL"), PriceStr(entry)),
             THEME_NEON, UI_FS);

   //--- وقف الخسارة عند مستوى فيبوناتشي
   DrawSegment("PLAN_SL", tL, tR, sl, THEME_SL, AnimWidth(1, 2), STYLE_DASH);
   DrawLabel("PLAN_SLL", tR, sl,
             StringFormat("SL %.3f  %s", InpPlanSlFib, PriceStr(sl)), THEME_SL, UI_FS_SM);

   //--- الأهداف عند امتدادات فيبوناتشي
   DrawSegment("PLAN_TP1", tL, tR, tp1, AnimColor(THEME_TP, THEME_TP_HOT), AnimWidth(2, 3), STYLE_DASH);
   DrawLabel("PLAN_TP1L", tR, tp1,
             StringFormat("TP1 %.3f  %s", InpPlanTp1Fib, PriceStr(tp1)),
             AnimColor(THEME_TP, THEME_TP_HOT), UI_FS_SM);

   DrawSegment("PLAN_TP2", tL, tR, tp2, THEME_TP, AnimWidth(1, 2), STYLE_DOT);
   DrawLabel("PLAN_TP2L", tR, tp2,
             StringFormat("TP2 %.3f  %s", InpPlanTp2Fib, PriceStr(tp2)), THEME_TP, UI_FS_SM);

   //--- نسبة العائد إلى المخاطرة
   double risk   = MathAbs(entry - sl);
   double reward = MathAbs(tp1 - entry);
   if(risk > 0.0)
      DrawLabel("PLAN_RR", tR, entry + (double)dir * atr * 0.45,
                StringFormat("R:R  1 : %.2f", reward / risk), THEME_TEXT_DIM, UI_FS_SM);
  }

//+------------------------------------------------------------------+
//|  A P P R O A C H  —  "GANN BUY" before price touches the line    |
//+------------------------------------------------------------------+
void DrawApproachMarker()
  {
   int dir = g_st.legValid ? g_st.legDir : 0;
   double atr = g_st.lastAtr;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool   armed = false;
   double level = 0.0;
   string source = "";

   if(InpShowApproachArrow && dir != 0 && atr > 0.0 && bid > 0.0)
     {
      double thr    = atr * InpApproachAtr;
      int    curBar = Bars(_Symbol, _Period) - 1;

      //--- زاوية جان المستخدمة كمرشّح
      double gv = GannValueAt(GannFilterRatioValue(), curBar);
      if(gv > 0.0 && MathAbs(bid - gv) <= thr &&
         ((dir > 0 && bid >= gv) || (dir < 0 && bid <= gv)))
        {
         armed  = true;
         level  = gv;
         source = "GANN";
        }

      //--- خط الاتجاه التلقائي (أولوية أعلى إن كان أقرب)
      double tv = 0.0;
      if(dir > 0 && HasSupTrendline())
         tv = TrendlineValueAt(g_st.prevLoBar, g_st.prevLoPrice, g_st.lastLoBar, g_st.lastLoPrice, curBar);
      if(dir < 0 && HasResTrendline())
         tv = TrendlineValueAt(g_st.prevHiBar, g_st.prevHiPrice, g_st.lastHiBar, g_st.lastHiPrice, curBar);
      if(tv > 0.0 && MathAbs(bid - tv) <= thr &&
         ((dir > 0 && bid >= tv) || (dir < 0 && bid <= tv)))
        {
         if(!armed || MathAbs(bid - tv) < MathAbs(bid - level))
           {
            armed  = true;
            level  = tv;
            source = "TREND";
           }
        }
     }

   //--- انطفأت العلامة: نظّف مرة واحدة
   if(!armed)
     {
      if(g_st.apprActive)
        {
         ClearGroup("APPR_");
         g_st.apprActive = false;
        }
      return;
     }
   datetime t = iTime(_Symbol, _Period, 0);
   if(t <= 0)
      return;
   g_st.apprActive = true;

   //--- السهم أسفل المستوى للشراء، أعلاه للبيع، مع نبضة حركة
   double gap  = atr * (0.45 + (InpAnimate ? MathAbs(AnimBob(0.12)) : 0.0));
   double pArw = level - (double)dir * gap;

   color c = (dir > 0) ? AnimColor(THEME_BUY, THEME_NEON) : AnimColor(THEME_SELL, THEME_GOLD);
   DrawArrowObj("APPR_ARROW", t, pArw, (uchar)(dir > 0 ? ARROW_BUY_CODE : ARROW_SELL_CODE),
                c, AnimWidth(2, 4), (dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM));

   string txt = source + (dir > 0 ? " BUY" : " SELL");
   DrawTag("APPR_TEXT", t, pArw - (double)dir * atr * 0.55, txt, c, UI_FS,
           (dir > 0 ? ANCHOR_UPPER : ANCHOR_LOWER));

   //--- خط رفيع يوضّح المستوى الذي يقترب منه السعر
   DrawSegment("APPR_LVL", (datetime)(t - (datetime)(PeriodSeconds() * 6)),
               RightEdge(), level, c, 1, STYLE_DOT);
  }

//+------------------------------------------------------------------+
//|      A D R E N A L I N E   T R E N D   B A N N E R               |
//+------------------------------------------------------------------+
void DrawAdrenaline()
  {
   //--- مطفأة: احذف اللافتة مرة واحدة
   if(!g_uiEnabled || !InpShowAdrenaline || g_st.adrState == 0)
     {
      if(g_st.adrShown)
        {
         ObjectsDeleteAll(0, Prefix() + "ADRB_");
         g_st.adrShown = false;
        }
      return;
     }

   bool  on       = (g_st.adrState > 0);
   bool  flashing = (g_st.adrFlash > 0);
   color base     = on ? THEME_ADR_ON : THEME_ADR_OFF;

   //--- أثناء الوميض تنبض الحدود والنص، ثم تستقر اللافتة على لون ثابت
   color border = flashing ? AnimColor(base, THEME_TEXT) : base;
   color text   = flashing ? AnimColor(THEME_TEXT, base) : base;
   color fill   = ColBlend(base, ChartBg(), flashing ? 0.30 : 0.15);

   //--- الأصل يُحسب من زاوية الشارت المختارة (كل كائنات الواجهة CORNER_LEFT_UPPER داخلياً)
   int chartW = Undpi((int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS));
   int chartH = Undpi((int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS));
   int w = UI_ADR_W;
   int h = UI_ADR_H;
   bool right = (InpAdrenalineCorner == PC_RIGHT_UPPER || InpAdrenalineCorner == PC_RIGHT_LOWER);
   bool lower = (InpAdrenalineCorner == PC_LEFT_LOWER  || InpAdrenalineCorner == PC_RIGHT_LOWER);
   int x = right ? (int)MathMax(2, chartW - w - InpAdrenalineX) : (int)MathMax(2, InpAdrenalineX);
   int y = lower ? (int)MathMax(2, chartH - h - InpAdrenalineY) : (int)MathMax(2, InpAdrenalineY);

   UiRect("ADRB_BG", x, y, w, h, fill, border);
   UiCell("ADRB_TXT", x + 2, y + 3, w - 4, h - 6,
          (on ? "ADRENALINE   ON" : "ADRENALINE   OFF"), text, fill, UI_FS_BIG);
   g_st.adrShown = true;
  }

//--- إعادة رسم كل الطبقات السعرية دفعة واحدة
void RedrawAll()
  {
   if(!g_uiEnabled)
      return;
   DrawFibonacci();
   DrawGannFan();
   DrawSquareOf9();
   DrawTrendlines();
   DrawPivots();
   DrawTradePlan();
   DrawApproachMarker();
   DrawAdrenaline();
   ChartRedraw();
  }

//--- تحديث الطبقات المتحركة فقط (يُستدعى من المؤقّت)
void AnimateOverlays()
  {
   if(!g_uiEnabled)
      return;
   bool before = (g_st.planBar != 0) || g_st.apprActive || g_st.adrShown;
   if(g_st.adrFlash > 0)
      g_st.adrFlash--;
   DrawTradePlan();
   DrawApproachMarker();
   DrawAdrenaline();
   bool after  = (g_st.planBar != 0) || g_st.apprActive || g_st.adrShown;
   if(before || after)               // لا إعادة رسم عندما لا يوجد شيء متحرك
      ChartRedraw();
  }

//+------------------------------------------------------------------+
//|                  U I  —  DASHBOARD (pixel objects)               |
//+------------------------------------------------------------------+

//--- الارتفاع الكلي للوحة بوحدات التصميم (يجب أن يطابق BuildPanel)
int PanelHeight()
  {
   int h = UI_HEAD_H + UI_PAD;                          // header + padding
   h += UI_ROW_H + UI_ROW_GAP;                          // symbol / tf / spread
   h += UI_SIG_H + UI_ROW_GAP;                          // master signal box
   h += UI_ROW_H + UI_ROW_GAP;                          // score bar
   h += UI_SEP_H + UI_ROW_GAP + 2;                      // separator 1
   h += UI_ROW_SM + UI_ROW_GAP;                         // table header
   h += ADR_TF_COUNT * (UI_ROW_SM + UI_ROW_GAP);        // timeframe rows
   h += 2 + UI_SEP_H + UI_ROW_GAP + 2;                  // separator 2
   h += ADR_DETAIL_ROWS * (UI_ROW_SM + UI_ROW_GAP);     // detail rows
   h += 2 + UI_SEP_H + UI_ROW_GAP;                      // separator 3
   h += UI_ROW_SM + UI_PAD;                             // footer
   return h;
  }

//--- حساب أصل اللوحة حسب الزاوية المختارة (دائماً CORNER_LEFT_UPPER داخلياً)
void ComputeOrigin()
  {
   int cw = Undpi((int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS));
   int ch = Undpi((int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS));
   bool right = (InpPanelCorner == PC_RIGHT_UPPER || InpPanelCorner == PC_RIGHT_LOWER);
   bool lower = (InpPanelCorner == PC_LEFT_LOWER  || InpPanelCorner == PC_RIGHT_LOWER);

   g_baseX = right ? (int)MathMax(2, cw - UI_PANEL_W - InpPanelX) : InpPanelX;
   g_baseY = lower ? (int)MathMax(2, ch - PanelHeight() - InpPanelY) : InpPanelY;
  }

//--- تهيئة مشتركة لأي كائن واجهة
bool UiCreate(const string id, const ENUM_OBJECT type, string &outName)
  {
   outName = Prefix() + id;
   if(ObjectFind(0, outName) < 0)
     {
      if(!ObjectCreate(0, outName, type, 0, 0, 0))
         return false;
     }
   ObjectSetInteger(0, outName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, outName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, outName, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, outName, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, outName, OBJPROP_BACK,       false);
   return true;
  }

//--- خلفية / شريط ملوّن
bool UiRect(const string id, const int x, const int y, const int w, const int h,
            const color bg, const color border)
  {
   string n;
   if(!UiCreate(id, OBJ_RECTANGLE_LABEL, n))
      return false;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   Dpi(x));
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   Dpi(y));
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       Dpi(w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       Dpi(h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      UI_ZBACK);
   return true;
  }

//--- خلية نصّية: تُبنى من OBJ_BUTTON لأن OBJ_LABEL قد يُحجب خلف المستطيلات
bool UiCell(const string id, const int x, const int y, const int w, const int h,
            const string text, const color fg, const color bg,
            const int fs = UI_FS, const string font = UI_FONT)
  {
   string n;
   if(!UiCreate(id, OBJ_BUTTON, n))
      return false;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    Dpi(x));
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    Dpi(y));
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        Dpi(w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        Dpi(h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     fs);
   ObjectSetString (0, n, OBJPROP_FONT,         font);
   ObjectSetString (0, n, OBJPROP_TEXT,         text);
   ObjectSetInteger(0, n, OBJPROP_STATE,        false);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,       UI_ZFRONT);
   return true;
  }

//--- تحديث خلية موجودة (لا إعادة إنشاء أبداً)
void UiSet(const string id, const string text, const color fg = clrNONE, const color bg = clrNONE)
  {
   string n = Prefix() + id;
   if(ObjectFind(0, n) < 0)
      return;
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   if(fg != clrNONE)
      ObjectSetInteger(0, n, OBJPROP_COLOR, fg);
   if(bg != clrNONE)
     {
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
     }
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
  }

//--- إظهار/إخفاء كائن واجهة
void UiShow(const string id, const bool visible)
  {
   string n = Prefix() + id;
   if(ObjectFind(0, n) < 0)
      return;
   ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }

//--- الموضع الأفقي لعمود في جدول الأطر الزمنية
int ColX(const int col)
  {
   int x = g_baseX + UI_PAD;
   for(int k = 0; k < col; k++)
      x += g_colW[k];
   return x;
  }

//--- بناء/إعادة تموضع اللوحة (idempotent: يمكن استدعاؤها عند تغيّر حجم الشارت)
void BuildPanel()
  {
   if(!g_uiEnabled || !InpShowPanel)
      return;

   ComputeOrigin();

   int x  = g_baseX;
   int y  = g_baseY;
   int w  = UI_PANEL_W;
   int cx = x + UI_PAD;
   int cw = w - 2 * UI_PAD;

   //--- الخلفية الرئيسية
   UiRect("BG", x, y, w, PanelHeight(), THEME_BG, THEME_NEON_DIM);

   //--- شريط العنوان
   UiRect("HEAD", x, y, w, UI_HEAD_H, THEME_HEADER, THEME_HEADER);
   UiCell("TITLE", cx, y + 5, cw - UI_BTN_W - UI_PAD, UI_HEAD_H - 10,
          "ADRENALINE  B1000", THEME_GOLD, THEME_HEADER, UI_FS_TITLE);
   UiCell("BTN_MIN", x + w - UI_BTN_W - UI_PAD, y + 5, UI_BTN_W, UI_HEAD_H - 10,
          g_st.collapsed ? "+" : "-", THEME_NEON, THEME_BORDER, UI_FS_TITLE);

   int ry = y + UI_HEAD_H + UI_PAD;

   //--- صف: الرمز / الإطار / السبريد
   UiCell("SYM", cx,                  ry, cw / 3, UI_ROW_H, _Symbol, THEME_NEON,     THEME_BG, UI_FS);
   UiCell("TFC", cx + cw / 3,         ry, cw / 3, UI_ROW_H, "-",     THEME_TEXT,     THEME_BG, UI_FS);
   UiCell("SPR", cx + 2 * (cw / 3),   ry, cw / 3, UI_ROW_H, "-",     THEME_TEXT_DIM, THEME_BG, UI_FS);
   ry += UI_ROW_H + UI_ROW_GAP;

   //--- صف: الإشارة الرئيسية
   UiCell("SIGBOX", cx, ry, cw, UI_SIG_H, "WAITING FOR SETUP", THEME_NEUTRAL, THEME_BG_ALT, UI_FS_BIG);
   ry += UI_SIG_H + UI_ROW_GAP;

   //--- صف: شريط نقاط التوافق
   UiCell("SCORELBL", cx, ry, 64, UI_ROW_H, "SCORE", THEME_TEXT_DIM, THEME_BG, UI_FS_SM);
   int segW = (cw - 64 - 34) / ADR_MAX_SCORE;
   for(int k = 0; k < ADR_MAX_SCORE; k++)
      UiCell(StringFormat("SEG%d", k), cx + 64 + k * segW, ry + 4, segW - 2, UI_ROW_H - 8,
             "", THEME_BG, THEME_BORDER, UI_FS_SM);
   UiCell("SCORENUM", cx + cw - 32, ry, 32, UI_ROW_H, "0/8", THEME_TEXT, THEME_BG, UI_FS_SM);
   ry += UI_ROW_H + UI_ROW_GAP;

   //--- فاصل 1
   UiRect("SEP1", cx, ry, cw, UI_SEP_H, THEME_BORDER, THEME_BORDER);
   ry += UI_SEP_H + UI_ROW_GAP + 2;

   //--- رأس جدول الأطر الزمنية
   string head[5] = {"TF", "TREND", "RSI", "STRUCTURE", "SIGNAL"};
   for(int c = 0; c < 5; c++)
      UiCell(StringFormat("TH%d", c), ColX(c), ry, g_colW[c] - 2, UI_ROW_SM,
             head[c], THEME_NEON, THEME_HEADER, UI_FS_SM);
   ry += UI_ROW_SM + UI_ROW_GAP;

   //--- صفوف الأطر الزمنية
   for(int r = 0; r < ADR_TF_COUNT; r++)
     {
      color rowBg = (r % 2 == 0) ? THEME_BG : THEME_BG_ALT;
      for(int c = 0; c < 5; c++)
         UiCell(StringFormat("R%dC%d", r, c), ColX(c), ry, g_colW[c] - 2, UI_ROW_SM,
                (c == 0 ? TfName(g_tf[r]) : "..."),
                (c == 0 ? THEME_GOLD : THEME_TEXT_DIM), rowBg,
                (c == 0 ? UI_FS : UI_FS_SM), (c == 0 ? UI_FONT : UI_FONT_MONO));
      ry += UI_ROW_SM + UI_ROW_GAP;
     }

   //--- فاصل 2
   ry += 2;
   UiRect("SEP2", cx, ry, cw, UI_SEP_H, THEME_BORDER, THEME_BORDER);
   ry += UI_SEP_H + UI_ROW_GAP + 2;

   //--- صفوف تفاصيل الموجة / جان / المنطقة الذهبية
   string keys [ADR_DETAIL_ROWS] = {"LEG", "GZ", "GANN", "SQ9", "LAST"};
   string names[ADR_DETAIL_ROWS] = {"IMPULSE LEG", "GOLDEN ZONE", "GANN 1x1", "SQUARE OF 9", "LAST SIGNAL"};
   for(int k = 0; k < ADR_DETAIL_ROWS; k++)
     {
      UiCell("K" + keys[k], cx, ry, UI_KEY_W, UI_ROW_SM, names[k], THEME_TEXT_DIM, THEME_BG, UI_FS_SM);
      UiCell("V" + keys[k], cx + UI_KEY_W, ry, cw - UI_KEY_W, UI_ROW_SM, "-", THEME_TEXT, THEME_BG,
             UI_FS_SM, UI_FONT_MONO);
      ry += UI_ROW_SM + UI_ROW_GAP;
     }

   //--- فاصل 3 + التذييل
   ry += 2;
   UiRect("SEP3", cx, ry, cw, UI_SEP_H, THEME_BORDER, THEME_BORDER);
   ry += UI_SEP_H + UI_ROW_GAP;
   UiCell("PULSE",  cx,           ry, 16,           UI_ROW_SM, "•",        THEME_BUY,      THEME_BG, UI_FS_TITLE);
   UiCell("STATUS", cx + 18,      ry, cw - 18 - 96, UI_ROW_SM, "LIVE",     THEME_TEXT_DIM, THEME_BG, UI_FS_SM);
   UiCell("CLOCK",  cx + cw - 96, ry, 96,           UI_ROW_SM, "--:--:--", THEME_TEXT_DIM, THEME_BG,
          UI_FS_SM, UI_FONT_MONO);

   g_st.uiBuilt = true;
   ChartRedraw();
  }

//--- طيّ/فرد اللوحة
void ApplyCollapse()
  {
   bool vis = !g_st.collapsed;
   string hide[] = {"BG", "SYM", "TFC", "SPR", "SIGBOX", "SCORELBL", "SCORENUM",
                    "SEP1", "SEP2", "SEP3", "PULSE", "STATUS", "CLOCK"};
   for(int k = 0; k < ArraySize(hide); k++)
      UiShow(hide[k], vis);
   for(int k = 0; k < ADR_MAX_SCORE; k++)
      UiShow(StringFormat("SEG%d", k), vis);
   for(int c = 0; c < 5; c++)
      UiShow(StringFormat("TH%d", c), vis);
   for(int r = 0; r < ADR_TF_COUNT; r++)
      for(int c = 0; c < 5; c++)
         UiShow(StringFormat("R%dC%d", r, c), vis);

   string keys[ADR_DETAIL_ROWS] = {"LEG", "GZ", "GANN", "SQ9", "LAST"};
   for(int k = 0; k < ADR_DETAIL_ROWS; k++)
     {
      UiShow("K" + keys[k], vis);
      UiShow("V" + keys[k], vis);
     }
   UiSet("BTN_MIN", g_st.collapsed ? "+" : "-");
   ChartRedraw();
  }

//--- قيم سطر إطار زمني في الجدول
void TfRowValues(const int idx, string &trend, color &trendClr, string &rsiTxt, color &rsiClr,
                 string &structTxt, color &structClr, string &sig, color &sigClr)
  {
   trend     = "n/a"; trendClr  = THEME_NEUTRAL;
   rsiTxt    = "--";  rsiClr    = THEME_NEUTRAL;
   structTxt = "--";  structClr = THEME_NEUTRAL;
   sig       = "--";  sigClr    = THEME_NEUTRAL;

   double f = 0.0, s = 0.0, r = 0.0;
   bool okF = ReadOne(g_hTfEmaF[idx], 0, 0, f);
   bool okS = ReadOne(g_hTfEmaS[idx], 0, 0, s);
   bool okR = ReadOne(g_hTfRsi [idx], 0, 0, r);

   int tScore = 0;

   if(okF && okS && f > 0.0 && s > 0.0)
     {
      if(f > s)      { trend = "BULL"; trendClr = THEME_BUY;     tScore++; }
      else if(f < s) { trend = "BEAR"; trendClr = THEME_SELL;    tScore--; }
      else           { trend = "FLAT"; trendClr = THEME_NEUTRAL;           }
     }

   if(okR)
     {
      rsiTxt = DoubleToString(r, 1);
      rsiClr = (r >= 60.0) ? THEME_BUY : ((r <= 40.0) ? THEME_SELL : THEME_TEXT_DIM);
      if(r > 55.0) tScore++;
      if(r < 45.0) tScore--;
     }

   //--- بنية السوق: مقارنة نافذتين متتاليتين من القمم/القيعان
   int win = (int)MathMax(6, InpSwingN * 3);
   int hi1 = iHighest(_Symbol, g_tf[idx], MODE_HIGH, win, 1);
   int lo1 = iLowest (_Symbol, g_tf[idx], MODE_LOW,  win, 1);
   int hi2 = iHighest(_Symbol, g_tf[idx], MODE_HIGH, win, win + 1);
   int lo2 = iLowest (_Symbol, g_tf[idx], MODE_LOW,  win, win + 1);
   if(hi1 >= 0 && lo1 >= 0 && hi2 >= 0 && lo2 >= 0)
     {
      double h1 = iHigh(_Symbol, g_tf[idx], hi1);
      double l1 = iLow (_Symbol, g_tf[idx], lo1);
      double h2 = iHigh(_Symbol, g_tf[idx], hi2);
      double l2 = iLow (_Symbol, g_tf[idx], lo2);
      if(h1 > 0.0 && l1 > 0.0 && h2 > 0.0 && l2 > 0.0)
        {
         if(h1 > h2 && l1 > l2)      { structTxt = "HH / HL"; structClr = THEME_BUY;     tScore++; }
         else if(h1 < h2 && l1 < l2) { structTxt = "LH / LL"; structClr = THEME_SELL;    tScore--; }
         else                        { structTxt = "RANGE";   structClr = THEME_NEUTRAL;           }
        }
     }

   if(tScore >= 2)       { sig = "BUY";  sigClr = THEME_BUY;     }
   else if(tScore <= -2) { sig = "SELL"; sigClr = THEME_SELL;    }
   else                  { sig = "WAIT"; sigClr = THEME_NEUTRAL; }
  }

//--- تحديث محتوى اللوحة من الحالة
void RefreshPanel()
  {
   if(!g_uiEnabled || !InpShowPanel || !g_st.uiBuilt || g_st.collapsed)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   sprd  = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- الصف العلوي
   UiSet("TFC", TfName(Period()), THEME_TEXT);
   UiSet("SPR", StringFormat("SPR %d", (int)sprd), (sprd > 30 ? THEME_SELL : THEME_TEXT_DIM));

   //--- الإشارة الرئيسية
   string sigTxt = "WAITING FOR SETUP";
   color  sigFg  = THEME_NEUTRAL;
   if(g_st.lastSignalDir > 0)      { sigTxt = "BUY  SIGNAL  ▲";  sigFg = THEME_BUY;  }
   else if(g_st.lastSignalDir < 0) { sigTxt = "SELL  SIGNAL  ▼"; sigFg = THEME_SELL; }
   UiSet("SIGBOX", sigTxt, sigFg, THEME_BG_ALT);

   //--- شريط النقاط
   int   sc    = Clamp(g_st.lastSignalScore, 0, ADR_MAX_SCORE);
   color scClr = (g_st.lastSignalDir > 0) ? THEME_BUY
                 : ((g_st.lastSignalDir < 0) ? THEME_SELL : THEME_NEON);
   for(int k = 0; k < ADR_MAX_SCORE; k++)
      UiSet(StringFormat("SEG%d", k), "", THEME_BG, (k < sc ? scClr : THEME_BORDER));
   UiSet("SCORENUM", StringFormat("%d/%d", sc, ADR_MAX_SCORE), THEME_TEXT);

   //--- جدول الأطر الزمنية
   for(int r = 0; r < ADR_TF_COUNT; r++)
     {
      string trend, rsiTxt, structTxt, sig;
      color  tc, rc, stc, sgc;
      TfRowValues(r, trend, tc, rsiTxt, rc, structTxt, stc, sig, sgc);
      UiSet(StringFormat("R%dC1", r), trend,     tc);
      UiSet(StringFormat("R%dC2", r), rsiTxt,    rc);
      UiSet(StringFormat("R%dC3", r), structTxt, stc);
      UiSet(StringFormat("R%dC4", r), sig,       sgc);
     }

   //--- تفاصيل الموجة
   if(g_st.legValid)
     {
      double pts = (point > 0.0) ? LegRange() / point : 0.0;
      UiSet("VLEG", StringFormat("%s  %s > %s  (%.0f pt)",
                                 (g_st.legDir > 0 ? "UP" : "DOWN"),
                                 PriceStr(g_st.legStartPrice), PriceStr(g_st.legEndPrice), pts),
            (g_st.legDir > 0 ? THEME_BUY : THEME_SELL));

      double a = FibRetPrice(InpGZ_Start);
      double b = FibRetPrice(InpGZ_End);
      bool inZone = (bid <= MathMax(a, b) && bid >= MathMin(a, b));
      UiSet("VGZ", StringFormat("%s - %s %s", PriceStr(MathMin(a, b)), PriceStr(MathMax(a, b)),
                                (inZone ? " [IN ZONE]" : "")),
            (inZone ? THEME_GOLD : THEME_TEXT));

      int    curBar = Bars(_Symbol, _Period) - 1;
      double g11    = GannValueAt(1.0, curBar);
      UiSet("VGANN", (g11 <= 0.0) ? "-"
            : StringFormat("%s   price %s", PriceStr(g11), (bid > g11 ? "ABOVE" : "BELOW")),
            (g11 <= 0.0 ? THEME_TEXT_DIM : (bid > g11 ? THEME_BUY : THEME_SELL)));

      double anchor = Sq9Anchor();
      g_sq9Scale = Sq9Scale(anchor);
      UiSet("VSQ9", StringFormat("%s / %s  (+/-%.0f deg)", PriceStr(Sq9Level(anchor, -1)),
                                 PriceStr(Sq9Level(anchor, +1)), InpSq9Degrees), THEME_GOLD_DIM);
     }
   else
     {
      UiSet("VLEG",  "no confirmed leg", THEME_TEXT_DIM);
      UiSet("VGZ",   "-", THEME_TEXT_DIM);
      UiSet("VGANN", "-", THEME_TEXT_DIM);
      UiSet("VSQ9",  "-", THEME_TEXT_DIM);
     }

   //--- آخر إشارة
   if(g_st.lastSignalDir != 0 && g_st.lastSignalTime > 0)
      UiSet("VLAST", StringFormat("%s %s @ %s (%d/%d)",
                                  TimeToString(g_st.lastSignalTime, TIME_DATE | TIME_MINUTES),
                                  (g_st.lastSignalDir > 0 ? "BUY" : "SELL"),
                                  PriceStr(g_st.lastSignalPrice),
                                  g_st.lastSignalScore, ADR_MAX_SCORE),
            (g_st.lastSignalDir > 0 ? THEME_BUY : THEME_SELL));
   else
      UiSet("VLAST", "none yet", THEME_TEXT_DIM);

   //--- التذييل
   bool connected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   UiSet("STATUS", connected ? "LIVE  •  ENGINE OK" : "DISCONNECTED",
         connected ? THEME_TEXT_DIM : THEME_SELL);
   UiSet("CLOCK", TimeToString(TimeCurrent(), TIME_SECONDS), THEME_TEXT_DIM);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|                        A L E R T S                               |
//+------------------------------------------------------------------+
void FireAlert(const int dir, const double price, const int score, const datetime barTime)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   if(g_st.lastAlertBar == barTime)
      return;
   g_st.lastAlertBar = barTime;

   string msg = StringFormat("Adrenaline B1000 | %s %s | %s @ %s | score %d/%d",
                             _Symbol, TfName(Period()),
                             (dir > 0 ? "BUY" : "SELL"), PriceStr(price), score, ADR_MAX_SCORE);
   PrintFormat("[ADR] %s", msg);
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertPush)
      SendNotification(msg);
   if(InpAlertSound && StringLen(InpAlertSoundFile) > 0)
      PlaySound(InpAlertSoundFile);
  }

//+------------------------------------------------------------------+
//|                       E V E N T S                                |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- التحقق من الإدخالات (fail fast)
   if(InpSwingN < 2)
     {
      Print("[ADR] Swing strength must be >= 2");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpEmaFast >= InpEmaSlow)
     {
      Print("[ADR] EMA fast must be smaller than EMA slow");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpGZ_End <= InpGZ_Start || InpGZ_Start <= 0.0 || InpGZ_End >= 1.0)
     {
      Print("[ADR] Golden Zone must satisfy 0 < start < end < 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSq9Degrees <= 0.0 || InpSq9Steps < 0)
     {
      Print("[ADR] Square of 9 settings are invalid");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_prefix    = "ADR" + IntegerToString(ChartID()) + "_";
   //--- في وضع الإكسبيرت لا رسم ولا لوحة: نسخة iCustom تشارك نفس الشارت والبادئة
   //--- مع النسخة المرئية، فتتصادم الكائنات وتُحذف عند إنهاء أيهما.
   g_uiEnabled = (!MQLInfoInteger(MQL_OPTIMIZATION) && !InpEaMode);

   //--- البافرات
   SetIndexBuffer(0, g_bufBuy,    INDICATOR_DATA);
   SetIndexBuffer(1, g_bufSell,   INDICATOR_DATA);
   SetIndexBuffer(2, g_bufSignal, INDICATOR_DATA);
   SetIndexBuffer(3, g_bufScore,  INDICATOR_DATA);
   SetIndexBuffer(4, g_bufLegDir,  INDICATOR_DATA);
   SetIndexBuffer(5, g_bufZoneHi,  INDICATOR_DATA);
   SetIndexBuffer(6, g_bufZoneLo,  INDICATOR_DATA);
   SetIndexBuffer(7, g_bufLegOrig, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_BUY_CODE);
   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_SELL_CODE);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(7, PLOT_EMPTY_VALUE, 0.0);

   g_warmup = (int)MathMax(InpSwingN * 2 + 2, MathMax(InpEmaSlow, InpRsiPeriod) + 2);
   g_warmup = (int)MathMax(g_warmup, InpAtrPeriod + 2);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, g_warmup);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, g_warmup);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Adrenaline B1000 (%d, %.3f-%.3f, min %d)",
                                   InpSwingN, InpGZ_Start, InpGZ_End, InpMinScore));

   //--- مقابض الإطار الحالي
   g_hEmaF = iMA (_Symbol, PERIOD_CURRENT, InpEmaFast,   0, MODE_EMA, PRICE_CLOSE);
   g_hEmaS = iMA (_Symbol, PERIOD_CURRENT, InpEmaSlow,   0, MODE_EMA, PRICE_CLOSE);
   g_hRsi  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   g_hAtr  = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_hEmaF == INVALID_HANDLE || g_hEmaS == INVALID_HANDLE ||
      g_hRsi  == INVALID_HANDLE || g_hAtr  == INVALID_HANDLE)
     {
      LogErr("failed to create chart timeframe handles");
      return INIT_FAILED;
     }

   //--- مقابض الإطار الأعلى
   if(InpUseMtfFilter)
     {
      g_hMtfF = iMA(_Symbol, InpMtfTimeframe, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
      g_hMtfS = iMA(_Symbol, InpMtfTimeframe, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hMtfF == INVALID_HANDLE || g_hMtfS == INVALID_HANDLE)
        {
         LogErr("failed to create MTF handles");
         return INIT_FAILED;
        }
     }

   //--- مقابض لوحة الأطر الزمنية
   for(int k = 0; k < ADR_TF_COUNT; k++)
     {
      g_hTfEmaF[k] = INVALID_HANDLE;
      g_hTfEmaS[k] = INVALID_HANDLE;
      g_hTfRsi [k] = INVALID_HANDLE;
     }
   if(g_uiEnabled && InpShowPanel)
     {
      for(int k = 0; k < ADR_TF_COUNT; k++)
        {
         g_hTfEmaF[k] = iMA (_Symbol, g_tf[k], InpEmaFast,   0, MODE_EMA, PRICE_CLOSE);
         g_hTfEmaS[k] = iMA (_Symbol, g_tf[k], InpEmaSlow,   0, MODE_EMA, PRICE_CLOSE);
         g_hTfRsi [k] = iRSI(_Symbol, g_tf[k], InpRsiPeriod, PRICE_CLOSE);
        }
     }

   //--- الحالة الابتدائية
   g_st.Reset();
   g_st.collapsed    = false;
   g_st.uiBuilt      = false;
   g_st.pulse        = 0;
   g_st.animFrame    = 0;
   g_st.trendDir     = 0;
   g_st.adrState     = 0;
   g_st.adrFlash     = 0;
   g_st.adrShown     = false;
   g_st.planBar      = 0;
   g_st.apprActive   = false;
   g_st.lastAlertBar = 0;
   g_st.lastBarTime  = 0;

   if(g_uiEnabled && InpShowPanel)
     {
      g_chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      g_chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      BuildPanel();
     }
   //--- مؤقّت واحد يخدم الحركة واللوحة معاً
   if(g_uiEnabled)
      EventSetMillisecondTimer((int)MathMax(50, InpAnimMs));

   PrintFormat("[ADR] initialised on %s %s | warm-up %d bars | min score %d/%d",
               _Symbol, TfName(Period()), g_warmup, InpMinScore, ADR_MAX_SCORE);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   if(g_hEmaF != INVALID_HANDLE) IndicatorRelease(g_hEmaF);
   if(g_hEmaS != INVALID_HANDLE) IndicatorRelease(g_hEmaS);
   if(g_hRsi  != INVALID_HANDLE) IndicatorRelease(g_hRsi);
   if(g_hAtr  != INVALID_HANDLE) IndicatorRelease(g_hAtr);
   if(g_hMtfF != INVALID_HANDLE) IndicatorRelease(g_hMtfF);
   if(g_hMtfS != INVALID_HANDLE) IndicatorRelease(g_hMtfS);
   for(int k = 0; k < ADR_TF_COUNT; k++)
     {
      if(g_hTfEmaF[k] != INVALID_HANDLE) IndicatorRelease(g_hTfEmaF[k]);
      if(g_hTfEmaS[k] != INVALID_HANDLE) IndicatorRelease(g_hTfEmaS[k]);
      if(g_hTfRsi [k] != INVALID_HANDLE) IndicatorRelease(g_hTfRsi [k]);
     }

   ObjectsDeleteAll(0, Prefix());
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < g_warmup + InpSwingN * 2 + 2)
      return 0;
   if(rates_total < prev_calculated)
      return 0;                                   // حارس حالة تبديل السيرفر

   //--- نطاق الحساب
   int limitStart = g_warmup;
   if(InpMaxBars > 0)
      limitStart = (int)MathMax(limitStart, rates_total - InpMaxBars);

   bool fullRebuild = (prev_calculated == 0);
   int  start;
   if(fullRebuild)
     {
      ArrayInitialize(g_bufBuy,    EMPTY_VALUE);
      ArrayInitialize(g_bufSell,   EMPTY_VALUE);
      ArrayInitialize(g_bufSignal,  0.0);
      ArrayInitialize(g_bufScore,   0.0);
      ArrayInitialize(g_bufLegDir,  0.0);
      ArrayInitialize(g_bufZoneHi,  0.0);
      ArrayInitialize(g_bufZoneLo,  0.0);
      ArrayInitialize(g_bufLegOrig, 0.0);
      g_st.Reset();
      start = limitStart;
     }
   else
      start = (int)MathMax(prev_calculated - 1, limitStart);

   if(start >= rates_total)
      return rates_total;

   //--- تحميل مؤشرات الإطار الحالي للنطاق المطلوب
   if(!LoadRange(g_hEmaF, start, rates_total, g_emaF) ||
      !LoadRange(g_hEmaS, start, rates_total, g_emaS) ||
      !LoadRange(g_hRsi,  start, rates_total, g_rsi)  ||
      !LoadRange(g_hAtr,  start, rates_total, g_atr))
      return prev_calculated;                     // بيانات غير جاهزة — أعد المحاولة بالتيك التالي

   bool legChanged = false;
   int  n = InpSwingN;

   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      g_bufBuy[i]    = EMPTY_VALUE;
      g_bufSell[i]   = EMPTY_VALUE;
      g_bufSignal[i]  = 0.0;
      g_bufScore[i]   = 0.0;
      g_bufLegDir[i]  = 0.0;
      g_bufZoneHi[i]  = 0.0;
      g_bufZoneLo[i]  = 0.0;
      g_bufLegOrig[i] = 0.0;

      //--- 1) تأكيد القمم والقيعان (على شموع مغلقة فقط لمنع إعادة الرسم)
      if(i <= rates_total - 2)
        {
         int c = i - n;
         if(c > g_st.checkedBar && c - n >= 0)
           {
            if(IsSwingHigh(high, c, n))
              {
               RegisterSwing(true, c, high[c], time[c]);
               legChanged = true;
              }
            else
               if(IsSwingLow(low, c, n))
                 {
                  RegisterSwing(false, c, low[c], time[c]);
                  legChanged = true;
                 }
            g_st.checkedBar = c;
           }
        }

      //--- 2) إبطال الموجة عند كسر مستوى 1.000 (على شموع مغلقة فقط)
      if(g_st.legValid && i > g_st.legEndBar && i <= rates_total - 2)
        {
         if((g_st.legDir > 0 && close[i] < g_st.legStartPrice) ||
            (g_st.legDir < 0 && close[i] > g_st.legStartPrice))
           {
            g_st.legValid = false;
            legChanged = true;
           }
        }

      //--- 3) تصدير حالة الموجة والمنطقة الذهبية (تُقرأ من الإكسبيرت عبر iCustom)
      if(g_st.legValid)
        {
         double zA = FibRetPrice(InpGZ_Start);
         double zB = FibRetPrice(InpGZ_End);
         g_bufLegDir[i]  = (double)g_st.legDir;
         g_bufZoneHi[i]  = MathMax(zA, zB);
         g_bufZoneLo[i]  = MathMin(zA, zB);
         g_bufLegOrig[i] = g_st.legStartPrice;
        }

      //--- 4) الإشارات على الشموع المغلقة فقط
      if(!InpShowArrows || i > rates_total - 2)
         continue;

      int dir   = 0;
      int score = EvaluateSignal(i, time, open, high, low, close, dir);
      if(dir == 0 || score <= 0)
         continue;

      double off = g_atr[i] * InpArrowOffsetAtr;
      if(dir > 0)
         g_bufBuy[i] = low[i] - off;
      else
         g_bufSell[i] = high[i] + off;

      g_bufSignal[i] = (double)dir;
      g_bufScore[i]  = (double)score;

      g_st.lastSignalBar   = i;
      g_st.lastSignalDir   = dir;
      g_st.lastSignalPrice = close[i];
      g_st.lastSignalScore = score;
      g_st.lastSignalTime  = time[i];
      g_st.legSignals++;

      //--- تنبيه على آخر شمعة مغلقة فقط، وفي التشغيل الحي فقط
      if(!fullRebuild && i == rates_total - 2)
         FireAlert(dir, close[i], score, time[i]);
     }

   //--- 5) خزّن ATR الأخير (تستخدمه طبقات الرسم والحركة)
   if(rates_total - 1 < ArraySize(g_atr))
      g_st.lastAtr = g_atr[rates_total - 1];

   //--- 6) انقلاب الاتجاه -> لافتة ADRENALINE ON / OFF
   int trendNow = (g_st.legValid ? g_st.legDir : 0);
   if(trendNow != 0 && trendNow != g_st.trendDir)
     {
      g_st.trendDir = trendNow;
      g_st.adrState = trendNow;
      g_st.adrFlash = InpAdrenalineFlashSec * FramesPerSecond();
      legChanged    = true;
      PrintFormat("[ADR] trend flip -> ADRENALINE %s", (trendNow > 0 ? "ON" : "OFF"));
     }

   //--- 7) كشف بلوغ منطقة OTE — يحدث داخل الشمعة، لذا يُفحص كل تيك
   if(g_st.legValid && !g_st.zoneTouched && ZoneReachedNow())
     {
      g_st.zoneTouched = true;
      legChanged = true;                          // أظهر المنطقة الآن
     }

   //--- 8) تحديث الرسومات عند شمعة جديدة أو تغيّر الموجة
   datetime curBarTime = time[rates_total - 1];
   if(g_uiEnabled && (legChanged || curBarTime != g_st.lastBarTime))
     {
      g_st.lastBarTime = curBarTime;
      RedrawAll();
      RefreshPanel();
     }

   return rates_total;                            // إشارة الجاهزية — إلزامي
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_uiEnabled)
      return;

   g_st.animFrame++;

   //--- كل إطار: الصاروخ وعلامة الاقتراب فقط (كائنات قليلة، تحديث في المكان)
   AnimateOverlays();

   //--- اللوحة وبيانات الأطر الزمنية مرة واحدة في الثانية تقريباً
   if(g_st.animFrame % FramesPerSecond() != 0)
      return;
   if(!InpShowPanel || !g_st.uiBuilt)
      return;

   //--- نبضة الحالة الحية
   if(InpPanelAnimate && !g_st.collapsed)
     {
      g_st.pulse = (g_st.pulse + 1) % 2;
      color pc = (g_st.pulse == 0) ? THEME_BUY : THEME_NEON;
      if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
         pc = THEME_SELL;
      UiSet("PULSE", (g_st.pulse == 0) ? "•" : "◦", pc);
     }

   RefreshPanel();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   //--- إعادة تموضع اللوحة عند تغيّر حجم الشارت فقط (لا عند كل تمرير)
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(w != g_chartW || h != g_chartH)
        {
         g_chartW = w;
         g_chartH = h;
         BuildPanel();
         ApplyCollapse();
         RefreshPanel();
        }
      return;
     }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(StringFind(sparam, Prefix()) != 0)
      return;

   //--- كل خلايا اللوحة أزرار: أعد ضبط الحالة حتى لا تبقى مضغوطة
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   if(sparam == Prefix() + "BTN_MIN")
     {
      g_st.collapsed = !g_st.collapsed;
      ApplyCollapse();
      RefreshPanel();
      return;
     }
   ChartRedraw();
  }
//+------------------------------------------------------------------+
