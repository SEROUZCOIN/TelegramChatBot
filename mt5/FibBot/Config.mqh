//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|  CONFIG + STATE for FibBot: inputs, constants, shared structs.   |
//+------------------------------------------------------------------+
#ifndef FIBBOT_CONFIG_MQH
#define FIBBOT_CONFIG_MQH

//--- CONFIG: enums -------------------------------------------------

// متى تُنشر الإشارة على المنصة
enum ENUM_PUBLISH_WHEN
  {
   PUBLISH_ON_SETUP,       // When the setup arms (pending zone)
   PUBLISH_ON_ENTRY        // When the trigger confirms (default)
  };

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

input group "=== Platform integration ==="
input bool   InpPublishSignals = true;   // POST setups to the platform API
input string InpApiBaseUrl     = "https://api.example.com/api"; // API base URL
input string InpIngestKey      = "";     // X-Ingest-Key
input string InpMinPlan        = "SIGNALS"; // Tier that receives these signals
input bool   InpPublishNow     = false;  // Publish immediately, or leave as a draft
input ENUM_PUBLISH_WHEN InpPublishWhen = PUBLISH_ON_ENTRY; // When to post the signal
input bool   InpReportUpdates  = true;   // Report entry, BE, TP and SL events

input group "=== Chart display ==="
input bool   InpShowVisuals    = true;   // Draw the setup on the chart

//--- CONFIG: constants ---------------------------------------------

#define LOG_PREFIX      "FibBot: "
#define OBJ_PREFIX      "FibBot_"
#define HTTP_TIMEOUT    5000
#define API_QUEUE_MAX   64
#define API_RETRY_MAX   3
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
   bool     published;
   bool     entryReported;
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

#endif // FIBBOT_CONFIG_MQH
//+------------------------------------------------------------------+
