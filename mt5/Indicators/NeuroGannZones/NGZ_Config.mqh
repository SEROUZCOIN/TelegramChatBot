//+------------------------------------------------------------------+
//|                                                   NGZ_Config.mqh |
//|                        Neuro Gann Zones - CONFIG layer            |
//|  Every input, enum, theme colour, pixel metric and tuning         |
//|  constant of the whole project lives HERE and nowhere else.       |
//+------------------------------------------------------------------+
#ifndef __NGZ_CONFIG_MQH__
#define __NGZ_CONFIG_MQH__

//+------------------------------------------------------------------+
//| Structural constants                                             |
//+------------------------------------------------------------------+
#define NGZ_FEATURES        12      // number of network inputs (math+gann features)
#define NGZ_STRIDE          15      // per-bar cache stride (features + 3 extra slots)
#define NGZ_SLOT_BASE       12      // cached regression baseline (price space)
#define NGZ_SLOT_GANN       13      // cached geometric (Gann) score  [-1..1]
#define NGZ_SLOT_MATH       14      // cached mathematical score      [-1..1]

#define NGZ_HIDDEN_MAX      32      // hard cap for the hidden layer
#define NGZ_FAN_COUNT        9      // Gann fan rays: 1x8 .. 8x1
#define NGZ_SQ9_MAX         16      // max Square-of-9 levels per side
#define NGZ_CYCLE_MAX       12      // max Gann time cycles
#define NGZ_CYCLE_DRAW_MAX  40      // max cycle markers drawn at once

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_NGZ_SCALE
  {
   NGZ_SCALE_ATR,       // Adaptive - ATR based (recommended)
   NGZ_SCALE_RANGE,     // Statistical - Range / Bars
   NGZ_SCALE_CHART,     // Geometric  - visual 45 degrees
   NGZ_SCALE_MANUAL     // Manual     - points per bar
  };

enum ENUM_NGZ_ANCHOR
  {
   NGZ_ANCHOR_SWING,    // Auto - confirmed swing pivots
   NGZ_ANCHOR_EXTREME,  // Auto - highest / lowest of lookback
   NGZ_ANCHOR_MANUAL    // Manual - fixed date
  };

enum ENUM_NGZ_MODE
  {
   NGZ_MODE_FUSION,     // Fusion  - neuro + math + gann (recommended)
   NGZ_MODE_NEURO,      // Neural network only
   NGZ_MODE_MATH,       // Mathematical models only
   NGZ_MODE_GANN        // Gann geometry only
  };

enum ENUM_NGZ_SQ9SCALE
  {
   NGZ_SQ9_AUTO,        // Auto - 10^Digits (works on FX, metals, indices)
   NGZ_SQ9_MANUAL       // Manual multiplier
  };

enum ENUM_NGZ_CORNER
  {
   NGZ_CORNER_LU,       // Left upper
   NGZ_CORNER_RU,       // Right upper
   NGZ_CORNER_LL,       // Left lower
   NGZ_CORNER_RL        // Right lower
  };

//+------------------------------------------------------------------+
//| THEME - the ONLY place a colour literal may appear                |
//| Futuristic dark scheme: neon blue + gold accents                  |
//+------------------------------------------------------------------+
#define NGZ_CLR_BG            C'14,17,23'      // panel background
#define NGZ_CLR_BG_HEAD       C'20,26,38'      // panel header strip
#define NGZ_CLR_BG_ROW        C'18,22,30'      // row background
#define NGZ_CLR_BORDER        C'38,48,66'      // hairline borders
#define NGZ_CLR_NEON          C'0,208,255'     // primary neon blue accent
#define NGZ_CLR_GOLD          C'255,196,0'     // gold accent (Gann geometry)
#define NGZ_CLR_TEXT          C'226,232,240'   // primary text
#define NGZ_CLR_TEXT_DIM      C'126,140,160'   // secondary text
#define NGZ_CLR_UP            C'0,230,160'     // bullish
#define NGZ_CLR_DOWN          C'255,72,102'    // bearish
#define NGZ_CLR_FLAT          C'110,120,135'   // neutral
#define NGZ_CLR_ZONE_UP       C'10,52,42'      // filled bullish zone
#define NGZ_CLR_ZONE_DOWN     C'62,20,30'      // filled bearish zone
#define NGZ_CLR_ZONE_PREM     C'54,24,34'      // premium zone
#define NGZ_CLR_ZONE_DISC     C'14,46,40'      // discount zone
#define NGZ_CLR_ZONE_CYCLE    C'34,30,16'      // time-cycle band
#define NGZ_CLR_CONFLUENCE    C'255,140,0'     // Gann/Sq9 confluence zone
#define NGZ_CLR_FAN_MAIN      C'255,196,0'     // the 1x1 ray
#define NGZ_CLR_FAN_SUB       C'0,140,190'     // secondary rays
#define NGZ_CLR_SQ9           C'150,120,220'   // Square of 9 levels
#define NGZ_CLR_FIB           C'120,150,190'   // Gann eighths / Fibonacci

