//+------------------------------------------------------------------+
//|                                                     AQ_Theme.mqh |
//|              APEX QUANTUM — Supply/Demand · Structure Engine     |
//|         THEME (colour library) + METRICS (dimension library)     |
//|                                                                  |
//|  Single source of truth for every colour and every pixel size    |
//|  used by the system. No raw colour literal and no raw pixel      |
//|  number may appear anywhere else in the project — restyling the  |
//|  whole product is a one-file edit.                               |
//+------------------------------------------------------------------+
#ifndef AQ_THEME_MQH
#define AQ_THEME_MQH

//+------------------------------------------------------------------+
//| THEME — dark futuristic surface, neon-blue + gold accents        |
//+------------------------------------------------------------------+
//--- panel surfaces
#define AQ_CLR_BG              C'8,11,18'       // panel background
#define AQ_CLR_BG_ALT          C'14,19,30'      // alternating row background
#define AQ_CLR_HEADER          C'17,24,39'      // header strip
#define AQ_CLR_BORDER          C'32,44,66'      // hairline borders
#define AQ_CLR_TRACK           C'23,31,46'      // empty gauge track

//--- accents
#define AQ_CLR_NEON            C'0,216,255'     // primary neon blue
#define AQ_CLR_NEON_DIM        C'0,96,124'      // neon blue, dimmed (animation floor)
#define AQ_CLR_GOLD            C'255,195,0'     // gold accent
#define AQ_CLR_GOLD_DIM        C'128,98,0'      // gold, dimmed (animation floor)

//--- typography
#define AQ_CLR_TEXT            C'226,232,240'   // primary text
#define AQ_CLR_TEXT_DIM        C'118,132,156'   // secondary / captions
#define AQ_CLR_TEXT_MUTE       C'72,84,104'     // disabled

//--- directional semantics
#define AQ_CLR_BULL            C'0,230,150'     // bullish / buy
#define AQ_CLR_BEAR            C'255,72,102'    // bearish / sell
#define AQ_CLR_FLAT            C'150,160,180'   // neutral
#define AQ_CLR_WARN            C'255,159,28'    // warning

//--- buttons
#define AQ_CLR_BTN_OFF         C'22,30,45'      // toggle released
#define AQ_CLR_BTN_ON          C'0,86,110'      // toggle engaged
#define AQ_CLR_BTN_TXT_OFF     C'118,132,156'
#define AQ_CLR_BTN_TXT_ON      C'0,216,255'
#define AQ_CLR_BTN_ACT         C'60,46,0'       // momentary action button

//--- demand (support) zones, by grade  WEAK/BROKEN/FRESH/TESTED/PROVEN
#define AQ_CLR_DEM_WEAK        C'26,58,52'
#define AQ_CLR_DEM_BROKEN      C'96,110,60'
#define AQ_CLR_DEM_FRESH       C'0,138,118'
#define AQ_CLR_DEM_TESTED      C'0,180,130'
#define AQ_CLR_DEM_PROVEN      C'0,230,150'

//--- supply (resistance) zones, by grade
#define AQ_CLR_SUP_WEAK        C'60,30,66'
#define AQ_CLR_SUP_BROKEN      C'176,96,20'
#define AQ_CLR_SUP_FRESH       C'170,72,150'
#define AQ_CLR_SUP_TESTED      C'220,50,90'
#define AQ_CLR_SUP_PROVEN      C'255,72,102'

//--- market structure overlays
#define AQ_CLR_FVG_BULL        C'12,74,66'      // bullish imbalance box
#define AQ_CLR_FVG_BEAR        C'86,28,46'      // bearish imbalance box
#define AQ_CLR_CHAN_UP         C'0,216,255'     // channel upper rail
#define AQ_CLR_CHAN_MID        C'255,195,0'     // channel mid line
#define AQ_CLR_CHAN_DN         C'0,216,255'     // channel lower rail
#define AQ_CLR_BOS             C'0,216,255'     // break of structure
#define AQ_CLR_CHOCH           C'255,195,0'     // change of character
#define AQ_CLR_FIB             C'150,110,220'   // fibonacci retracement

//+------------------------------------------------------------------+
//| METRICS — every pixel dimension of the dashboard                 |
//+------------------------------------------------------------------+
#define AQ_PANEL_W            274               // dashboard width
#define AQ_PAD                  8               // uniform inner padding
#define AQ_HDR_H               28               // header strip height
#define AQ_ROW_H               17               // standard info row height
#define AQ_ROW_BIG             26               // bias row height
#define AQ_GAUGE_H              9               // score gauge height
#define AQ_BTN_H               19               // toggle button height
#define AQ_BTN_GAP              3               // gap between buttons
#define AQ_SWEEP_W             46               // animated header sweep width
#define AQ_DOT_W               10               // pulsing status dot size
#define AQ_SEP_H                1               // separator thickness

//--- typography metrics
#define AQ_FONT               "Segoe UI"        // UI font
#define AQ_FONT_MONO          "Consolas"        // numeric font
#define AQ_FONT_ICON          "Wingdings"       // arrow glyph font
#define AQ_FS                   8               // body font size
#define AQ_FS_SM                7               // caption font size
#define AQ_FS_TITLE             9               // header font size
#define AQ_FS_BIG              12               // bias font size

//--- Wingdings glyph codes (rendered through AQ_FONT_ICON)
#define AQ_GLYPH_UP           233               // solid up arrow
#define AQ_GLYPH_DN           234               // solid down arrow
#define AQ_GLYPH_DOT          159               // small filled dot (neutral)

//--- chart drawing metrics
#define AQ_ZONE_EXT_BARS       12               // bars a zone projects to the right
#define AQ_ARROW_ATR_OFF      0.6               // signal arrow offset, in ATR units

#endif // AQ_THEME_MQH
//+------------------------------------------------------------------+
