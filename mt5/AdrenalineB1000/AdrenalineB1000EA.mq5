//+------------------------------------------------------------------+
//|                                            AdrenalineB1000EA.mq5 |
//|                                        Copyright 2026, Serro Deriv|
//|                                                                  |
//|   Martingale Expert Advisor driven by the Adrenaline B1000       |
//|   indicator.                                                     |
//|                                                                  |
//|   إكسبيرت مارتينجيل يقرأ حالته من مؤشر Adrenaline B1000:         |
//|   الدخول الأول عند لمس المنطقة الذهبية (قبل السهم)، ثم مضاعفات   |
//|   عند ظهور السهم وعند ابتعاد السعر، مع تريلينج على متوسط السلة.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Serro Deriv"
#property link      ""
#property version   "2.00"
#property description "Adrenaline B1000 EA — by Serro Deriv"
#property description "Martingale EA for the Adrenaline B1000 indicator."
#property description "Entry 1: Golden Zone touch (before the arrow). Entry 2+: arrow and distance martingale."
#property description "Basket average TP/SL, break-even and trailing. Buy-only / Sell-only supported."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| TYPES                                                            |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIR
  {
   TD_BOTH = 0,    // Buy and Sell
   TD_BUY_ONLY,    // Buy only
   TD_SELL_ONLY    // Sell only
  };

//+------------------------------------------------------------------+
//| CONFIG — الإدخالات (بلا مرشحات جلسات أو وقت، حسب الطلب)          |
//+------------------------------------------------------------------+
input group "=========  1. INDICATOR LINK  ========="
input string         InpIndName        = "AdrenalineB1000\\AdrenalineB1000"; // Indicator path under MQL5\Indicators
input int            InpMinScore       = 5;          // Min confluence score to accept an arrow (0-8)

input group "=========  2. DIRECTION  ========="
input ENUM_TRADE_DIR InpDirection      = TD_BOTH;    // Allowed direction

input group "=========  3. ENTRIES  ========="
input bool           InpEntryZoneTouch = true;       // Entry 1: Golden Zone touch (BEFORE the arrow)
input bool           InpEntryOnArrow   = true;       // Entry 2: indicator arrow

input group "=========  4. MARTINGALE  ========="
input double         InpLotStart       = 0.01;       // Base lot (first position)
input double         InpLotMult        = 2.0;        // Lot multiplier per level (2.0 - 5.0)
input int            InpMaxTrades      = 5;          // Max positions per cycle
input int            InpStepPoints     = 250;        // Distance between adds (points, 0 = arrow adds only)
input bool           InpStepGrow       = true;       // Widen the step at each level

input group "=========  5. EXITS  ========="
input int            InpTakeProfit     = 300;        // Basket TP from average price (points, 0 = off)
input int            InpStopLoss       = 0;          // Basket SL from average price (points, 0 = off)
input bool           InpCloseOnReverse = true;       // Close the basket on an opposite arrow

input group "=========  6. TRAILING  ========="
input bool           InpUseTrailing    = true;       // Enable basket trailing stop
input int            InpTrailStart     = 150;        // Arm trailing after this basket profit (points)
input int            InpTrailDistance  = 100;        // Trail this far behind price (points)
input int            InpTrailStep      = 20;         // Min improvement before modifying (points)
input bool           InpUseBreakEven   = true;       // Enable break-even
input int            InpBreakEvenAt    = 120;        // Move to break-even after this profit (points)
input int            InpBreakEvenLock  = 20;         // Points locked in at break-even

input group "=========  7. PROTECTION  ========="
input int            InpMaxSpread      = 0;          // Max spread for new entries (points, 0 = off)
input double         InpEquityStopPct  = 30.0;       // Halt and close all at this equity drawdown % (0 = off)
input long           InpMagic          = 20260903;   // Magic number
input int            InpSlippage       = 20;         // Slippage (points)
input bool           InpDebug          = true;       // Log why an entry was not taken (once per bar)

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define ADR_BUF_SIGNAL     2
#define ADR_BUF_SCORE      3
#define ADR_BUF_LEGDIR     4
#define ADR_BUF_ZONE_HI    5
#define ADR_BUF_ZONE_LO    6
#define ADR_BUF_LEG_ORIG   7

