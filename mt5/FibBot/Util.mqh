//+------------------------------------------------------------------+
//|                                                         Util.mqh |
//|  Generic, project-neutral helpers: normalisation, sizing, JSON.  |
//|  Nothing here knows about Fibonacci — these move to a shared     |
//|  Common.mqh unchanged.                                           |
//+------------------------------------------------------------------+
#ifndef FIBBOT_UTIL_MQH
#define FIBBOT_UTIL_MQH

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

//--- JSON ----------------------------------------------------------

// تهريب المحارف التي تكسر JSON — النص التحليلي مولّد فلا بد منه
string JsonEscape(const string src)
  {
   string out = "";
   int    n   = StringLen(src);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(src, i);
      if(c == '"')
         out += "\\\"";
      else if(c == '\\')
         out += "\\\\";
      else if(c == '\n')
         out += "\\n";
      else if(c == '\r')
         out += "\\r";
      else if(c == '\t')
         out += "\\t";
      else if(c < 32)
         out += " ";
      else
         out += ShortToString(c);
     }
   return(out);
  }

string JsonStr(const string key, const string value)
  {
   return("\"" + key + "\":\"" + JsonEscape(value) + "\"");
  }

string JsonNum(const string key, const double value, const int digits)
  {
   return("\"" + key + "\":" + DoubleToString(value, digits));
  }

string JsonBool(const string key, const bool value)
  {
   return("\"" + key + "\":" + (value ? "true" : "false"));
  }

string JsonObj(const string body)
  {
   return("{" + body + "}");
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

#endif // FIBBOT_UTIL_MQH
//+------------------------------------------------------------------+
