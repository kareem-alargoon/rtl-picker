/* RTL Picker — CSS selector generation for picked elements.
 *
 * Goal is *generalisation*, not uniqueness: when you pick one chat bubble you
 * almost always want every bubble. So at each level we choose the most
 * meaningful discriminator available and stop as soon as the selector matches
 * the element, without pinning it down with :nth-child. Holding Alt while
 * picking asks for the opposite (exact = this one element only).
 */
(() => {
  const NS = (window.__RTLP = window.__RTLP || {});
  if (NS.selector) return;

  const MAX_DEPTH = 5;

  // Values that look machine-generated: hashes, uuids, long digit runs.
  const RANDOMISH = /([0-9a-f]{7,}|[0-9a-f]{8}-[0-9a-f]{4}|\d{4,})/i;
  // Class prefixes emitted by CSS-in-JS tooling — never stable across builds.
  const GENERATED_CLASS = /^(css|sc|jsx|emotion|svelte|styles?)[-_]/i;

  const esc = (s) =>
    window.CSS && CSS.escape ? CSS.escape(s) : String(s).replace(/[^\w-]/g, '\\$&');

  function looksRandom(v) {
    return !v || v.length > 60 || RANDOMISH.test(v);
  }

  function isStableId(id) {
    return !!id && !looksRandom(id) && !/^\d/.test(id);
  }

  function usableClasses(el) {
    return Array.from(el.classList).filter(
      (c) => c.length > 1 && c.length < 40 && !GENERATED_CLASS.test(c) && !looksRandom(c)
    );
  }

  /**
   * Pick the class that appears on the fewest elements in the document. On a
   * Tailwind-heavy page this naturally prefers `message-bubble` (10 hits) over
   * `flex` (900 hits), without needing a blocklist.
   */
  function bestClass(el) {
    const classes = usableClasses(el);
    if (!classes.length) return null;
    let best = null;
    let bestCount = Infinity;
    for (const c of classes) {
      let n;
      try {
        n = document.getElementsByClassName(c).length;
      } catch {
        continue;
      }
      if (n && (n < bestCount || (n === bestCount && c.length > best.length))) {
        best = c;
        bestCount = n;
      }
    }
    return best;
  }

  // Attributes worth keying off, in order of preference.
  const ATTR_HINTS = [
    'data-testid',
    'data-test-id',
    'data-message-author-role',
    'data-author',
    'data-role',
    'itemprop',
    'role',
  ];

  function attrToken(el) {
    for (const name of ATTR_HINTS) {
      const v = el.getAttribute(name);
      if (v && !looksRandom(v) && v.length < 40) return `[${name}="${v.replace(/"/g, '\\"')}"]`;
    }
    return null;
  }

  function nthOfParent(el) {
    const parent = el.parentElement;
    if (!parent) return 1;
    return Array.prototype.indexOf.call(parent.children, el) + 1;
  }

  function token(el, exact) {
    const tag = el.tagName.toLowerCase();
    if (tag === 'body' || tag === 'html') return tag;

    const attr = attrToken(el);
    if (attr) return tag + attr;
    if (isStableId(el.id)) return `${tag}#${esc(el.id)}`;
    const cls = bestClass(el);
    if (cls) return `${tag}.${esc(cls)}`;
    if (exact) return `${tag}:nth-child(${nthOfParent(el)})`;
    return tag;
  }

  function matchesTarget(sel, el) {
    try {
      const found = document.querySelectorAll(sel);
      return { hit: Array.prototype.includes.call(found, el), count: found.length };
    } catch {
      return { hit: false, count: 0 };
    }
  }

  /** Last resort: a rigid nth-child path from <body>. Always unique. */
  function exactPath(el) {
    const parts = [];
    let cur = el;
    while (cur && cur.nodeType === 1 && cur !== document.body && parts.length < 12) {
      parts.unshift(`${cur.tagName.toLowerCase()}:nth-child(${nthOfParent(cur)})`);
      cur = cur.parentElement;
    }
    return 'body > ' + parts.join(' > ');
  }

  /**
   * @param {Element} el
   * @param {{exact?:boolean}} [opts] exact = match only this element
   * @returns {{selector:string, count:number}}
   */
  function generate(el, opts) {
    const exact = !!(opts && opts.exact);
    const parts = [];
    let cur = el;

    for (let depth = 0; cur && cur.nodeType === 1 && depth < MAX_DEPTH; depth++) {
      parts.unshift(token(cur, exact));
      const sel = parts.join(' > ');
      const { hit, count } = matchesTarget(sel, el);

      // A bare tag name as the leftmost part isn't a real anchor — keep walking.
      const anchored = /[.#[\]]|nth-child/.test(parts[0]);
      if (hit && anchored && (!exact || count === 1)) return { selector: sel, count };
      if (cur.parentElement === null || cur === document.body) break;
      cur = cur.parentElement;
    }

    const joined = parts.join(' > ');
    const fallback = matchesTarget(joined, el);
    if (fallback.hit && (!exact || fallback.count === 1)) {
      return { selector: joined, count: fallback.count };
    }
    const path = exactPath(el);
    return { selector: path, count: matchesTarget(path, el).count };
  }

  function countMatches(sel) {
    try {
      return document.querySelectorAll(sel).length;
    } catch {
      return -1; // invalid selector
    }
  }

  NS.selector = { generate, countMatches };
})();