#define ADR_LOT_MULT_MAX   5.0
#define ADR_EA_TAG         "ADR"

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
//--- لقطة واحدة من المؤشر لكل تيك
struct SIndSnap
  {
   bool              ok;
   int               legDir;        // +1 / -1 / 0   (shift 0)
   double            zoneHi;        // حد المنطقة الذهبية الأعلى
   double            zoneLo;        // حد المنطقة الذهبية الأدنى
   double            legOrigin;     // مستوى 1.000 — نقطة إبطال الموجة
   int               signal;        // +1 / -1 / 0   (shift 1 = آخر شمعة مغلقة)
   int               score;         // 0..8
   datetime          signalBar;     // زمن الشمعة المغلقة
  };

struct SEaState
  {
   int               cycleDir;         // +1 سلة شراء، -1 سلة بيع، 0 لا شيء
   int               tradesInCycle;    // عدد المضاعفات المفتوحة في الدورة
   double            lastLot;          // حجم آخر صفقة
   double            lastEntryPrice;   // سعر آخر دخول (أساس خطوة المارتينجيل)
   datetime          usedArrowBar;     // آخر سهم استُهلك
   double            zoneLegOrigin;    // الموجة التي دخلنا عليها من المنطقة الذهبية
   double            zoneLegHi;        // حد المنطقة لتلك الموجة
   bool              trailArmed;
   double            trailLevel;
   double            equityPeak;
   bool              halted;

   void Reset()
     {
      cycleDir = 0;
      tradesInCycle = 0;
      lastLot = 0.0;
      lastEntryPrice = 0.0;
      trailArmed = false;
      trailLevel = 0.0;
     }
  };

CTrade   g_trade;
SEaState g_ea;
int      g_hInd    = INVALID_HANDLE;
double   g_point   = 0.0;
double   g_tick    = 0.0;
double   g_lotMult = 2.0;      // نسخة مُقيَّدة من InpLotMult (الإدخالات ثوابت)

//+------------------------------------------------------------------+
//|                        U T I L I T I E S                         |
//+------------------------------------------------------------------+

//--- تسجيل موحّد
void Log(const string msg)
  {
   PrintFormat("[%s][%s] %s", ADR_EA_TAG, _Symbol, msg);
  }

//--- تطبيع الحجم على خطوة الرمز
double NormalizeVolume(double vol)
  {
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = minV > 0.0 ? minV : 0.01;
   vol = MathFloor(vol / step + 0.5) * step;
   vol = MathMin(MathMax(vol, minV), maxV);
   return NormalizeDouble(vol, 8);
  }

//--- تقريب السعر إلى حجم التيك (وليس إلى الخانات فقط)
double NormalizePrice(double price)
  {
   double t = (g_tick > 0.0) ? g_tick : g_point;
   if(t <= 0.0)
      return price;
   return NormalizeDouble(MathRound(price / t) * t, _Digits);
  }

//--- أدنى مسافة مسموحة للوقف/الهدف عن السعر الحالي
double MinStopDistance()
  {
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long pts = (long)MathMax(stops, freeze);
   if(pts <= 0)
      pts = (long)MathMax(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * 3, 10);
   return (double)pts * g_point;
  }

//--- هل القيمتان مختلفتان فعلاً؟ (يمنع الخطأ 10025 NO_CHANGES)
bool LevelsDiffer(const double a, const double b)
  {
   double t = (g_tick > 0.0) ? g_tick : g_point;
   return MathAbs(a - b) >= t / 2.0;
  }

//--- الاتجاه مسموح به حسب الإعداد
bool DirectionAllowed(const int dir)
  {
   if(dir > 0) return (InpDirection == TD_BOTH || InpDirection == TD_BUY_ONLY);
   if(dir < 0) return (InpDirection == TD_BOTH || InpDirection == TD_SELL_ONLY);
   return false;
  }

//--- السبريد الحالي بالنقاط
int SpreadPoints()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  }

//+------------------------------------------------------------------+
//|                  I N D I C A T O R   R E A D                     |
//+------------------------------------------------------------------+

//--- قراءة قيمة واحدة من بافر المؤشر
bool IndValue(const int buffer, const int shift, double &out)
  {
   out = 0.0;
   double v[1];
   if(CopyBuffer(g_hInd, buffer, shift, 1, v) != 1)
      return false;
   out = v[0];
   return true;
  }

