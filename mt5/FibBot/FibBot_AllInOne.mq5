//+------------------------------------------------------------------+
//|                                              FibBot_AllInOne.mq5 |
//|                                                                  |
//|  GENERATED FILE — do not edit. Built from the modules in         |
//|  mt5/FibBot/ by build-single-file.sh. Edit those and re-run it.  |
//|                                                                  |
//|  Single-file build for pasting straight into MetaEditor: copy    |
//|  this one file to MQL5\Experts\ and press F7. Behaviour is       |
//|  identical to the modular folder.                                |
//+------------------------------------------------------------------+
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property description "Fibonacci retracement setups: detect, draw, optionally trade."

#include <Trade\Trade.mqh>


//====================================================================
// Config.mqh
//====================================================================

//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|  CONFIG + STATE for FibBot: inputs, constants, shared structs.   |
//+------------------------------------------------------------------+

//--- CONFIG: enums -------------------------------------------------

// حالات آلة الإعداد — كل انتقال يقرره شمعة مغلقة فقط
enum ENUM_SETUP_STATE
  {
   SETUP_IDLE,             // nothing armed
   SETUP_ARMED,            // anchors frozen, waiting for price
   SETUP_IN_ZONE,          // price inside the entry band
   SETUP_TRIGGERED,        // confirmation closed, order sent
   SETUP_INVALIDATED,      // close beyond the leg origin
   SETUP_EXPIRED           // ran out of bars
  };

//--- CONFIG: inputs ------------------------------------------------

input group "=== Swing detection (non-repainting) ==="
input int    InpPivotLeft      = 5;      // Pivot: bars required to the left
input int    InpPivotRight     = 5;      // Pivot: bars required to the right (= confirmation lag)
input double InpMinLegAtr      = 2.0;    // Minimum leg size (x ATR)
input int    InpMaxLegBars     = 120;    // Reject a leg longer than this many bars
input int    InpAtrPeriod      = 14;     // ATR period

input group "=== Fibonacci setup ==="
input double InpEntryFibNear   = 0.618;  // Entry zone: shallow edge
input double InpEntryFibFar    = 0.786;  // Entry zone: deep edge
input double InpStopFib        = 1.000;  // Stop at this retracement (1.0 = leg origin)
input double InpStopAtrBuffer  = 0.5;    // Extra stop buffer (x ATR)
input double InpTp1Extension   = 1.000;  // TP1 (1.0 = retest of the leg extreme)
input double InpTp2Extension   = 1.272;  // TP2 extension
input double InpTp3Extension   = 1.618;  // TP3 extension
input int    InpSetupExpiryBars= 40;     // Cancel an armed setup after this many bars

input group "=== Confluence (Fibonacci levels do not count) ==="
input int    InpMinConfluence  = 2;      // Minimum confluence factors required
input bool   InpUseTrendFilter = true;   // Factor: leg agrees with the trend MA
input int    InpTrendMaPeriod  = 200;    // Trend MA period
input ENUM_TIMEFRAMES InpTrendTimeframe = PERIOD_CURRENT; // Trend MA timeframe
input bool   InpUseBosFactor   = true;   // Factor: leg broke the prior swing
input bool   InpUseLevelFactor = true;   // Factor: a prior swing sits inside the zone
input bool   InpUseRoundFactor = false;  // Factor: a round number sits inside the zone
input int    InpRoundStepPoints= 500;    // Round-number spacing (points)
input bool   InpUseDisplaceFactor = true;// Factor: the leg contains a displacement bar
input double InpDisplaceAtr    = 1.5;    // Displacement bar size (x ATR)

input group "=== Entry trigger ==="
input bool   InpRequireTrigger = true;   // Require a confirmation close (never enter on touch)

input group "=== Execution (OFF by default: analysis and publishing only) ==="
input bool   InpEnableTrading  = false;  // Let this EA open positions
input long   InpMagic          = 61803;  // Magic number
input double InpRiskPercent    = 1.0;    // Risk per trade (% of equity)
input int    InpMaxSpreadPts   = 30;     // Skip the entry above this spread (points)
input bool   InpBeAtTp1        = true;   // Move stop to break-even when TP1 fills
input double InpTp1ClosePct    = 50.0;   // Close this % of the position at TP1
input double InpTp2ClosePct    = 25.0;   // Close this % of the position at TP2
input double InpMaxDailyLossPct= 3.0;    // Halt for the day after this loss (% of day-start balance)

input group "=== Chart display ==="
input bool   InpShowVisuals    = true;   // Draw the setup on the chart

//--- CONFIG: constants ---------------------------------------------

#define LOG_PREFIX      "FibBot: "
#define OBJ_PREFIX      "FibBot_"
#define PIVOT_HISTORY   64
#define RETRY_MAX       3

//--- THEME: every colour used by this program, and nothing outside --
#define THEME_LONG      clrMediumSeaGreen
#define THEME_SHORT     clrIndianRed
#define THEME_ZONE      C'40,52,64'
#define THEME_STOP      clrCrimson
#define THEME_TARGET    clrDodgerBlue
#define THEME_ANCHOR    clrSlateGray
#define THEME_TEXT      clrGainsboro

//--- METRICS: every dimension used by this program ------------------
#define METRIC_LINE_W       1
#define METRIC_ZONE_W       1
#define METRIC_FONT_SIZE    8
#define METRIC_LABEL_SHIFT  3

