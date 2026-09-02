//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|  CONFIG layer: every input, enum, constant, colour and dimension. |
//|  Nothing in this file changes after OnInit — runtime-mutable      |
//|  values live in State.mqh and are SEEDED from here.               |
//+------------------------------------------------------------------+
#ifndef GFEA_CONFIG_MQH
#define GFEA_CONFIG_MQH

//+------------------------------------------------------------------+
//| ENUMS — the comment after each member becomes its dropdown label |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
  {
   LOT_FIXED,              // Fixed lot
   LOT_RISK_PERCENT,       // Risk % of equity per structural stop
   LOT_PER_BALANCE         // Lot per balance step
  };

enum ENUM_LOT_PROGRESSION
  {
   PROG_FLAT,              // Flat - every grid level same lot
   PROG_LINEAR,            // Linear - 1x 2x 3x 4x
   PROG_FIBONACCI,         // Fibonacci - 1 1 2 3 5 8
   PROG_GEOMETRIC          // Geometric - factor^level (martingale)
  };

enum ENUM_GRID_SPACING
  {
   SPACING_FIB_LEG,        // Fibonacci ratios of the impulse leg
   SPACING_ATR_FIB,        // ATR x Fibonacci widening (1 1.618 2.618 ...)
   SPACING_ATR_LINEAR,     // ATR x fixed multiple, equal steps
   SPACING_FIXED_POINTS    // Fixed points, equal steps
  };

enum ENUM_BASKET_TP
  {
   BTP_FIB_EXTENSION,      // Fibonacci extension of the anchor leg
   BTP_MONEY,              // Fixed money target for the whole basket
   BTP_EQUITY_PCT,         // % of equity for the whole basket
   BTP_FIRST_HIT           // Whichever of fib / money comes first
  };

enum ENUM_REGIME_POLICY
  {
   REGIME_TREND_ONLY,      // Only trade confirmed trends
   REGIME_RANGE_ONLY,      // Only trade ranges
   REGIME_BOTH             // Trend and range (never chop)
  };

enum ENUM_ENTRY_CONFIRM
  {
   CONFIRM_NONE,           // Zone touch is enough
   CONFIRM_MA_RECLAIM,     // Close back through the fast MA
   CONFIRM_REJECTION,      // Rejection wick out of the zone
   CONFIRM_BOTH            // MA reclaim AND rejection wick
  };

enum ENUM_TRAIL_MODE
  {
   TRAIL_OFF,              // No trailing
   TRAIL_ATR,              // ATR distance behind price
   TRAIL_FIB_STEP          // Step up through the fib extension ladder
  };

enum ENUM_MARKET_REGIME
  {
   REG_CHOP,               // No tradable structure
   REG_TREND_UP,           // Confirmed uptrend
   REG_TREND_DOWN,         // Confirmed downtrend
   REG_RANGE               // Mean-reverting range
  };

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== 01. Identity & Master Switches ==="
input long   InpMagic              = 987654321;   // Magic Number
input string InpTradeComment       = "GFEA";      // Order comment prefix
input bool   InpEnableTrading      = true;        // Trading enabled at start
input bool   InpCloseOnDeinit      = false;       // Close everything when EA is removed

input group "=== 02. Advanced Moving Average Engine ==="
input ENUM_TIMEFRAMES     InpSignalTF     = PERIOD_CURRENT; // Signal timeframe
input int                 InpMaFast       = 21;    // Fast MA period
input int                 InpMaMid        = 55;    // Mid MA period
input int                 InpMaSlow       = 200;   // Slow MA period
input ENUM_MA_METHOD      InpMaMethod     = MODE_EMA;          // MA method
input ENUM_APPLIED_PRICE  InpMaPrice      = PRICE_CLOSE;       // MA applied price
input bool                InpUseHtf       = true;  // Use higher timeframe confirmation
input ENUM_TIMEFRAMES     InpHtfTF        = PERIOD_H4;         // Higher timeframe
input int                 InpHtfMaPeriod  = 100;   // Higher timeframe MA period
input int                 InpSlopeBars    = 5;     // Bars used to measure MA slope
input double              InpMinSlopeAtr  = 0.10;  // Min slope per bar (x ATR) for a trend

input group "=== 03. Regime Filter (ADX) ==="
input ENUM_REGIME_POLICY  InpRegimePolicy = REGIME_BOTH; // Which regimes may open a cycle
input int                 InpAdxPeriod    = 14;    // ADX period
input double              InpAdxTrendMin  = 22.0;  // ADX above this = trend
input double              InpAdxRangeMax  = 18.0;  // ADX below this = range