//--- لقطة كاملة: حالة الموجة عند الشمعة الحالية + السهم عند آخر شمعة مغلقة
bool ReadIndicator(SIndSnap &s)
  {
   s.ok = false;
   s.legDir = 0; s.zoneHi = 0.0; s.zoneLo = 0.0; s.legOrigin = 0.0;
   s.signal = 0; s.score = 0; s.signalBar = 0;

   if(g_hInd == INVALID_HANDLE)
      return false;
   if(BarsCalculated(g_hInd) <= 0)
      return false;                       // المؤشر لم يجهز بعد

   double legDir, zHi, zLo, orig, sig, sco;
   if(!IndValue(ADR_BUF_LEGDIR,   0, legDir)) return false;
   if(!IndValue(ADR_BUF_ZONE_HI,  0, zHi))    return false;
   if(!IndValue(ADR_BUF_ZONE_LO,  0, zLo))    return false;
   if(!IndValue(ADR_BUF_LEG_ORIG, 0, orig))   return false;
   if(!IndValue(ADR_BUF_SIGNAL,   1, sig))    return false;
   if(!IndValue(ADR_BUF_SCORE,    1, sco))    return false;

   s.legDir    = (int)MathRound(legDir);
   s.zoneHi    = zHi;
   s.zoneLo    = zLo;
   s.legOrigin = orig;
   s.signal    = (int)MathRound(sig);
   s.score     = (int)MathRound(sco);
   s.signalBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   s.ok        = true;
   return true;
  }

//+------------------------------------------------------------------+
//|                     B A S K E T   S T A T E                      |
//+------------------------------------------------------------------+

//--- معلومات السلة: العدد، الحجم، متوسط السعر، الربح
void BasketInfo(int &count, double &volume, double &avgPrice, double &profit, int &dir)
  {
   count = 0; volume = 0.0; avgPrice = 0.0; profit = 0.0; dir = 0;
   double weighted = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double prc = PositionGetDouble(POSITION_PRICE_OPEN);
      long   typ = PositionGetInteger(POSITION_TYPE);

      count++;
      volume   += vol;
      weighted += prc * vol;
      profit   += PositionGetDouble(POSITION_PROFIT)
                  + PositionGetDouble(POSITION_SWAP);
      dir = (typ == POSITION_TYPE_BUY) ? +1 : -1;
     }

   if(volume > 0.0)
      avgPrice = weighted / volume;
  }

//--- أكبر حجم مركز في السلة = آخر درجة في سلّم المارتينجيل
double LargestPositionVolume()
  {
   double best = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      best = MathMax(best, PositionGetDouble(POSITION_VOLUME));
     }
   return best;
  }

//--- ربح السلة بالنقاط من متوسط السعر
double BasketProfitPoints(const int dir, const double avgPrice)
  {
   if(dir == 0 || avgPrice <= 0.0 || g_point <= 0.0)
      return 0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(dir > 0)
      return (bid - avgPrice) / g_point;
   return (avgPrice - ask) / g_point;
  }

//+------------------------------------------------------------------+
//|                    T R A D E   A C T I O N S                     |
//+------------------------------------------------------------------+