//--- STATE ---------------------------------------------------------

// نقطة تأرجح مؤكدة — لا تتغير بعد تسجيلها
struct SPivot
  {
   datetime time;
   double   price;
   bool     isHigh;
  };

// الإعداد الحالي — المراسي تُجمّد عند التسليح ولا تُعدّل بعدها أبداً
struct SSetup
  {
   ENUM_SETUP_STATE state;
   int      dir;              // +1 long, -1 short
   double   anchorFrom;       // leg origin  (retracement 1.0)
   double   anchorTo;         // leg extreme (retracement 0.0)
   datetime anchorFromTime;
   datetime anchorToTime;
   double   zoneNear;         // shallow edge of the entry band
   double   zoneFar;          // deep edge of the entry band
   double   stop;
   double   tp1;
   double   tp2;
   double   tp3;
   double   legRange;
   int      confluence;
   string   confluenceText;
   int      barsArmed;
  };

// حالة البرنامج كلها في struct واحد — لا متغيرات global مبعثرة
struct SBotState
  {
   datetime lastBar;
   int      hATR;
   int      hTrendMA;
   ulong    ticket;           // position opened from the current setup
   ulong    posId;            // POSITION_IDENTIFIER — survives server-side SL/TP deals
   double   entryPrice;
   bool     beDone;
   bool     tp1Done;
   bool     tp2Done;
   bool     halted;
   double   dayStartBalance;
   datetime lastDayTs;
  };

SBotState g_bot;
SSetup    g_setup;
SPivot    g_pivots[];

//+------------------------------------------------------------------+

//====================================================================
// Util.mqh
//====================================================================

//+------------------------------------------------------------------+
//|                                                         Util.mqh |
//|  Generic, project-neutral helpers: normalisation, sizing, JSON.  |
//|  Nothing here knows about Fibonacci — these move to a shared     |
//|  Common.mqh unchanged.                                           |
//+------------------------------------------------------------------+

//--- bars ----------------------------------------------------------

// شمعة جديدة: تُستدعى مرة واحدة لكل تيك وتُحدّث الحالة
bool IsNewBar(datetime &lastBar)
  {
   datetime cur = iTime(_Symbol, _Period, 0);
   if(cur == 0 || cur == lastBar)
      return(false);
   lastBar = cur;
   return(true);
  }

//--- price and volume normalisation --------------------------------

// التقريب لحجم التيك — NormalizeDouble وحده يفشل على المؤشرات والمعادن
double NormalizePriceTick(const string symbol, const double price)
  {
   double tick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0)
      tick = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tick <= 0)
      return(price);
   return(MathRound(price / tick) * tick);
  }

double NormalizeVolumeStep(const string symbol, double volume)
  {
   double minV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      return(0);
   volume = MathFloor(volume / step) * step;   // لا تخاطر بأكثر من المحسوب
   if(volume < minV)
      return(0);                                // أقل من الحد الأدنى = لا صفقة
   return(MathMin(volume, maxV));
  }

// أدنى مسافة مسموحة بين السعر الحالي ووقف الخسارة أو الهدف
double MinStopDistance(const string symbol)
  {
   long stops  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long pts    = (stops > freeze) ? stops : freeze;
   if(pts == 0)
      pts = (long)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * 3;  // بروكر يعيد صفراً
   return((double)pts * SymbolInfoDouble(symbol, SYMBOL_POINT));
  }

// فرق حقيقي بين مستويين — يمنع 10025 NO_CHANGES
bool LevelsDiffer(const string symbol, const double a, const double b)
  {
   double tick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0)
      tick = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return(MathAbs(a - b) >= tick / 2.0);
  }

//--- risk ----------------------------------------------------------

// الحجم من مسافة الوقف — يعمل على الفوركس والمعادن والمؤشرات وأي عملة حساب
double LotsForRisk(const string symbol, const double riskMoney, const double stopDistance)
  {
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0)
      tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || stopDistance <= 0 || riskMoney <= 0)
      return(0);
   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0)
      return(0);
   return(NormalizeVolumeStep(symbol, riskMoney / lossPerLot));
  }

//--- formatting ----------------------------------------------------

// PERIOD_CURRENT يُطبع "CURRENT" لولا الحل هنا — والمشترك يحتاج الإطار الفعلي
ENUM_TIMEFRAMES ResolveTf(const ENUM_TIMEFRAMES tf)
  {
   return(tf == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : tf);
  }

string TimeframeName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(ResolveTf(tf));
   StringReplace(s, "PERIOD_", "");
   return(s);
  }

//+------------------------------------------------------------------+

//====================================================================
// Swing.mqh
//====================================================================

//+------------------------------------------------------------------+
//|                                                        Swing.mqh |
//|  CORE: non-repainting pivot detection and the pivot history.     |
//|                                                                  |
//|  A pivot cannot be confirmed until the bars to its right have    |
//|  closed. That lag is inherent, not a bug to engineer away — it   |
//|  is the price of a definition a backtest can honestly evaluate.  |
//|  Nothing here ever reads bar 0 (still forming).                  |
//+------------------------------------------------------------------+


//--- indicator reads (always the last CLOSED bar) ------------------

double GetAtr()
  {
   double v[1];
   if(CopyBuffer(g_bot.hATR, 0, 1, 1, v) != 1)
      return(0);
   return(v[0]);
  }

