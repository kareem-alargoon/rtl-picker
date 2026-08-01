/* RTL Picker — popup. */
(() => {
  const store = self.__RTLP.settings;

  const $ = (id) => document.getElementById(id);
  const el = {
    site: $('site'),
    status: $('status'),
    siteEnabled: $('site-enabled'),
    enabled: $('enabled'),
    auto: $('auto'),
    fields: $('fields'),
    skipCode: $('skipCode'),
    threshold: $('threshold'),
    thresholdLabel: $('threshold-label'),
    pick: $('pick'),
    ruleList: $('rule-list'),
    ruleCount: $('rule-count'),
    rulesEmpty: $('rules-empty'),
    clearRules: $('clear-rules'),
  };

  let tab = null;
  let origin = null;
  let settings = store.DEFAULTS;

  function ask(message) {
    return new Promise((resolve) => {
      if (!tab || !tab.id) return resolve(null);
      chrome.tabs.sendMessage(tab.id, message, (response) => {
        void chrome.runtime.lastError; // no content script here — fine
        resolve(response ?? null);
      });
    });
  }

  function setStatus(text) {
    el.status.textContent = text;
  }

  async function renderRules() {
    const rules = store.rulesFor(settings, origin);
    el.ruleCount.textContent = String(rules.length);
    el.clearRules.hidden = rules.length === 0;
    el.rulesEmpty.hidden = rules.length > 0;
    el.ruleList.textContent = '';
    if (!rules.length) return;

    const counts = (await ask({ type: 'rtlp:counts', selectors: rules.map((r) => r.selector) })) || [];

    rules.forEach((rule, i) => {
      const li = document.createElement('li');

      const dir = document.createElement('button');
      dir.className = 'dir';
      dir.dataset.dir = rule.dir;
      dir.textContent = rule.dir.toUpperCase();
      dir.title = 'Switch this rule between RTL and LTR';
      dir.addEventListener('click', async () => {
        await store.addRule(origin, {
          selector: rule.selector,
          dir: rule.dir === 'rtl' ? 'ltr' : 'rtl',
          exact: rule.exact,
        });
        settings = await store.get();
        await ask({ type: 'rtlp:rescan' });
        renderRules();
      });

      const sel = document.createElement('span');
      sel.className = 'sel';
      sel.textContent = rule.selector;
      sel.title = rule.selector;

      const count = document.createElement('span');
      count.className = 'count';
      const n = counts[i];
      count.textContent = n === undefined || n === null ? '' : n < 0 ? 'invalid' : `${n}×`;

      const remove = document.createElement('button');
      remove.className = 'remove';
      remove.textContent = '×';
      remove.title = 'Delete this rule';
      remove.addEventListener('click', async () => {
        await store.removeRule(origin, rule.selector);
        settings = await store.get();
        await ask({ type: 'rtlp:rescan' });
        renderRules();
      });

      li.append(dir, sel, count, remove);
      el.ruleList.appendChild(li);
    });
  }

  function renderSettings() {
    el.enabled.checked = settings.enabled;
    el.auto.checked = settings.auto;
    el.fields.checked = settings.fields;
    el.skipCode.checked = settings.skipCode;
    el.threshold.value = String(Math.round(settings.threshold * 100));
    el.thresholdLabel.textContent = `Flip at ${Math.round(settings.threshold * 100)}% RTL characters`;
    el.siteEnabled.checked = !!origin && store.siteEnabled(settings, origin);
    el.siteEnabled.disabled = !origin || !settings.enabled;
    el.pick.disabled = !origin || !store.siteEnabled(settings, origin);
  }

  async function refreshStatus() {
    if (!origin) {
      setStatus('This page cannot be modified by extensions.');
      return;
    }
    if (!store.siteEnabled(settings, origin)) {
      setStatus(settings.enabled ? 'Turned off for this site.' : 'Extension is off everywhere.');
      return;
    }
    const status = await ask({ type: 'rtlp:status' });
    if (!status) {
      setStatus('Reload the page to activate RTL Picker here.');
      return;
    }
    setStatus(
      status.flipped
        ? `${status.flipped} block${status.flipped === 1 ? '' : 's'} flipped on this page.`
        : 'Running — no RTL text found yet.'
    );
  }

  async function update(changes) {
    settings = await store.patch(changes);
    renderSettings();
    refreshStatus();
  }

  el.enabled.addEventListener('change', () => update({ enabled: el.enabled.checked }));
  el.auto.addEventListener('change', () => update({ auto: el.auto.checked }));
  el.fields.addEventListener('change', () => update({ fields: el.fields.checked }));
  el.skipCode.addEventListener('change', () => update({ skipCode: el.skipCode.checked }));

  el.threshold.addEventListener('input', () => {
    const pct = Number(el.threshold.value);
    el.thresholdLabel.textContent = `Flip at ${pct}% RTL characters`;
  });
  el.threshold.addEventListener('change', () => update({ threshold: Number(el.threshold.value) / 100 }));

  el.siteEnabled.addEventListener('change', async () => {
    if (!origin) return;
    await store.setSiteEnabled(origin, el.siteEnabled.checked);
    settings = await store.get();
    renderSettings();
    refreshStatus();
  });

  el.clearRules.addEventListener('click', async () => {
    if (!origin) return;
    await store.clearRules(origin);
    settings = await store.get();
    await ask({ type: 'rtlp:rescan' });
    renderRules();
  });

  el.pick.addEventListener('click', async () => {
    await ask({ type: 'rtlp:pick' });
    window.close(); // the picker needs the page, not this popup
  });

  (async function init() {
    [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    origin = tab ? store.originOf(tab.url || '') : null;
    settings = await store.get();
    el.site.textContent = origin ? origin.replace(/^https?:\/\//, '') : 'unsupported page';
    el.site.title = origin || '';
    renderSettings();
    await renderRules();
    refreshStatus();
  })();
})();
