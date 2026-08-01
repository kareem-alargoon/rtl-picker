/* RTL Picker — content script.
 *
 * Three jobs:
 *   1. Auto-detect: find blocks whose text is mostly RTL and flip them.
 *   2. Fields: flip inputs / textareas / contenteditable as you type.
 *   3. Rules: apply the selectors you saved with the picker.
 *
 * AI chats stream their answers token by token, so everything here is driven by
 * a throttled MutationObserver rather than a one-shot pass.
 */
(() => {
  const NS = (window.__RTLP = window.__RTLP || {});
  if (NS.content) return;
  NS.content = true;

  const detect = NS.detect;
  const store = NS.settings;
  const IS_TOP = window.top === window;

  let settings = store.DEFAULTS;
  let origin = store.originOf(location.href);
  let rules = [];
  let active = false; // enabled for this site
  let observer = null;

  const NEVER_FLIP = new Set(['HTML', 'BODY']);
  const SKIP_TAGS = new Set([
    'SCRIPT',
    'STYLE',
    'NOSCRIPT',
    'TEXTAREA',
    'TITLE',
    'TEMPLATE',
    'IFRAME',
    'CANVAS',
    'SVG',
    'PATH',
  ]);

  const FIELD_SEL =
    'textarea, input[type="text"], input[type="search"], input[type="email"], ' +
    'input[type="url"], input:not([type]), [contenteditable=""], [contenteditable="true"]';

  /* ---------------- block resolution ---------------- */

  const INLINEISH = /^(inline|contents|ruby)/;
  const displayCache = new WeakMap();

  function isBlockish(el) {
    let d = displayCache.get(el);
    if (d === undefined) {
      try {
        d = getComputedStyle(el).display || 'block';
      } catch {
        d = 'block';
      }
      displayCache.set(el, d);
    }
    // inline-block / inline-flex still establish their own line box, so they
    // are valid targets even though the name starts with "inline".
    return !INLINEISH.test(d) || d.startsWith('inline-');
  }

  /** Nearest ancestor that actually lays out lines — that's where dir belongs. */
  function nearestBlock(textNode) {
    let el = textNode.parentElement;
    for (let i = 0; el && i < 12; i++) {
      if (NEVER_FLIP.has(el.tagName)) return null;
      if (isBlockish(el)) return el;
      el = el.parentElement;
    }
    return el && !NEVER_FLIP.has(el.tagName) ? el : null;
  }

  /* ---------------- auto-detect ---------------- */

  function markDirection(el, dir) {
    if (dir === 'rtl' || dir === 'ltr') {
      if (el.getAttribute('data-rtlp-auto') !== dir) el.setAttribute('data-rtlp-auto', dir);
    } else if (el.hasAttribute('data-rtlp-auto')) {
      el.removeAttribute('data-rtlp-auto');
    }
  }

  function inheritsRTL(el) {
    const parent = el.parentElement;
    return !!parent && !!parent.closest('[data-rtlp-auto="rtl"], [data-rtlp="rtl"]');
  }

  /**
   * Once a container is flipped, its English children would inherit rtl too.
   * Give each direct block child an explicit direction so a mixed-language
   * message reads correctly paragraph by paragraph.
   */
  function balanceChildren(el) {
    const kids = el.children;
    if (!kids.length || kids.length > 40) return;
    for (const kid of kids) {
      if (SKIP_TAGS.has(kid.tagName)) continue;
      if (kid.hasAttribute('data-rtlp')) continue; // a manual rule owns this one
      if (!isBlockish(kid)) continue; // inline runs are the bidi algorithm's job
      markDirection(kid, detect.directionOf(kid.textContent, settings.threshold));
    }
  }

  function applyAuto(el) {
    if (!el || !el.isConnected || NEVER_FLIP.has(el.tagName)) return;
    if (el.closest('[data-rtlp-ui]')) return;
    if (el.closest('[data-rtlp="ltr"]')) return; // a manual LTR rule wins
    if (settings.skipCode && el.closest('pre, code')) return;

    const text = el.textContent;
    if (!text || text.length > 50000) return;

    const dir = detect.directionOf(text, settings.threshold);
    if (dir === 'rtl') {
      markDirection(el, 'rtl');
      balanceChildren(el);
    } else {
      // Only pin LTR where it matters — otherwise we'd litter the page with
      // attributes that change nothing.
      markDirection(el, inheritsRTL(el) ? 'ltr' : null);
    }
  }

  const textFilter = {
    acceptNode(node) {
      const v = node.nodeValue;
      if (!v || v.length < 2 || !detect.hasRTL(v)) return NodeFilter.FILTER_REJECT;
      const p = node.parentElement;
      if (!p || SKIP_TAGS.has(p.tagName)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    },
  };

  function scanRoot(root) {
    if (!settings.auto || !root || !root.isConnected) return;
    if (root.nodeType === 1 && root.closest('[data-rtlp-ui]')) return;

    const blocks = new Set();
    if (root.nodeType === 3) {
      if (detect.hasRTL(root.nodeValue)) {
        const b = nearestBlock(root);
        if (b) blocks.add(b);
      }
    } else {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, textFilter);
      let n;
      let seen = 0;
      while ((n = walker.nextNode()) && seen++ < 5000) {
        const b = nearestBlock(n);
        if (b) blocks.add(b);
      }
    }
    blocks.forEach(applyAuto);
  }

  /* ---------------- saved rules ---------------- */

  function applyRules(reconcile) {
    if (reconcile) {
      document.querySelectorAll('[data-rtlp]').forEach((el) => el.removeAttribute('data-rtlp'));
    }
    for (const rule of rules) {
      let nodes;
      try {
        nodes = document.querySelectorAll(rule.selector);
      } catch {
        continue; // selector no longer valid on this page
      }
      nodes.forEach((el) => {
        if (el.getAttribute('data-rtlp') !== rule.dir) el.setAttribute('data-rtlp', rule.dir);
      });
    }
  }

  /* ---------------- editable fields ---------------- */

  function fieldText(el) {
    if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
      return el.value || el.getAttribute('placeholder') || '';
    }
    return el.textContent || el.getAttribute('data-placeholder') || '';
  }

  function applyField(el) {
    if (!settings.fields || !el || !el.isConnected) return;
    const dir = detect.directionOf(fieldText(el), settings.threshold);
    const want = dir === 'rtl' ? 'rtl' : '';
    if (el.style.direction !== want) {
      el.style.direction = want;
      el.style.textAlign = want ? 'start' : '';
    }
    // Rich editors (ProseMirror, Lexical, Quill) keep one node per paragraph —
    // flip each one so a mixed-language draft reads correctly line by line.
    if (el.isContentEditable) balanceChildren(el);
  }

  function scanFields(root) {
    if (!settings.fields) return;
    const scope = root && root.nodeType === 1 ? root : document;
    if (scope.matches && scope.matches(FIELD_SEL)) applyField(scope);
    scope.querySelectorAll?.(FIELD_SEL).forEach(applyField);
  }

  function onFieldEvent(e) {
    if (!active || !settings.fields) return;
    const el = e.target;
    if (!el || el.nodeType !== 1 || !el.matches?.(FIELD_SEL)) return;
    applyField(el);
  }

  /* ---------------- mutation pipeline ---------------- */

  const pendingEls = new Set();
  const pendingText = new Set();
  let scheduled = false;
  let lastRun = 0;
  const MIN_INTERVAL_MS = 120;

  function flush() {
    scheduled = false;
    lastRun = Date.now();
    if (!active) {
      pendingEls.clear();
      pendingText.clear();
      return;
    }
    const els = Array.from(pendingEls);
    const texts = Array.from(pendingText);
    pendingEls.clear();
    pendingText.clear();

    for (const el of els) {
      scanRoot(el);
      scanFields(el);
    }
    for (const t of texts) {
      if (!t.isConnected) continue;
      if (!detect.hasRTL(t.nodeValue)) {
        // Text was edited down to nothing RTL — clear a stale flip.
        const b = nearestBlock(t);
        if (b) applyAuto(b);
        continue;
      }
      const b = nearestBlock(t);
      if (b) applyAuto(b);
    }
    if (rules.length) applyRules(false);
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    const wait = Math.max(0, MIN_INTERVAL_MS - (Date.now() - lastRun));
    setTimeout(flush, wait);
  }

  function onMutations(records) {
    if (!active) return;
    for (const m of records) {
      if (m.type === 'childList') {
        for (const n of m.addedNodes) {
          if (n.nodeType === 1) {
            if (n.hasAttribute?.('data-rtlp-ui')) continue;
            pendingEls.add(n);
          } else if (n.nodeType === 3) {
            pendingText.add(n);
          }
        }
      } else if (m.type === 'characterData') {
        pendingText.add(m.target);
      }
    }
    if (pendingEls.size || pendingText.size) schedule();
  }

  function startObserver() {
    if (observer) return;
    observer = new MutationObserver(onMutations);
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
    });
  }

  function stopObserver() {
    if (!observer) return;
    observer.disconnect();
    observer = null;
  }

  /* ---------------- lifecycle ---------------- */

  function clearAll() {
    document
      .querySelectorAll('[data-rtlp-auto]')
      .forEach((el) => el.removeAttribute('data-rtlp-auto'));
    document.querySelectorAll('[data-rtlp]').forEach((el) => el.removeAttribute('data-rtlp'));
    document.querySelectorAll(FIELD_SEL).forEach((el) => {
      if (el.style.direction === 'rtl') {
        el.style.direction = '';
        el.style.textAlign = '';
      }
    });
  }

  function fullPass() {
    if (!document.body) return;
    applyRules(true);
    scanRoot(document.body);
    scanFields(document.body);
  }

  function activate() {
    if (active) return;
    active = true;
    startObserver();
    fullPass();
  }

  function deactivate() {
    if (!active) return;
    active = false;
    stopObserver();
    NS.picker.stop();
    clearAll();
  }

  function reconcile() {
    const shouldRun = store.siteEnabled(settings, origin);
    if (shouldRun) {
      if (active) {
        clearAll();
        fullPass();
      } else {
        activate();
      }
    } else {
      deactivate();
    }
  }

  /* ---------------- picker glue ---------------- */

  let toastEl = null;
  let toastTimer = 0;

  function toast(message) {
    if (!document.body) return;
    if (!toastEl || !toastEl.isConnected) {
      toastEl = document.createElement('div');
      toastEl.id = 'rtlp-toast';
      toastEl.setAttribute('data-rtlp-ui', '1');
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = message;
    toastEl.classList.add('rtlp-show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl && toastEl.classList.remove('rtlp-show'), 2500);
  }

  async function handlePick(picked) {
    if (!origin) return;
    try {
      await store.addRule(origin, {
        selector: picked.selector,
        dir: picked.dir,
        exact: picked.exact,
      });
      toast(
        `${picked.dir.toUpperCase()} rule saved — ${picked.count} element${
          picked.count === 1 ? '' : 's'
        }`
      );
    } catch {
      toast('Could not save the rule (extension was reloaded?)');
    }
  }

  function startPicker() {
    if (!IS_TOP) return; // one HUD per tab, not one per iframe
    NS.picker.start(handlePick);
  }

  /* ---------------- wiring ---------------- */

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (!msg || !msg.type) return;
    switch (msg.type) {
      case 'rtlp:pick':
        startPicker();
        break;
      case 'rtlp:stop-pick':
        NS.picker.stop();
        break;
      case 'rtlp:rescan':
        if (active) {
          clearAll();
          fullPass();
        }
        break;
      case 'rtlp:counts':
        sendResponse((msg.selectors || []).map((s) => NS.selector.countMatches(s)));
        return true;
      case 'rtlp:status':
        sendResponse({
          origin,
          active,
          flipped: document.querySelectorAll('[data-rtlp-auto="rtl"], [data-rtlp]').length,
          picking: NS.picker.active,
        });
        return true;
    }
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !changes[store.KEY]) return;
    settings = store.normalise(changes[store.KEY].newValue);
    rules = store.rulesFor(settings, origin);
    reconcile();
  });

  document.addEventListener('input', onFieldEvent, true);
  document.addEventListener('focusin', onFieldEvent, true);

  async function init() {
    try {
      settings = await store.get();
    } catch {
      return; // extension context gone
    }
    rules = store.rulesFor(settings, origin);
    if (!store.siteEnabled(settings, origin)) return;

    if (document.body) activate();
    else document.addEventListener('DOMContentLoaded', activate, { once: true });
    // Late-hydrating SPAs sometimes replace the whole tree after load.
    window.addEventListener('load', () => active && fullPass(), { once: true });
  }

  init();
})();