double GetTrendMa()
  {
   if(g_bot.hTrendMA == INVALID_HANDLE)
      return(0);
   double v[1];
   // الإزاحة 1 على إطار الاتجاه = آخر شمعة مغلقة هناك، فلا إعادة رسم
   if(CopyBuffer(g_bot.hTrendMA, 0, 1, 1, v) != 1)
      return(0);
   return(v[0]);
  }

//--- pivot history -------------------------------------------------

int PivotCount()
  {
   return(ArraySize(g_pivots));
  }

// الفهرس 0 = الأحدث
bool PivotAt(const int indexFromNewest, SPivot &out)
  {
   int total = ArraySize(g_pivots);
   int idx   = total - 1 - indexFromNewest;
   if(idx < 0 || idx >= total)
      return(false);
   out = g_pivots[idx];
   return(true);
  }

void PivotAdd(const datetime time, const double price, const bool isHigh)
  {
   int n = ArraySize(g_pivots);
   ArrayResize(g_pivots, n + 1);
   g_pivots[n].time   = time;
   g_pivots[n].price  = price;
   g_pivots[n].isHigh = isHigh;

   // القص من الأقدم حتى لا ينمو المصفوف بلا حد
   int total = ArraySize(g_pivots);
   if(total > PIVOT_HISTORY)
     {
      int drop = total - PIVOT_HISTORY;
      SPivot kept[];
      ArrayResize(kept, PIVOT_HISTORY);
      ArrayCopy(kept, g_pivots, 0, drop, PIVOT_HISTORY);
      ArrayResize(g_pivots, PIVOT_HISTORY);
      ArrayCopy(g_pivots, kept, 0, 0, PIVOT_HISTORY);
     }
  }

//--- detection -----------------------------------------------------

// الشمعة المرشحة الوحيدة عند كل شمعة جديدة: الإزاحة right+1
// (كل الشموع على يمينها مغلقة، والشمعة 0 لا تُقرأ إطلاقاً)
int CandidatePivotShift()
  {
   return(InpPivotRight + 1);
  }

bool IsPivotHigh(const int shift)
  {
   double h = iHigh(_Symbol, _Period, shift);
   if(h == 0)
      return(false);

   for(int i = 1; i <= InpPivotRight; i++)      // الجانب الأيمن: أصغر بصرامة
     {
      double r = iHigh(_Symbol, _Period, shift - i);
      if(r == 0 || r >= h)
         return(false);
     }
   for(int i = 1; i <= InpPivotLeft; i++)       // الجانب الأيسر: أصغر أو يساوي
     {
      double l = iHigh(_Symbol, _Period, shift + i);
      if(l == 0 || l > h)
         return(false);
     }
   return(true);
  }

bool IsPivotLow(const int shift)
  {
   double lo = iLow(_Symbol, _Period, shift);
   if(lo == 0)
      return(false);

   for(int i = 1; i <= InpPivotRight; i++)
     {
      double r = iLow(_Symbol, _Period, shift - i);
      if(r == 0 || r <= lo)
         return(false);
     }
   for(int i = 1; i <= InpPivotLeft; i++)
     {
      double l = iLow(_Symbol, _Period, shift + i);
      if(l == 0 || l < lo)
         return(false);
     }
   return(true);
  }

// تُستدعى مرة واحدة عند كل شمعة جديدة. تعيد true عند تأكيد نقطة جديدة.
bool SwingScanNewBar()
  {
   int shift = CandidatePivotShift();
   if(Bars(_Symbol, _Period) < shift + InpPivotLeft + 2)
      return(false);

   datetime t = iTime(_Symbol, _Period, shift);
   if(t == 0)
      return(false);

   // لا تسجل النقطة نفسها مرتين
   int total = ArraySize(g_pivots);
   if(total > 0 && g_pivots[total - 1].time == t)
      return(false);

   if(IsPivotHigh(shift))
     {
      PivotAdd(t, iHigh(_Symbol, _Period, shift), true);
      return(true);
     }
   if(IsPivotLow(shift))
     {
      PivotAdd(t, iLow(_Symbol, _Period, shift), false);
      return(true);
     }
   return(false);
  }

//--- leg construction ----------------------------------------------

// آخر نقطة مؤكدة من النوع المطلوب، بدءاً من فهرس معيّن (0 = الأحدث)
int FindPivot(const bool isHigh, const int fromIndex)
  {
   int total = ArraySize(g_pivots);
   for(int i = fromIndex; i < total; i++)
     {
      SPivot p;
      if(!PivotAt(i, p))
         break;
      if(p.isHigh == isHigh)
         return(i);
     }
   return(-1);
  }

// أكبر مدى شمعة داخل الساق — دليل الاندفاع (displacement)
double LargestBarRangeBetween(const datetime fromTime, const datetime toTime)
  {
   int fromShift = iBarShift(_Symbol, _Period, fromTime, false);
   int toShift   = iBarShift(_Symbol, _Period, toTime, false);
   if(fromShift < 0 || toShift < 0)
      return(0);

   int hi = MathMax(fromShift, toShift);
   int lo = MathMin(fromShift, toShift);
   double best = 0;
   for(int s = lo; s <= hi; s++)
     {
      double r = iHigh(_Symbol, _Period, s) - iLow(_Symbol, _Period, s);
      if(r > best)
         best = r;
     }
   return(best);
  }