//--- فتح مركز واحد في اتجاه dir بحجم lot (دالة واحدة للشراء والبيع)
bool OpenPosition(const int dir, const double lot, const string reason)
  {
   double vol = NormalizeVolume(lot);
   if(vol <= 0.0)
     {
      Log("volume normalised to zero — entry skipped");
      return false;
     }

   bool   isBuy = (dir > 0);
   double price = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);

   //--- فحص الهامش قبل الإرسال
   double need = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, vol, price, need))
     {
      Log("OrderCalcMargin failed — entry skipped");
      return false;
     }
   if(need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      Log(StringFormat("not enough free margin for %.2f lots (need %.2f) — entry skipped", vol, need));
      return false;
     }

   //--- الوقف والهدف يُضبطان لاحقاً على مستوى السلة
   bool ok = isBuy ? g_trade.Buy (vol, _Symbol, 0.0, 0.0, 0.0, ADR_EA_TAG + " " + reason)
             : g_trade.Sell(vol, _Symbol, 0.0, 0.0, 0.0, ADR_EA_TAG + " " + reason);

   if(!ok || g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
     {
      Log(StringFormat("entry failed (%s) retcode=%u %s", reason,
                       g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return false;
     }

   g_ea.cycleDir       = dir;
   g_ea.tradesInCycle++;
   g_ea.lastLot        = vol;
   g_ea.lastEntryPrice = price;
   Log(StringFormat("%s #%d %.2f lots @ %s (%s)", (isBuy ? "BUY" : "SELL"),
                    g_ea.tradesInCycle, vol, DoubleToString(price, _Digits), reason));
   return true;
  }

//--- إغلاق كل مراكز الإكسبيرت
void CloseBasket(const string reason)
  {
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(g_trade.PositionClose(ticket))
         closed++;
      else
         Log(StringFormat("close failed ticket=%I64u retcode=%u", ticket, g_trade.ResultRetcode()));
     }
   if(closed > 0)
     {
      Log(StringFormat("basket closed (%d positions) — %s", closed, reason));
      g_ea.Reset();                             // الإغلاق ينهي الدورة دائماً
     }
  }

//--- حجم المستوى التالي في سلّم المارتينجيل
double NextLot()
  {
   if(g_ea.tradesInCycle <= 0 || g_ea.lastLot <= 0.0)
      return InpLotStart;
   return g_ea.lastLot * g_lotMult;
  }

//--- المسافة المطلوبة قبل المضاعفة التالية
double NextStepPoints()
  {
   if(InpStepPoints <= 0)
      return 0.0;
   int level = (int)MathMax(1, g_ea.tradesInCycle);
   return InpStepGrow ? (double)InpStepPoints * level : (double)InpStepPoints;
  }

//+------------------------------------------------------------------+
//|            B A S K E T   S T O P S   /   T R A I L I N G         |
//+------------------------------------------------------------------+

//--- يحسب الوقف والهدف المطلوبين للسلة ويطبّقهما على كل المراكز
void ApplyBasketStops(const int dir, const double avgPrice)
  {
   if(dir == 0 || avgPrice <= 0.0)
      return;

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double dist = MinStopDistance();
   bool   isBuy = (dir > 0);

   //--- الهدف من متوسط السعر
   double tp = 0.0;
   if(InpTakeProfit > 0)
      tp = NormalizePrice(isBuy ? avgPrice + InpTakeProfit * g_point
                          : avgPrice - InpTakeProfit * g_point);

   //--- الوقف: الأساسي، ثم نقطة التعادل، ثم التريلينج — الأفضل يفوز
   double sl = 0.0;
   if(InpStopLoss > 0)
      sl = NormalizePrice(isBuy ? avgPrice - InpStopLoss * g_point
                          : avgPrice + InpStopLoss * g_point);

   double profitPts = BasketProfitPoints(dir, avgPrice);

   if(InpUseBreakEven && InpBreakEvenAt > 0 && profitPts >= (double)InpBreakEvenAt)
     {
      double be = NormalizePrice(isBuy ? avgPrice + InpBreakEvenLock * g_point
                                 : avgPrice - InpBreakEvenLock * g_point);
      if(sl == 0.0 || (isBuy && be > sl) || (!isBuy && be < sl))
         sl = be;
     }

   if(g_ea.trailArmed && g_ea.trailLevel > 0.0)
     {
      if(sl == 0.0 || (isBuy && g_ea.trailLevel > sl) || (!isBuy && g_ea.trailLevel < sl))
         sl = g_ea.trailLevel;
     }

   //--- التحقق من المسافة الدنيا؛ ما يقع داخل النطاق المحظور يُهمل هذه المرة
   if(sl > 0.0)
     {
      if(isBuy  && sl > bid - dist) sl = 0.0;
      if(!isBuy && sl < ask + dist) sl = 0.0;
     }
   if(tp > 0.0)
     {
      if(isBuy  && tp < bid + dist) tp = 0.0;
      if(!isBuy && tp > ask - dist) tp = 0.0;
     }

   //--- التطبيق على كل المراكز، مع مقارنة قبل التعديل
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double newSL = (sl > 0.0) ? sl : curSL;      // لا نمسح وقفاً قائماً
      double newTP = (tp > 0.0) ? tp : curTP;

      if(!LevelsDiffer(newSL, curSL) && !LevelsDiffer(newTP, curTP))
         continue;
      if(!g_trade.PositionModify(ticket, newSL, newTP))
         Log(StringFormat("modify failed ticket=%I64u retcode=%u", ticket, g_trade.ResultRetcode()));
     }
  }