//+------------------------------------------------------------------+
//| METRICS - the ONLY place a pixel literal may appear                |
//+------------------------------------------------------------------+
#define NGZ_UI_PAD            8
#define NGZ_UI_ROW_H          17
#define NGZ_UI_HEAD_H         26
#define NGZ_UI_PANEL_W        250
#define NGZ_UI_LAB_W          74
#define NGZ_UI_GAUGE_W        84
#define NGZ_UI_GAUGE_H        7
#define NGZ_UI_BTN_W          46
#define NGZ_UI_BTN_H          18
#define NGZ_UI_FONT           "Consolas"
#define NGZ_UI_FONT_HEAD      "Segoe UI Semibold"
#define NGZ_UI_FS             8
#define NGZ_UI_FS_HEAD        10

//+------------------------------------------------------------------+
//| Mathematical consensus weights (transparent, tunable)             |
//| Trend-following features are added, mean-reversion subtracted.    |
//+------------------------------------------------------------------+
#define NGZ_W_SLOPE           1.20    // regression slope
#define NGZ_W_R2              0.55    // regression quality
#define NGZ_W_EFF             1.00    // Kaufman efficiency ratio
#define NGZ_W_ZSCORE         -0.45    // z-score (mean reversion)
#define NGZ_W_RSI             0.70    // RSI momentum
#define NGZ_W_VOLREG          0.15    // volatility regime
#define NGZ_W_MOM             0.90    // ATR-normalised momentum
#define NGZ_W_VR              0.50    // variance ratio (persistence)
#define NGZ_W_PREMIUM        -0.55    // premium/discount (mean reversion)
#define NGZ_W_VOLUME          0.35    // volume trend
#define NGZ_W_MATH_NORM       6.35    // sum of |weights| used for normalisation

#define NGZ_W_GANN_FAN        1.50    // fan position weight
#define NGZ_W_GANN_SQ9        0.70    // Square-of-9 proximity weight
#define NGZ_W_GANN_NORM       2.20    // normaliser for the geometric score

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== 1. ENGINE ==="
input ENUM_NGZ_MODE   InpMode            = NGZ_MODE_FUSION;  // Decision engine
input double          InpWeightNeuro     = 0.45;             // Fusion weight: neural
input double          InpWeightMath      = 0.35;             // Fusion weight: mathematical
input double          InpWeightGann      = 0.20;             // Fusion weight: Gann geometry
input int             InpMaxBars         = 4000;             // Max bars to process (0 = all)

input group "=== 2. GANN GEOMETRY ==="
input ENUM_NGZ_ANCHOR InpAnchorMode      = NGZ_ANCHOR_SWING; // Anchor detection
input int             InpSwingBars       = 8;                // Swing strength (bars each side)
input int             InpSwingLookback   = 300;              // Master range lookback (bars)
input datetime        InpManualAnchor    = D'2026.01.01 00:00'; // Manual anchor time
input ENUM_NGZ_SCALE  InpScaleMode       = NGZ_SCALE_ATR;    // Price/time unit (1x1 scale)
input double          InpAtrFactor       = 0.55;             // ATR factor for the 1x1 unit
input double          InpManualUnit      = 100.0;            // Manual unit (points per bar)
input int             InpFanLength       = 260;              // Fan projection length (bars)
input bool            InpShowFan         = true;             // Draw Gann fan (1x8 .. 8x1)
input bool            InpShowFanLabels   = true;             // Label each ray with its angle
input bool            InpDualFan         = true;             // Draw both bull and bear fans