int BarsBetween(const datetime fromTime, const datetime toTime)
  {
   int fromShift = iBarShift(_Symbol, _Period, fromTime, false);
   int toShift   = iBarShift(_Symbol, _Period, toTime, false);
   if(fromShift < 0 || toShift < 0)
      return(-1);
   return(MathAbs(fromShift - toShift));
  }

//+------------------------------------------------------------------+

//====================================================================
// Fib.mqh
//====================================================================

//+------------------------------------------------------------------+
//|                                                          Fib.mqh |
//|  CORE: retracement geometry, confluence scoring, setup machine.  |
//|                                                                  |
//|  Geometry note. Entering at retracement r with the stop at the   |
//|  leg origin and the target at the leg extreme gives              |
//|  R = r/(1-r) and a break-even win rate of exactly (1-r). The     |
//|  ladder therefore prices probability against payoff at par and   |
//|  supplies no edge on its own — which is why nothing here arms a  |
//|  setup on a Fibonacci level alone. Confluence and the trigger    |
//|  are the parts that have to carry the edge.                      |
//+------------------------------------------------------------------+


//--- direction-aware comparisons -----------------------------------

// السعر تراجع إلى ما بعد المستوى (لأسفل في الشراء، لأعلى في البيع)
bool RetracedPast(const double price, const double level, const int dir)
  {
   return(dir > 0 ? (price <= level) : (price >= level));
  }

// السعر تقدّم إلى ما بعد المستوى في اتجاه الصفقة
bool AdvancedPast(const double price, const double level, const int dir)
  {
   return(dir > 0 ? (price >= level) : (price <= level));
  }

//--- geometry ------------------------------------------------------

// r = 0.0 عند طرف الساق، r = 1.0 عند أصلها
double PriceAtRetrace(const SSetup &s, const double r)
  {
   return(s.anchorTo - s.dir * r * s.legRange);
  }

// x = 1.0 عند طرف الساق، وما فوقه امتداد
double PriceAtExtension(const SSetup &s, const double x)
  {
   return(s.anchorFrom + s.dir * x * s.legRange);
  }

//--- confluence ----------------------------------------------------

// عوامل غير فيبوناتشي حصراً: مستويان فيبوناتشي متقاطعان ليسا عاملين مستقلين
int ScoreConfluence(const SSetup &s, const int anchorFromIdx, const int anchorToIdx,
                    const double atr, string &text)
  {
   int    score = 0;
   string parts = "";

   double zoneLow  = MathMin(s.zoneNear, s.zoneFar);
   double zoneHigh = MathMax(s.zoneNear, s.zoneFar);

   if(InpUseTrendFilter)
     {
      double ma = GetTrendMa();
      double c1 = iClose(_Symbol, _Period, 1);
      if(ma > 0 && c1 > 0 && ((s.dir > 0 && c1 > ma) || (s.dir < 0 && c1 < ma)))
        {
         score++;
         parts += (parts == "" ? "" : ", ") + StringFormat("trend (%s MA%d)",
                  TimeframeName(InpTrendTimeframe), InpTrendMaPeriod);
        }
     }

   if(InpUseBosFactor)
     {
      // الساق كسرت آخر قمة/قاع من نفس النوع قبل مرساها الأول
      int prevIdx = FindPivot(s.dir > 0, anchorFromIdx + 1);
      SPivot prev;
      if(prevIdx >= 0 && PivotAt(prevIdx, prev) && AdvancedPast(s.anchorTo, prev.price, s.dir))
        {
         score++;
         parts += (parts == "" ? "" : ", ") + "structure break";
        }
     }

   if(InpUseLevelFactor)
     {
      // نقطة تأرجح سابقة داخل نطاق الدخول — دعم/مقاومة حقيقية لا خط نسبة
      int total = PivotCount();
      for(int i = 0; i < total; i++)
        {
         if(i == anchorFromIdx || i == anchorToIdx)
            continue;
         SPivot p;
         if(!PivotAt(i, p))
            continue;
         if(p.price >= zoneLow && p.price <= zoneHigh)
           {
            score++;
            parts += (parts == "" ? "" : ", ") + "prior swing in zone";
            break;
           }
        }
     }

   if(InpUseRoundFactor && InpRoundStepPoints > 0)
     {
      double step = (double)InpRoundStepPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(step > 0 && MathFloor(zoneHigh / step) * step >= zoneLow)
        {
         score++;
         parts += (parts == "" ? "" : ", ") + "round number";
        }
     }

   if(InpUseDisplaceFactor && atr > 0)
     {
      double biggest = LargestBarRangeBetween(s.anchorFromTime, s.anchorToTime);
      if(biggest >= InpDisplaceAtr * atr)
        {
         score++;
         parts += (parts == "" ? "" : ", ") + "displacement bar";
        }
     }

   text = parts;
   return(score);
  }

//--- setup lifecycle -----------------------------------------------

// إعادة تعيين صريحة: ZeroMemory على struct يحمل string ليست آمنة
void SetupReset()
  {
   g_setup.state          = SETUP_IDLE;
   g_setup.dir            = 0;
   g_setup.anchorFrom     = 0;
   g_setup.anchorTo       = 0;
   g_setup.anchorFromTime = 0;
   g_setup.anchorToTime   = 0;
   g_setup.zoneNear       = 0;
   g_setup.zoneFar        = 0;
   g_setup.stop           = 0;
   g_setup.tp1            = 0;
   g_setup.tp2            = 0;
   g_setup.tp3            = 0;
   g_setup.legRange       = 0;
   g_setup.confluence     = 0;
   g_setup.confluenceText = "";
   g_setup.barsArmed      = 0;
  }