input group "=== 04. Fibonacci Structure ==="
input int    InpSwingLookback  = 180;   // Bars scanned for the impulse leg
input int    InpPivotStrength  = 3;     // Bars each side of a confirmed pivot
input double InpMinSwingAtr    = 2.0;   // Min leg size (x ATR) to be tradable
input double InpEntryFibMin    = 0.382; // Entry zone starts at this retracement
input double InpEntryFibMax    = 0.786; // Entry zone ends at this retracement
input double InpSlFibLevel     = 1.000; // Structural stop at this retracement
input double InpSlAtrBuffer    = 0.35;  // Extra ATR buffer beyond the stop level
input double InpTp1Fib         = 1.272; // TP1 extension
input double InpTp2Fib         = 1.618; // TP2 extension
input double InpTp3Fib         = 2.618; // TP3 extension
input double InpTp1ClosePct    = 40.0;  // % of the basket closed at TP1
input double InpTp2ClosePct    = 35.0;  // % of the remainder closed at TP2
input ENUM_ENTRY_CONFIRM InpEntryConfirm = CONFIRM_MA_RECLAIM; // Entry confirmation

input group "=== 05. Grid Engine ==="
input bool               InpGridEnable      = true;             // Enable grid additions
input ENUM_GRID_SPACING  InpGridSpacing     = SPACING_ATR_FIB;  // Grid spacing model
input int                InpGridMaxLevels   = 6;     // Max levels per cycle (incl. first entry)
input double             InpGridBaseAtr     = 1.0;   // Base spacing (x ATR)
input int                InpGridFixedPoints = 300;   // Base spacing when spacing = fixed points
input ENUM_LOT_PROGRESSION InpLotProgression = PROG_FLAT; // Lot progression across levels
input double             InpLotFactor       = 1.5;   // Geometric factor (progression only)
input double             InpGridMaxLotTotal = 0.0;   // Hard cap on total basket lots (0 = auto)
input int                InpCooldownBars    = 3;     // Bars to wait after a cycle closes

input group "=== 06. Basket Exit ==="
input ENUM_BASKET_TP InpBasketTpMode   = BTP_FIRST_HIT; // Basket take profit model
input double         InpBasketTpMoney  = 50.0;   // Basket target in account currency
input double         InpBasketTpPct    = 1.0;    // Basket target as % of equity
input double         InpCycleMaxLossPct= 4.0;    // Cycle killed at this % equity loss

input group "=== 07. Risk & Position Sizing ==="
input ENUM_LOT_MODE InpLotMode       = LOT_RISK_PERCENT; // Lot sizing model
input double InpFixedLot             = 0.01;  // Fixed lot
input double InpRiskPercent          = 0.75;  // Risk % of equity on the first entry
input double InpLotPerBalance        = 0.01;  // Lot per balance step
input double InpBalanceStep          = 1000;  // Balance step for lot-per-balance
input double InpMaxTotalRiskPct      = 6.0;   // Max theoretical basket risk (% equity)
input int    InpMaxSpreadPoints      = 35;    // Max spread allowed (points)
input int    InpSlippagePoints       = 20;    // Max deviation (points)

input group "=== 08. Account Protection ==="
input double InpMaxDailyLossPct   = 4.0;   // Max daily loss (% of day-start balance)
input double InpMaxDailyProfitPct = 6.0;   // Daily profit target that stops trading
input double InpMaxTotalDDPct     = 12.0;  // Max drawdown from equity peak (%)
input bool   InpHaltOnBreach      = true;  // Close all and halt when a limit breaks
input double InpMinEquityStop     = 0.0;   // Absolute equity floor (0 = off)

input group "=== 09. Trade Management ==="
input bool           InpUseBreakEven  = true;  // Move stop to break-even
input double         InpBeTriggerR    = 1.0;   // Break-even trigger (R multiple)
input int            InpBeOffsetPoints= 30;    // Break-even offset (points)
input ENUM_TRAIL_MODE InpTrailMode    = TRAIL_ATR; // Trailing model
input double         InpTrailAtr      = 2.0;   // Trailing distance (x ATR)
input int            InpTrailStepPts  = 50;    // Min improvement before modifying (points)
input int            InpAtrPeriod     = 14;    // ATR period (structure, grid, trailing)

input group "=== 10. Session & Time Filter ==="
input bool   InpUseTimeFilter = false; // Restrict trading hours
input int    InpStartHour     = 7;     // Session start hour (server time)
input int    InpEndHour       = 21;    // Session end hour (server time)
input bool   InpTradeMonday   = true;  // Trade Monday
input bool   InpTradeTuesday  = true;  // Trade Tuesday
input bool   InpTradeWednesday= true;  // Trade Wednesday
input bool   InpTradeThursday = true;  // Trade Thursday
input bool   InpTradeFriday   = true;  // Trade Friday
input int    InpFridayCloseHr = 0;     // Close all at this hour Friday (0 = off)
input int    InpNewsPauseMin  = 0;     // Minutes to pause around InpNewsTimes (0 = off)
input string InpNewsTimes     = "";    // Manual news times "HH:MM,HH:MM" server time

