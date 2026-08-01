/* RTL Picker — script detection.
 * Decides whether a chunk of text should read right-to-left.
 *
 * The browser's own `dir="auto"` uses the *first* strong character, which gets
 * it wrong constantly in AI chats ("Here is the answer: مرحبا ..." stays LTR).
 * We count strong characters on both sides instead and use a ratio.
 */
(() => {
  const NS = (window.__RTLP = window.__RTLP || {});
  if (NS.detect) return;

  // U+0590–U+08FF is a contiguous run of RTL scripts: Hebrew, Arabic, Syriac,
  // Thaana, N'Ko, Samaritan, Mandaic, Arabic Extended-A/B.
  // The FB/FD/FE blocks are the Hebrew and Arabic presentation forms.
  const RTL_RANGES = '\\u0590-\\u08FF\\uFB1D-\\uFDFF\\uFE70-\\uFEFF';

  // Strong LTR: Latin (+ extensions), Greek, Cyrillic, CJK, Hangul, Kana.
  const LTR_RANGES =
    'A-Za-z\\u00C0-\\u02AF\\u0370-\\u04FF\\u1E00-\\u1FFF\\u2C60-\\u2C7F' +
    '\\u3040-\\u30FF\\u3400-\\u4DBF\\u4E00-\\u9FFF\\uAC00-\\uD7AF';

  const HAS_RTL = new RegExp('[' + RTL_RANGES + ']');
  const RTL_G = new RegExp('[' + RTL_RANGES + ']', 'g');
  const LTR_G = new RegExp('[' + LTR_RANGES + ']', 'g');

  /** Cheap pre-filter: is there any RTL character at all? */
  function hasRTL(text) {
    return !!text && HAS_RTL.test(text);
  }

  function count(text, re) {
    re.lastIndex = 0;
    const m = text.match(re);
    return m ? m.length : 0;
  }

  /**
   * @returns {{rtl:number, ltr:number, ratio:number}} ratio is rtl/(rtl+ltr),
   *          or 0 when the text has no strong characters at all.
   */
  function measure(text) {
    if (!text) return { rtl: 0, ltr: 0, ratio: 0 };
    // Long nodes don't need full counting to reach a verdict.
    const sample = text.length > 4000 ? text.slice(0, 4000) : text;
    const rtl = count(sample, RTL_G);
    const ltr = count(sample, LTR_G);
    const total = rtl + ltr;
    return { rtl, ltr, ratio: total ? rtl / total : 0 };
  }

  /**
   * @param {string} text
   * @param {number} threshold share of strong chars that must be RTL (0..1)
   * @returns {'rtl'|'ltr'|null} null when there is nothing to judge by.
   */
  function directionOf(text, threshold) {
    const { rtl, ltr, ratio } = measure(text);
    if (!rtl && !ltr) return null;
    if (!rtl) return 'ltr';
    const t = typeof threshold === 'number' ? threshold : 0.25;
    return ratio >= t ? 'rtl' : 'ltr';
  }

  NS.detect = { hasRTL, measure, directionOf, HAS_RTL };
})();