// يحاول تسليح إعداد من آخر نقطتي تأرجح مؤكدتين.
// المراسي تُجمّد هنا ولا تُعدّل بعدها أبداً — الساق الجديدة تنشئ إعداداً جديداً.
bool SetupTryArm()
  {
   SPivot last;
   if(!PivotAt(0, last))
      return(false);

   int oppIdx = FindPivot(!last.isHigh, 1);
   SPivot opp;
   if(oppIdx < 0 || !PivotAt(oppIdx, opp))
      return(false);

   double atr = GetAtr();
   if(atr <= 0)
      return(false);

   SSetup s;
   s.dir            = last.isHigh ? 1 : -1;   // قمة جديدة = ساق صاعدة = بحث عن شراء
   s.anchorTo       = last.price;
   s.anchorToTime   = last.time;
   s.anchorFrom     = opp.price;
   s.anchorFromTime = opp.time;
   s.legRange       = MathAbs(s.anchorTo - s.anchorFrom);

   if(s.legRange < InpMinLegAtr * atr)
      return(false);

   int legBars = BarsBetween(s.anchorFromTime, s.anchorToTime);
   if(legBars < 0 || legBars > InpMaxLegBars)
      return(false);

   s.zoneNear = PriceAtRetrace(s, InpEntryFibNear);
   s.zoneFar  = PriceAtRetrace(s, InpEntryFibFar);

   // السعر تجاوز الحافة العميقة أصلاً: الإعداد وُلد ميتاً
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 == 0 || RetracedPast(c1, s.zoneFar, s.dir))
      return(false);

   double stopRaw = PriceAtRetrace(s, InpStopFib);
   s.stop = NormalizePriceTick(_Symbol, stopRaw - s.dir * InpStopAtrBuffer * atr);
   s.tp1  = NormalizePriceTick(_Symbol, PriceAtExtension(s, InpTp1Extension));
   s.tp2  = NormalizePriceTick(_Symbol, PriceAtExtension(s, InpTp2Extension));
   s.tp3  = NormalizePriceTick(_Symbol, PriceAtExtension(s, InpTp3Extension));

   string text = "";
   s.confluence     = ScoreConfluence(s, oppIdx, 0, atr, text);
   s.confluenceText = text;
   if(s.confluence < InpMinConfluence)
      return(false);

   s.state         = SETUP_ARMED;
   s.barsArmed     = 0;

   g_setup = s;
   PrintFormat("%sArmed %s setup — zone %s..%s, stop %s, confluence %d (%s)",
               LOG_PREFIX, (s.dir > 0 ? "LONG" : "SHORT"),
               DoubleToString(s.zoneNear, _Digits), DoubleToString(s.zoneFar, _Digits),
               DoubleToString(s.stop, _Digits), s.confluence, s.confluenceText);
   return(true);
  }

// انتقالات الحالة — كلها بشمعة مغلقة، ولا واحدة تقرأ شمعة لاحقة
void SetupAdvanceOnBar()
  {
   if(g_setup.state == SETUP_IDLE || g_setup.state == SETUP_TRIGGERED)
      return;

   double c1 = iClose(_Symbol, _Period, 1);
   double o1 = iOpen(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1);
   double l1 = iLow(_Symbol, _Period, 1);
   if(c1 == 0 || o1 == 0)
      return;

   g_setup.barsArmed++;

   // إبطال: إغلاق خلف أصل الساق — إغلاق لا ظل
   if(RetracedPast(c1, g_setup.anchorFrom, g_setup.dir))
     {
      g_setup.state = SETUP_INVALIDATED;
      return;
     }

   if(g_setup.barsArmed > InpSetupExpiryBars)
     {
      g_setup.state = SETUP_EXPIRED;
      return;
     }

   // دخول النطاق: الطرف المتطرف للشمعة لمس الحافة الضحلة
   if(g_setup.state == SETUP_ARMED)
     {
      double extreme = (g_setup.dir > 0) ? l1 : h1;
      if(RetracedPast(extreme, g_setup.zoneNear, g_setup.dir))
         g_setup.state = SETUP_IN_ZONE;
     }
  }

// هل أغلقت هذه الشمعة كإشارة تأكيد؟ النطاق موقع، والمشغّل هو التوقيت.
bool SetupTriggerFired()
  {
   if(g_setup.state != SETUP_IN_ZONE)
      return(false);

   if(!InpRequireTrigger)
      return(true);

   double c1 = iClose(_Symbol, _Period, 1);
   double o1 = iOpen(_Symbol, _Period, 1);
   if(c1 == 0 || o1 == 0)
      return(false);

   bool bodyAgrees = (g_setup.dir > 0) ? (c1 > o1) : (c1 < o1);
   bool rejected   = AdvancedPast(c1, g_setup.zoneNear, g_setup.dir);
   return(bodyAgrees && rejected);
  }

//+------------------------------------------------------------------+

//====================================================================
// Execution.mqh
//====================================================================