input group "=== 11. Alerts & Telegram ==="
input bool   InpAlertsOn        = true;  // Terminal alerts
input bool   InpPushOn          = false; // MetaQuotes push notifications
input bool   InpTelegramOn      = false; // Telegram alerts
input string InpTelegramToken   = "";    // Telegram bot token
input string InpTelegramChatId  = "";    // Telegram chat id

input group "=== 12. Telemetry to Python Dashboard ==="
input bool   InpTelemetryOn      = false; // Stream telemetry to the dashboard
input string InpTelemetryUrl     = "http://127.0.0.1:8050/ingest"; // Dashboard ingest URL
input string InpTelemetryKey     = "";    // Ingest key (X-Ingest-Key)
input int    InpTelemetrySeconds = 5;     // Telemetry interval (seconds)

input group "=== 13. On-Chart Dashboard ==="
input bool   InpShowPanel   = true;  // Show the on-chart panel
input bool   InpDrawFib     = true;  // Draw the fib structure on the chart
input bool   InpDrawGrid    = true;  // Draw grid levels on the chart
input int    InpPanelX      = 16;    // Panel X offset (px)
input int    InpPanelY      = 16;    // Panel Y offset (px)
input bool   InpPanelRight  = false; // Dock the panel on the right

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define GFEA_NAME          "GRID FIBONACCI PRO"
#define GFEA_VERSION       "1.00"
#define LOG_TAG            "GFEA"
#define RETRY_MAX          3          // send attempts on retryable retcodes
#define MAX_GRID_LEVELS    32         // absolute ceiling regardless of inputs
#define TELEMETRY_TIMEOUT  4000       // ms — WebRequest timeout
#define STATE_FILE_SUFFIX  "_state.bin"

//--- Fibonacci ladders used everywhere in the EA
double FIB_RETRACE[7] = {0.236, 0.382, 0.500, 0.618, 0.705, 0.786, 1.000};
double FIB_EXTEND[5]  = {1.272, 1.414, 1.618, 2.000, 2.618};
double FIB_WIDEN[8]   = {1.000, 1.618, 2.618, 4.236, 6.854, 11.090, 17.944, 29.034};
double FIB_LOTS[8]    = {1.0, 1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0};

//+------------------------------------------------------------------+
//| THEME — every colour in the program is defined here only         |
//| Futuristic dark: neon cyan primary, gold accent, deep navy base  |
//+------------------------------------------------------------------+
#define THEME_BG          C'8,12,20'       // panel background
#define THEME_BG_HEAD     C'14,22,36'      // header strip
#define THEME_BG_ROW      C'11,17,28'      // alternating row
#define THEME_NEON        C'0,229,255'     // neon cyan — primary accent
#define THEME_NEON_DIM    C'0,122,140'     // dimmed cyan
#define THEME_GOLD        C'255,199,44'    // gold — highlights and titles
#define THEME_GOLD_DIM    C'146,114,26'    // dimmed gold
#define THEME_TEXT        C'226,238,245'   // primary text
#define THEME_TEXT_DIM    C'122,140,158'   // secondary text
#define THEME_BUY         C'0,230,150'     // long / profit
#define THEME_SELL        C'255,74,110'    // short / loss
#define THEME_WARN        C'255,164,46'    // warning
#define THEME_BORDER      C'30,44,66'      // borders and separators
#define THEME_ZONE_BULL   C'10,58,52'      // bullish zone fill
#define THEME_ZONE_BEAR   C'62,20,34'      // bearish zone fill
#define THEME_GRID_LINE   C'86,110,150'    // grid level line

//+------------------------------------------------------------------+
//| METRICS — every pixel dimension is defined here only              |
//+------------------------------------------------------------------+
#define UI_FONT        "Consolas"
#define UI_FONT_TITLE  "Segoe UI Semibold"
#define UI_FS          9      // base font size
#define UI_FS_TITLE    11     // title font size
#define UI_FS_BIG      14     // hero value font size
#define UI_PAD         10     // uniform padding
#define UI_PANEL_W     286    // panel width
#define UI_HEAD_H      30     // header height
#define UI_ROW_H       17     // info row height
#define UI_SEC_H       19     // section header height
#define UI_BTN_H       22     // button height
#define UI_BTN_GAP     6      // gap between buttons
#define UI_LED         8      // status LED size

#endif // GFEA_CONFIG_MQH
//+------------------------------------------------------------------+
