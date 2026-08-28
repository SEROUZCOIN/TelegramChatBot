/**
 * Risk disclaimer shown on first launch and gated on before the app opens.
 *
 * This is a compliance requirement, not boilerplate. Both stores scrutinise
 * trading apps, and the framing here — education and analysis, never advice,
 * never execution — is what keeps the app outside Apple guideline 3.2.1(viii)
 * ("apps used for financial trading, investing, or money management should be
 * submitted by the financial institution performing such services").
 *
 * If this wording changes materially, bump RISK_DISCLAIMER_VERSION so every
 * user is asked to accept the new version.
 */
export const RISK_DISCLAIMER_TEXT = `
RISK DISCLOSURE AND TERMS OF USE

Educational content only. Everything in this app — signals, chart analysis,
courses, and coaching — is published for education and information. It is not
financial, investment, or trading advice, and it is not a recommendation to buy
or sell any instrument.

We are not a broker or a financial institution. This app does not execute
trades, does not connect to your brokerage account, and never holds or handles
your funds. Any trade you place is your own decision, entered through your own
broker, at your own risk.

Trading carries a high risk of loss. Leveraged products such as forex, CFDs and
derivatives can move against you quickly. You can lose more than your initial
deposit. Only risk money you can afford to lose entirely.

Past performance is not indicative of future results. Any win rate, pip total,
or historical record shown in this app describes what already happened. It is
not a forecast and it is not a promise. We do not guarantee profits of any kind.

No personalised advice. Signals and lessons are published to all subscribers of
a tier. They take no account of your finances, your objectives, or your risk
tolerance. Consider taking independent, licensed advice before acting.

Your responsibility. You are responsible for complying with the laws and
regulations that apply where you live, including any restrictions on leveraged
trading.

By continuing you confirm that you have read and understood this notice, that
you are of legal age in your jurisdiction, and that you accept full
responsibility for your own trading decisions.
`.trim();