//+------------------------------------------------------------------+
//|                                                    Execution.mqh |
//|  TRADE: every CTrade call in this program lives in this file.    |
//|  Execution is opt-in (InpEnableTrading, default false) — with it |
//|  off the bot analyses and publishes and never touches an order.  |
//+------------------------------------------------------------------+


CTrade g_trade;

//--- setup ---------------------------------------------------------

void TradeInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFillingBySymbol(_Symbol);   // يمنع 10030 Unsupported filling mode
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
  }

//--- inspection ----------------------------------------------------

int CountMyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      count++;
     }
   return(count);
  }

// تذكرة أول مركز يخص هذا الإكسبيرت على هذا الرمز، أو صفر
ulong FindMyTicket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      return(t);
     }
   return(0);
  }

//--- daily loss guard ----------------------------------------------

// يعيد false = لا تتداول اليوم
bool DailyGuardOk()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayOpen = StructToTime(dt);

   if(dayOpen > g_bot.lastDayTs)
     {
      g_bot.dayStartBalance = balance;
      g_bot.lastDayTs       = dayOpen;
      g_bot.halted          = false;      // يوم جديد يرفع الإيقاف
     }

   if(g_bot.halted)
      return(false);

   if(InpMaxDailyLossPct <= 0 || g_bot.dayStartBalance <= 0)
      return(true);

   double loss  = g_bot.dayStartBalance - equity;
   double limit = g_bot.dayStartBalance * InpMaxDailyLossPct / 100.0;
   if(loss >= limit)
     {
      PrintFormat("%sDaily loss %.2f reached the %.2f limit — halted until tomorrow.",
                  LOG_PREFIX, loss, limit);
      g_bot.halted = true;
      return(false);
     }
   return(true);
  }

//--- opening -------------------------------------------------------

// يفتح المركز من الإعداد المسلَّح. يعيد سعر التنفيذ أو صفراً.
double OpenFromSetup()
  {
   if(!InpEnableTrading)
      return(0);
   if(!DailyGuardOk())
      return(0);
   if(CountMyPositions() > 0)
      return(0);
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
     {
      PrintFormat("%sSpread %d exceeds the %d limit — entry skipped.", LOG_PREFIX,
                  (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPts);
      return(0);
     }

   bool   isBuy = (g_setup.dir > 0);
   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);
   if(price <= 0)
      return(0);

   double minDist = MinStopDistance(_Symbol);
   double sl = g_setup.stop;
   double tp = g_setup.tp3;

   // ادفع الوقف والهدف خارج نطاق البروكر الممنوع إن لزم
   if(isBuy)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(sl > bid - minDist)
         sl = bid - minDist;
      if(tp < bid + minDist)
         tp = bid + minDist;
     }
   else
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(sl < ask + minDist)
         sl = ask + minDist;
      if(tp > ask - minDist)
         tp = ask - minDist;
     }
   sl = NormalizePriceTick(_Symbol, sl);
   tp = NormalizePriceTick(_Symbol, tp);

   double stopDistance = MathAbs(price - sl);
   if(stopDistance <= 0)
      return(0);

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lot       = LotsForRisk(_Symbol, riskMoney, stopDistance);
   if(lot <= 0)
     {
      // لا ترفع الحجم إلى الحد الأدنى سراً — ذلك يكسر إدارة المخاطر
      PrintFormat("%sRisk-sized lot is below the broker minimum — entry skipped.", LOG_PREFIX);
      return(0);
     }

   double need = 0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, need) ||
      need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      PrintFormat("%sInsufficient free margin for %.2f lots — entry skipped.", LOG_PREFIX, lot);
      return(0);
     }

   for(int attempt = 0; attempt < RETRY_MAX; attempt++)
     {
      bool ok = isBuy ? g_trade.Buy(lot, _Symbol, 0, sl, tp, "FibBot")
                      : g_trade.Sell(lot, _Symbol, 0, sl, tp, "FibBot");
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
        {
         double fill = g_trade.ResultPrice();
         if(fill <= 0)
            fill = price;
         g_bot.ticket     = FindMyTicket();
         g_bot.posId      = (g_bot.ticket != 0 && PositionSelectByTicket(g_bot.ticket))
                            ? (ulong)PositionGetInteger(POSITION_IDENTIFIER) : 0;
         g_bot.entryPrice = fill;
         g_bot.beDone     = false;
         g_bot.tp1Done    = false;
         g_bot.tp2Done    = false;
         PrintFormat("%sOpened %s %.2f lots at %s, stop %s, final target %s",
                     LOG_PREFIX, isBuy ? "BUY" : "SELL", lot,
                     DoubleToString(fill, _Digits), DoubleToString(sl, _Digits),
                     DoubleToString(tp, _Digits));
         return(fill);
        }
      if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED &&
         rc != TRADE_RETCODE_PRICE_OFF)
         break;
     }

   PrintFormat("%sOpen failed retcode=%u (%s)", LOG_PREFIX,
               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(0);
  }

//--- management ----------------------------------------------------

// إغلاق جزئي آمن: لا يترك بقية أصغر من الحد الأدنى للحجم
bool ClosePartialPct(const ulong ticket, const double percent)
  {
   if(percent <= 0)
      return(false);
   if(!PositionSelectByTicket(ticket))
      return(false);

   double current = PositionGetDouble(POSITION_VOLUME);
   double minV    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double want    = NormalizeVolumeStep(_Symbol, current * percent / 100.0);

   if(want <= 0)
      return(false);
   if(current - want < minV)
      return(false);          // البقية ستكون غير صالحة — اترك المركز كما هو

   return(g_trade.PositionClosePartial(ticket, want));
  }

