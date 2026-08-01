/* RTL Picker — settings + saved rules.
 * Uses `self` so the same file works in a content script, the popup, and the
 * service worker. Everything lives in chrome.storage.local (sync's 8KB
 * per-item cap is too tight once a site has a few dozen rules).
 */
(() => {
  const NS = (self.__RTLP = self.__RTLP || {});
  if (NS.settings) return;

  const KEY = 'rtlp';

  const DEFAULTS = {
    enabled: true, // master switch
    auto: true, // auto-detect RTL text
    fields: true, // flip inputs / textareas / contenteditable as you type
    skipCode: true, // leave <pre>/<code> alone
    threshold: 0.25, // share of strong chars that must be RTL
    disabledSites: [], // origins where auto-detect is off
    rules: {}, // { origin: [{ selector, dir, exact, created }] }
  };

  function normalise(raw) {
    const s = Object.assign({}, DEFAULTS, raw || {});
    s.disabledSites = Array.isArray(s.disabledSites) ? s.disabledSites : [];
    s.rules = s.rules && typeof s.rules === 'object' ? s.rules : {};
    s.threshold = Math.min(1, Math.max(0.01, Number(s.threshold) || DEFAULTS.threshold));
    return s;
  }

  function get() {
    return new Promise((resolve) => {
      chrome.storage.local.get(KEY, (data) => resolve(normalise(data && data[KEY])));
    });
  }

  function save(settings) {
    return new Promise((resolve) => {
      chrome.storage.local.set({ [KEY]: settings }, () => resolve(settings));
    });
  }

  async function patch(changes) {
    const current = await get();
    return save(Object.assign(current, changes));
  }

  /** Storage key for a page. Origin-scoped so rules follow the site, not the URL. */
  function originOf(url) {
    try {
      const u = new URL(url);
      if (u.protocol === 'file:') return 'file://';
      return u.origin;
    } catch {
      return null;
    }
  }

  function siteEnabled(settings, origin) {
    return settings.enabled && !settings.disabledSites.includes(origin);
  }

  function rulesFor(settings, origin) {
    return (settings.rules && settings.rules[origin]) || [];
  }

  async function addRule(origin, rule) {
    const s = await get();
    const list = rulesFor(s, origin).slice();
    const existing = list.findIndex((r) => r.selector === rule.selector);
    if (existing >= 0) list[existing] = Object.assign({}, list[existing], rule);
    else list.push(Object.assign({ created: Date.now() }, rule));
    s.rules[origin] = list;
    return save(s);
  }

  async function removeRule(origin, selector) {
    const s = await get();
    s.rules[origin] = rulesFor(s, origin).filter((r) => r.selector !== selector);
    if (!s.rules[origin].length) delete s.rules[origin];
    return save(s);
  }

  async function clearRules(origin) {
    const s = await get();
    delete s.rules[origin];
    return save(s);
  }

  async function setSiteEnabled(origin, enabled) {
    const s = await get();
    const set = new Set(s.disabledSites);
    if (enabled) set.delete(origin);
    else set.add(origin);
    s.disabledSites = Array.from(set);
    return save(s);
  }

  NS.settings = {
    KEY,
    DEFAULTS,
    get,
    save,
    patch,
    originOf,
    siteEnabled,
    rulesFor,
    addRule,
    removeRule,
    clearRules,
    setSiteEnabled,
    normalise,
  };
})();