//--- تحديث مستوى التريلينج على متوسط السلة (سقّاطة: يتحسن فقط)
void UpdateTrailing(const int dir, const double avgPrice)
  {
   if(!InpUseTrailing || dir == 0 || avgPrice <= 0.0)
      return;

   double profitPts = BasketProfitPoints(dir, avgPrice);
   if(profitPts < (double)InpTrailStart)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lvl = (dir > 0) ? NormalizePrice(bid - InpTrailDistance * g_point)
                : NormalizePrice(ask + InpTrailDistance * g_point);

   if(!g_ea.trailArmed)
     {
      g_ea.trailArmed = true;
      g_ea.trailLevel = lvl;
      Log(StringFormat("trailing armed at %s", DoubleToString(lvl, _Digits)));
      return;
     }

   double stepPrice = InpTrailStep * g_point;
   if(dir > 0 && lvl > g_ea.trailLevel + stepPrice)
      g_ea.trailLevel = lvl;
   if(dir < 0 && lvl < g_ea.trailLevel - stepPrice)
      g_ea.trailLevel = lvl;
  }

//--- إغلاق احتياطي بالسوق عند بلوغ الهدف أو ارتداد السعر إلى مستوى التريلينج
bool CheckSoftExits(const int dir, const double avgPrice)
  {
   if(dir == 0 || avgPrice <= 0.0)
      return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPts = BasketProfitPoints(dir, avgPrice);

   if(InpTakeProfit > 0 && profitPts >= (double)InpTakeProfit)
     {
      CloseBasket("take profit reached");
      return true;
     }
   if(InpStopLoss > 0 && profitPts <= -(double)InpStopLoss)
     {
      CloseBasket("stop loss reached");
      return true;
     }
   if(g_ea.trailArmed && g_ea.trailLevel > 0.0)
     {
      if(dir > 0 && bid <= g_ea.trailLevel) { CloseBasket("trailing stop hit"); return true; }
      if(dir < 0 && ask >= g_ea.trailLevel) { CloseBasket("trailing stop hit"); return true; }
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                    E N T R Y   L O G I C                         |
//+------------------------------------------------------------------+

//--- السعر داخل حدود المنطقة الذهبية تماماً (للعرض على الشارت فقط)
bool PriceInZone(const SIndSnap &s)
  {
   if(s.zoneHi <= 0.0 || s.zoneLo <= 0.0)
      return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (bid <= s.zoneHi && bid >= s.zoneLo);
  }

//--- شرط الدخول: هل بلغ السعر منطقة الخصم؟
//    الموجة تُؤكَّد بعد InpSwingN شمعة من تكوّن القمة/القاع، وفي التصحيح السريع
//    يكون السعر قد عبر شريط 0.618-0.786 كاملاً قبل أن تظهر الموجة أصلاً.
//    لذلك الشرط هو "بلغ حافة 0.618 وما زال داخل الموجة" وليس "داخل الشريط الآن"،
//    وإلا لا تُفتح أي صفقة على الحركات السريعة.
bool ZoneReached(const SIndSnap &s)
  {
   if(s.zoneHi <= 0.0 || s.zoneLo <= 0.0 || s.legOrigin <= 0.0)
      return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(s.legDir > 0)
      return (bid <= s.zoneHi && bid > s.legOrigin);    // من 0.618 نزولاً حتى 1.000
   if(s.legDir < 0)
      return (bid >= s.zoneLo && bid < s.legOrigin);    // من 0.618 صعوداً حتى 1.000
   return false;
  }

//--- هل هذه الموجة استُهلكت بالفعل بدخول المنطقة الذهبية؟
bool ZoneAlreadyTraded(const SIndSnap &s)
  {
   if(g_ea.zoneLegOrigin <= 0.0)
      return false;
   return (!LevelsDiffer(g_ea.zoneLegOrigin, s.legOrigin) &&
           !LevelsDiffer(g_ea.zoneLegHi,     s.zoneHi));
  }

//--- الدخول الأول: لمس المنطقة الذهبية قبل ظهور السهم
void TryZoneEntry(const SIndSnap &s)
  {
   if(!InpEntryZoneTouch)
      return;
   if(g_ea.tradesInCycle > 0)
      return;                                   // السلة مفتوحة — هذا دخول أول فقط
   if(s.legDir == 0 || !DirectionAllowed(s.legDir))
      return;
   if(!ZoneReached(s))
      return;
   if(ZoneAlreadyTraded(s))
      return;

   if(OpenPosition(s.legDir, InpLotStart, "zone touch"))
     {
      g_ea.zoneLegOrigin = s.legOrigin;         // الموجة استُهلكت — لا دخول ثانٍ عليها
      g_ea.zoneLegHi     = s.zoneHi;
     }
  }

//--- الدخول الثاني: سهم المؤشر — يفتح مضاعفة جديدة
void TryArrowEntry(const SIndSnap &s)
  {
   if(!InpEntryOnArrow)
      return;
   if(s.signal == 0 || s.score < InpMinScore)
      return;
   if(s.signalBar == 0 || s.signalBar == g_ea.usedArrowBar)
      return;                                   // هذا السهم استُهلك

   //--- سهم معاكس: إغلاق السلة بدل الإضافة
   if(g_ea.tradesInCycle > 0 && s.signal != g_ea.cycleDir)
     {
      g_ea.usedArrowBar = s.signalBar;
      if(InpCloseOnReverse)
         CloseBasket("opposite arrow");
      return;
     }

   if(!DirectionAllowed(s.signal))
      return;
   if(g_ea.tradesInCycle >= InpMaxTrades)
      return;

   g_ea.usedArrowBar = s.signalBar;
   double lot = NextLot();
   if(OpenPosition(s.signal, lot, StringFormat("arrow %d/8", s.score)))
     {
      //--- الموجة تُحسب مستهلَكة حتى لا يضيف دخولُ المنطقة صفقةً ثانية عليها
      g_ea.zoneLegOrigin = s.legOrigin;
      g_ea.zoneLegHi     = s.zoneHi;
     }
  }

//--- الدخول الثالث: مضاعفة بالمسافة عندما يتحرك السعر ضد السلة
void TryDistanceEntry()
  {
   if(InpStepPoints <= 0)
      return;
   if(g_ea.tradesInCycle <= 0 || g_ea.cycleDir == 0)
      return;
   if(g_ea.tradesInCycle >= InpMaxTrades)
      return;
   if(g_ea.lastEntryPrice <= 0.0)
      return;

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double need = NextStepPoints() * g_point;
   if(need <= 0.0)
      return;

   bool trigger = (g_ea.cycleDir > 0) ? (bid <= g_ea.lastEntryPrice - need)
                  : (ask >= g_ea.lastEntryPrice + need);
   if(!trigger)
      return;

   OpenPosition(g_ea.cycleDir, NextLot(),
                StringFormat("martingale step %d", g_ea.tradesInCycle + 1));
  }

//--- تشخيص: لماذا لم تُفتح صفقة؟ سطر واحد لكل شمعة
void DebugEntryState(const SIndSnap &s)
  {
   if(!InpDebug || MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   static datetime lastBar = 0;
   datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar == 0 || bar == lastBar)
      return;
   lastBar = bar;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string why;

   if(g_ea.halted)
      why = "EA is halted by the equity stop — re-attach it to resume";
   else if(InpMaxSpread > 0 && SpreadPoints() > InpMaxSpread)
      why = StringFormat("spread %d exceeds InpMaxSpread %d", SpreadPoints(), InpMaxSpread);
   else if(g_ea.tradesInCycle > 0)
      why = StringFormat("basket already open (%d/%d)", g_ea.tradesInCycle, InpMaxTrades);
   else if(!InpEntryZoneTouch && !InpEntryOnArrow)
      why = "both entry modes are off";
   else if(s.legDir == 0)
      why = "the indicator reports no valid impulse leg yet";
   else if(!DirectionAllowed(s.legDir))
      why = StringFormat("leg is %s but InpDirection blocks that side",
                         (s.legDir > 0 ? "UP (buy)" : "DOWN (sell)"));
   else if(ZoneAlreadyTraded(s))
      why = "this leg was already traded — waiting for the next impulse";
   else if(!ZoneReached(s))
      why = StringFormat("price %s has not reached the discount region (0.618 %s, origin %s)",
                         DoubleToString(bid, _Digits),
                         DoubleToString(s.legDir > 0 ? s.zoneHi : s.zoneLo, _Digits),
                         DoubleToString(s.legOrigin, _Digits));
   else
      why = "all gates open — an entry should fire on the next tick";

   Log("entry check: " + why);
  }

//+------------------------------------------------------------------+
//|                    P R O T E C T I O N                           |
//+------------------------------------------------------------------+

//--- قاطع الأمان: يغلق كل شيء ويوقف الإكسبيرت عند تجاوز حد السحب
bool CheckEquityStop()
  {
   if(InpEquityStopPct <= 0.0)
      return false;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_ea.equityPeak)
      g_ea.equityPeak = eq;
   if(g_ea.equityPeak <= 0.0)
      return false;

   double ddPct = (g_ea.equityPeak - eq) / g_ea.equityPeak * 100.0;
   if(ddPct < InpEquityStopPct)
      return false;

   if(!g_ea.halted)
     {
      g_ea.halted = true;
      CloseBasket(StringFormat("equity stop: drawdown %.2f%%", ddPct));
      g_ea.Reset();
      Log("HALTED — remove and re-attach the EA to resume");
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                        S T A T U S                               |
//+------------------------------------------------------------------+
void ShowStatus(const SIndSnap &s, const int count, const double vol,
                const double avg, const double profit)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   //--- تحديث مرة كل ثانية بدل كل تيك (GetTickCount64 لا يتوقف بين التيكات)
   static ulong lastPaint = 0;
   ulong now = GetTickCount64();
   if(lastPaint != 0 && now - lastPaint < 1000)
      return;
   lastPaint = now;

   string dirTxt = (g_ea.cycleDir > 0) ? "BUY" : ((g_ea.cycleDir < 0) ? "SELL" : "-");
   string legTxt = (s.legDir > 0) ? "UP" : ((s.legDir < 0) ? "DOWN" : "-");
   string mode   = (InpDirection == TD_BUY_ONLY) ? "BUY ONLY"
                   : ((InpDirection == TD_SELL_ONLY) ? "SELL ONLY" : "BUY + SELL");

   string txt = StringFormat(
                   "GannFiboPro EA  |  %s  %s\n"
                   "mode: %s   spread: %d   %s\n"
                   "leg: %s   zone: %s - %s   %s\n"
                   "basket: %s  %d/%d  vol %.2f  avg %s\n"
                   "profit: %.2f (%.0f pts)   trail: %s\n"
                   "last arrow: %s (score %d)",
                   _Symbol, EnumToString((ENUM_TIMEFRAMES)Period()),
                   mode, SpreadPoints(), (g_ea.halted ? "*** HALTED ***" : "running"),
                   legTxt,
                   (s.zoneLo > 0.0 ? DoubleToString(s.zoneLo, _Digits) : "-"),
                   (s.zoneHi > 0.0 ? DoubleToString(s.zoneHi, _Digits) : "-"),
                   (PriceInZone(s) ? "[IN ZONE]" : (ZoneReached(s) ? "[DISCOUNT - entry armed]" : "")),
                   dirTxt, count, InpMaxTrades, vol,
                   (avg > 0.0 ? DoubleToString(avg, _Digits) : "-"),
                   profit, BasketProfitPoints(g_ea.cycleDir, avg),
                   (g_ea.trailArmed ? DoubleToString(g_ea.trailLevel, _Digits) : "off"),
                   (s.signal > 0 ? "BUY" : (s.signal < 0 ? "SELL" : "none")), s.score);
   Comment(txt);
  }

//+------------------------------------------------------------------+
//|                        E V E N T S                               |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- تحقق من الإدخالات
   if(InpLotStart <= 0.0)
     {
      Log("Base lot must be greater than zero");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotMult < 1.0)
     {
      Log("Lot multiplier must be >= 1.0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxTrades < 1)
     {
      Log("Max trades must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!InpEntryZoneTouch && !InpEntryOnArrow)
     {
      Log("Enable at least one entry mode");
      return INIT_PARAMETERS_INCORRECT;
     }

   //--- الإدخالات ثوابت وقت التشغيل — تُنسخ إلى متغيرات عمل قابلة للتقييد
   g_lotMult = MathMin(InpLotMult, ADR_LOT_MULT_MAX);
   if(InpLotMult > ADR_LOT_MULT_MAX)
      Log(StringFormat("lot multiplier clamped from %.2f to %.2f", InpLotMult, ADR_LOT_MULT_MAX));

   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tick  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_point <= 0.0)
     {
      Log("symbol point size is zero");
      return INIT_FAILED;
     }

   //--- تحذير على الحساب الصافي: المراكز تندمج في مركز واحد
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
      != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Log("netting account detected — martingale adds merge into one position (average price is still correct)");

   //--- إعداد CTrade
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- مقبض المؤشر (يستخدم إعداداته الافتراضية)
   g_hInd = iCustom(_Symbol, PERIOD_CURRENT, InpIndName, true);   // true = InpEaMode: no drawings/panel
   if(g_hInd == INVALID_HANDLE)
     {
      Log(StringFormat("cannot load indicator '%s' — compile it first, err=%d",
                       InpIndName, GetLastError()));
      return INIT_FAILED;
     }

   //--- الحالة الابتدائية
   g_ea.Reset();
   g_ea.usedArrowBar  = 0;
   g_ea.zoneLegOrigin = 0.0;
   g_ea.zoneLegHi     = 0.0;
   g_ea.halted        = false;
   g_ea.equityPeak    = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- تبنّي أي سلة قائمة من تشغيل سابق
   int count, dir; double vol, avg, profit;
   BasketInfo(count, vol, avg, profit, dir);
   if(count > 0)
     {
      g_ea.cycleDir       = dir;
      g_ea.tradesInCycle  = count;
      g_ea.lastLot        = LargestPositionVolume();   // آخر درجة في السلّم هي الأكبر
      g_ea.lastEntryPrice = avg;
      Log(StringFormat("adopted existing basket: %d positions, %.2f lots, avg %s",
                       count, vol, DoubleToString(avg, _Digits)));
     }

   Log(StringFormat("initialised | lot %.2f x%.2f | max %d | step %d pts | %s",
                    InpLotStart, g_lotMult, InpMaxTrades, InpStepPoints,
                    (InpDirection == TD_BUY_ONLY ? "BUY only"
                     : (InpDirection == TD_SELL_ONLY ? "SELL only" : "BUY + SELL"))));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hInd != INVALID_HANDLE)
      IndicatorRelease(g_hInd);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1) قراءة السلة أولاً — الحالة الحقيقية عند الوسيط
   int count, dir; double vol, avg, profit;
   BasketInfo(count, vol, avg, profit, dir);

   //--- السلة أُغلقت (هدف/وقف/يدوياً) — أنهِ الدورة
   if(count == 0 && g_ea.tradesInCycle > 0)
     {
      Log("cycle closed — state reset");
      g_ea.Reset();
     }
   if(count > 0)
      g_ea.cycleDir = dir;

   //--- 2) قاطع الأمان له الأولوية على كل شيء
   if(CheckEquityStop())
     {
      SIndSnap empty;
      ReadIndicator(empty);
      ShowStatus(empty, 0, 0.0, 0.0, 0.0);
      return;
     }

   //--- 3) لقطة المؤشر
   static bool linkLogged = false;
   SIndSnap s;
   if(!ReadIndicator(s))
     {
      if(!MQLInfoInteger(MQL_OPTIMIZATION))
         Comment("GannFiboPro EA  |  waiting for the indicator to calculate...");
      return;                                   // لا قرارات على بيانات ناقصة
     }

   if(!linkLogged)
     {
      linkLogged = true;
      Log(StringFormat("indicator link OK — legDir=%d zone %s..%s origin %s",
                       s.legDir, DoubleToString(s.zoneLo, _Digits),
                       DoubleToString(s.zoneHi, _Digits), DoubleToString(s.legOrigin, _Digits)));
     }

   //--- 4) إدارة السلة القائمة
   if(count > 0)
     {
      UpdateTrailing(g_ea.cycleDir, avg);
      if(CheckSoftExits(g_ea.cycleDir, avg))
        {
         g_ea.Reset();
         ShowStatus(s, 0, 0.0, 0.0, 0.0);
         return;
        }
      ApplyBasketStops(g_ea.cycleDir, avg);
     }

   //--- 5) الدخولات — تُمنع فقط عند اتساع السبريد
   bool spreadOk = (InpMaxSpread <= 0 || SpreadPoints() <= InpMaxSpread);
   if(spreadOk && !g_ea.halted)
     {
      TryArrowEntry(s);         // السهم أولاً: قد يغلق السلة عند الانعكاس
      TryZoneEntry(s);          // الدخول الأول عند بلوغ منطقة الخصم
      TryDistanceEntry();       // مضاعفات المسافة
     }
   DebugEntryState(s);

   //--- 6) الحالة على الشارت
   BasketInfo(count, vol, avg, profit, dir);
   ShowStatus(s, count, vol, avg, profit);
  }
//+------------------------------------------------------------------+