bool MoveStopToBreakEven(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return(false);

   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSl  = PositionGetDouble(POSITION_SL);
   double curTp  = PositionGetDouble(POSITION_TP);
   long   type   = PositionGetInteger(POSITION_TYPE);
   double newSl  = NormalizePriceTick(_Symbol, entry);

   if(!LevelsDiffer(_Symbol, newSl, curSl))
      return(false);          // لا تغيير حقيقي — يمنع 10025

   double dist = MinStopDistance(_Symbol);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY  && newSl > bid - dist)
      return(false);
   if(type == POSITION_TYPE_SELL && newSl < ask + dist)
      return(false);

   return(g_trade.PositionModify(ticket, newSl, curTp));
  }

// هل بلغ السعر هدفاً؟ يُقاس على السعر الحي في اتجاه الصفقة
bool TargetReached(const double target)
  {
   if(target <= 0)
      return(false);
   double price = SymbolInfoDouble(_Symbol, g_setup.dir > 0 ? SYMBOL_BID : SYMBOL_ASK);
   if(price <= 0)
      return(false);
   return(AdvancedPast(price, target, g_setup.dir));
  }

//+------------------------------------------------------------------+

//====================================================================
// Visuals.mqh
//====================================================================

//+------------------------------------------------------------------+
//|                                                      Visuals.mqh |
//|  UI: every ObjectCreate in this program lives in this file.      |
//|  Colours come only from the THEME block and sizes only from      |
//|  METRICS, both in Config.mqh.                                    |
//+------------------------------------------------------------------+


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

//+------------------------------------------------------------------+

//====================================================================
// FibBot.mq5
//====================================================================

//+------------------------------------------------------------------+
//|                                                       FibBot.mq5 |
//|  Fibonacci retracement bot for the Trading Signals Platform.     |
//|                                                                  |
//|  Detects non-repainting swing pivots, arms a retracement setup   |
//|  only when independent non-Fibonacci confluence agrees, waits    |
//|  for a confirmation close, then draws it and (optionally)        |
//|  trades it. Self-contained: it talks to no network service.      |
//|                                                                  |
//|  Method and evidence: docs/education/fibonacci-retracement.md    |
//|  Setup, inputs and caveats: mt5/FibBot/README.md                 |
//|                                                                  |
//|  Attach one instance per chart; it trades only that chart's      |
//|  symbol and timeframe.                                           |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| EVENTS                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   ZeroMemory(g_bot);
   g_bot.hATR     = INVALID_HANDLE;
   g_bot.hTrendMA = INVALID_HANDLE;
   ArrayFree(g_pivots);
   SetupReset();

   g_bot.hATR = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_bot.hATR == INVALID_HANDLE)
     {
      PrintFormat("%sATR handle failed: %d", LOG_PREFIX, GetLastError());
      return(INIT_FAILED);
     }

   if(InpUseTrendFilter)
     {
      g_bot.hTrendMA = iMA(_Symbol, InpTrendTimeframe, InpTrendMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_bot.hTrendMA == INVALID_HANDLE)
        {
         PrintFormat("%sTrend MA handle failed: %d", LOG_PREFIX, GetLastError());
         return(INIT_FAILED);
        }
     }

   TradeInit();
   g_bot.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_bot.lastDayTs       = 0;

   PrintFormat("%sReady on %s %s. Trading %s.", LOG_PREFIX,
               _Symbol, TimeframeName((ENUM_TIMEFRAMES)_Period),
               InpEnableTrading ? "ENABLED" : "disabled");

   if(InpEnableTrading && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      PrintFormat("%sTrading is enabled in the inputs but AutoTrading is off in the terminal.",
                  LOG_PREFIX);

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_bot.hATR != INVALID_HANDLE)
      IndicatorRelease(g_bot.hATR);
   if(g_bot.hTrendMA != INVALID_HANDLE)
      IndicatorRelease(g_bot.hTrendMA);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ChartRedraw();
  }

void OnTick()
  {
   ManageOpenTrade();                 // الأهداف الجزئية تحتاج كل تيك

   if(!IsNewBar(g_bot.lastBar))
      return;

   ProcessBar();
   VisualsDraw();
  }

//+------------------------------------------------------------------+
//| CORE — the bar pipeline                                          |
//+------------------------------------------------------------------+
void ProcessBar()
  {
   bool newPivot = SwingScanNewBar();

   // تقدّم الإعداد القائم أولاً حتى لا تُلغى ساق صالحة بنقطة جديدة
   if(g_setup.state != SETUP_IDLE)
     {
      SetupAdvanceOnBar();
      HandleSetupOutcome();
     }

   if(g_setup.state == SETUP_IDLE && newPivot && CountMyPositions() == 0)
     {
      SetupTryArm();
      return;
     }

   if(g_setup.state == SETUP_IN_ZONE && SetupTriggerFired())
      EnterFromSetup();
  }