input group "=== 3. GANN SQUARE OF 9 ==="
input bool            InpShowSq9         = true;             // Draw Square of 9 levels
input double          InpSq9Turn         = 2.0;              // sqrt increment per 360 deg (1 or 2)
input double          InpSq9Step         = 45.0;             // Degrees per level
input int             InpSq9Levels       = 6;                // Levels each side
input ENUM_NGZ_SQ9SCALE InpSq9ScaleMode  = NGZ_SQ9_AUTO;     // Square of 9 price scaling
input double          InpSq9ScaleManual  = 10000.0;          // Manual scale multiplier

input group "=== 4. GANN EIGHTHS / TIME CYCLES ==="
input bool            InpShowRetrace     = true;             // Draw Gann eighths + thirds
input bool            InpShowCycles      = true;             // Draw Gann time cycles
input string          InpCycleList       = "45,90,144,180,225,270,360"; // Cycle lengths (bars)
input int             InpCycleBand       = 2;                // Cycle band half-width (bars)

input group "=== 5. ZONES ==="
input bool            InpShowZones       = true;             // Master zone switch
input bool            InpShowFanZones    = true;             // Gann power / balance triangles
input bool            InpShowPremium     = true;             // Premium / discount / equilibrium
input bool            InpShowConfluence  = true;             // Gann x Sq9 confluence zones
input bool            InpShowProjection  = true;             // Forward projection zone
input double          InpConfluenceATR   = 0.35;             // Confluence tolerance (x ATR)
input int             InpProjectBars     = 30;               // Projection depth (bars)

input group "=== 6. MATHEMATICS ==="
input int             InpRegPeriod       = 40;               // Linear regression period
input int             InpAtrPeriod       = 14;               // ATR period
input int             InpAtrAvgPeriod    = 60;               // ATR baseline period (regime)
input int             InpRsiPeriod       = 14;               // RSI period
input int             InpEffPeriod       = 20;               // Efficiency ratio period
input int             InpZPeriod         = 30;               // Z-score period
input int             InpMomPeriod       = 12;               // Momentum period
input int             InpVrPeriod        = 60;               // Variance ratio window
input int             InpVrLag           = 5;                // Variance ratio lag (k)
input int             InpVolPeriod       = 20;               // Volume regression period

input group "=== 7. NEURAL NETWORK ==="
input bool            InpUseNeuro        = true;             // Enable the neural layer
input int             InpHidden          = 10;               // Hidden neurons (2..32)
input int             InpTrainBars       = 2500;             // Training window (bars)
input int             InpEpochs          = 40;               // Training epochs
input double          InpLearnRate       = 0.030;            // Learning rate
input double          InpLrDecay         = 0.97;             // Learning-rate decay per epoch
input double          InpL2              = 0.00005;          // L2 weight decay
input int             InpHorizon         = 5;                // Target horizon (bars ahead)
input double          InpTargetATR       = 1.20;             // Target scaling (x ATR)
input int             InpNetSeed         = 20260907;         // RNG seed (reproducibility)
input int             InpMinSamples      = 300;              // Minimum training samples
input bool            InpPersistNet      = false;            // Save/load weights to file

input group "=== 8. SIGNALS & ALERTS ==="
input double          InpSignalLevel     = 0.35;             // Signal threshold |score|
input double          InpExitLevel       = 0.12;             // Neutral band |score|
input bool            InpRequireRail     = true;             // Require price on the right side of the 1x1 rail
input double          InpTrendAmp        = 1.60;             // Trend line amplitude (x ATR)
input int             InpRailBars        = 300;              // Max rail length (bars)
input bool            InpAlertPopup      = true;             // Terminal alert
input bool            InpAlertPush       = false;            // Push notification
input bool            InpAlertMail       = false;            // E-mail
input bool            InpAlertSound      = true;             // Sound
input string          InpSoundFile       = "alert.wav";      // Sound file

input group "=== 9. DASHBOARD ==="
input bool            InpShowPanel       = true;             // Show dashboard
input ENUM_NGZ_CORNER InpPanelCorner     = NGZ_CORNER_LU;    // Panel corner
input int             InpPanelX          = 12;               // Panel X offset (px)
input int             InpPanelY          = 22;               // Panel Y offset (px)
input bool            InpPanelDpi        = true;             // Scale panel with screen DPI

#endif // __NGZ_CONFIG_MQH__
//+------------------------------------------------------------------+
