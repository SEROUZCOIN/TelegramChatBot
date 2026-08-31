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
#ifndef FIBBOT_FIB_MQH
#define FIBBOT_FIB_MQH

#include "Config.mqh"
#include "Swing.mqh"
#include "Util.mqh"

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

#endif // FIBBOT_FIB_MQH
//+------------------------------------------------------------------+