void EnterFromSetup()
  {
   double fill = OpenFromSetup();     // تعيد صفراً عندما يكون التنفيذ مطفأً

   g_setup.state = SETUP_TRIGGERED;

   if(fill <= 0 && !InpEnableTrading)
      PrintFormat("%sTrigger confirmed at %s — execution is off, nothing sent.", LOG_PREFIX,
                  DoubleToString(iClose(_Symbol, _Period, 1), _Digits));
  }

void HandleSetupOutcome()
  {
   if(g_setup.state != SETUP_INVALIDATED && g_setup.state != SETUP_EXPIRED)
      return;

   PrintFormat("%sSetup ended: %s", LOG_PREFIX, EnumToString(g_setup.state));
   SetupReset();
   VisualsClear();
  }

//+------------------------------------------------------------------+
//| TRADE management — partials, break-even, close detection         |
//+------------------------------------------------------------------+
void ManageOpenTrade()
  {
   ulong ticket = FindMyTicket();

   if(ticket == 0)
     {
      // المركز اختفى: نظّف حالة الصفقة وحرّر مكاناً لإعداد جديد
      if(g_bot.ticket != 0)
        {
         g_bot.ticket     = 0;
         g_bot.posId      = 0;
         g_bot.entryPrice = 0;
         if(g_setup.state == SETUP_TRIGGERED)
           {
            SetupReset();
            VisualsClear();
           }
        }
      return;
     }

   g_bot.ticket = ticket;

   // مركز تبنّاه الإكسبيرت بعد إعادة تشغيل: لا إعداد يصف أهدافه، فاتركه لوقفه وهدفه
   if(g_setup.state != SETUP_TRIGGERED)
      return;

   if(!g_bot.tp1Done && TargetReached(g_setup.tp1))
     {
      PrintFormat("%sTP1 reached at %s.", LOG_PREFIX, DoubleToString(g_setup.tp1, _Digits));
      if(InpTp1ClosePct > 0 && ClosePartialPct(ticket, InpTp1ClosePct))
         PrintFormat("%sTP1 partial closed (%.0f%%).", LOG_PREFIX, InpTp1ClosePct);
      g_bot.tp1Done = true;

      if(InpBeAtTp1 && !g_bot.beDone && MoveStopToBreakEven(ticket))
        {
         PrintFormat("%sStop moved to break-even at %s.", LOG_PREFIX,
                     DoubleToString(g_bot.entryPrice, _Digits));
         g_bot.beDone = true;
        }
     }

   if(!g_bot.tp2Done && TargetReached(g_setup.tp2))
     {
      PrintFormat("%sTP2 reached at %s.", LOG_PREFIX, DoubleToString(g_setup.tp2, _Digits));
      if(InpTp2ClosePct > 0 && ClosePartialPct(ticket, InpTp2ClosePct))
         PrintFormat("%sTP2 partial closed (%.0f%%).", LOG_PREFIX, InpTp2ClosePct);
      g_bot.tp2Done = true;
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   // الصفقات التي يغلقها الخادم قد تصل بسحر صفري — طابِق بمعرّف المركز أيضاً
   long  magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(magic != InpMagic && (g_bot.posId == 0 || posId != g_bot.posId))
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   // إغلاق جزئي: المركز ما زال قائماً، وقد أُبلغ عنه في ManageOpenTrade
   if(posId != 0 && PositionSelectByTicket(posId))
      return;

   long   reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double pl     = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   string how = (reason == DEAL_REASON_SL)
                ? (g_bot.beDone ? "stopped out at break-even" : "stop loss")
                : (reason == DEAL_REASON_TP ? "final target" : "closed");

   PrintFormat("%sPosition %s at %s, P/L %.2f", LOG_PREFIX, how,
               DoubleToString(price, _Digits), pl);
  }

//+------------------------------------------------------------------+
//| CONFIG validation                                                |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpPivotLeft < 1 || InpPivotRight < 1)
     {
      PrintFormat("%sPivot left/right must be at least 1.", LOG_PREFIX);
      return(false);
     }
   if(InpEntryFibNear <= 0.0 || InpEntryFibFar >= 1.0 || InpEntryFibNear >= InpEntryFibFar)
     {
      PrintFormat("%sEntry zone must satisfy 0 < near < far < 1.", LOG_PREFIX);
      return(false);
     }
   if(InpStopFib < InpEntryFibFar)
     {
      // وقف أقرب من حافة النطاق العميقة يُضرب قبل أن يُختبر الإعداد
      PrintFormat("%sStop retracement (%.3f) must be at least the deep zone edge (%.3f).",
                  LOG_PREFIX, InpStopFib, InpEntryFibFar);
      return(false);
     }
   if(InpTp1Extension < 1.0 || InpTp2Extension < InpTp1Extension || InpTp3Extension < InpTp2Extension)
     {
      PrintFormat("%sTargets must satisfy 1.0 <= TP1 <= TP2 <= TP3.", LOG_PREFIX);
      return(false);
     }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 100.0)
     {
      PrintFormat("%sRisk percent must be between 0 and 100.", LOG_PREFIX);
      return(false);
     }
   if(InpTp1ClosePct + InpTp2ClosePct >= 100.0)
     {
      PrintFormat("%sTP1 and TP2 partials must leave something for TP3.", LOG_PREFIX);
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| OnTester — reject samples too small to mean anything             |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 30)
      return(0);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = MathMax(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 1.0);
   return(TesterStatistics(STAT_PROFIT) * pf / dd);
  }
//+------------------------------------------------------------------+
