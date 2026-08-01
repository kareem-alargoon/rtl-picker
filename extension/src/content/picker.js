/* RTL Picker — click-to-pick mode.
 * Hover to highlight, click to flip. Arrow keys widen/narrow the selection so
 * you can grab the message container rather than the one <span> you're over.
 */
(() => {
  const NS = (window.__RTLP = window.__RTLP || {});
  if (NS.picker) return;

  let active = false;
  let current = null;
  let exact = false;
  let point = { x: 0, y: 0 };
  let onPick = null;
  let highlight = null;
  let hud = null;

  function ui(id, tag) {
    const el = document.createElement(tag || 'div');
    el.id = id;
    el.setAttribute('data-rtlp-ui', '1');
    (document.body || document.documentElement).appendChild(el);
    return el;
  }

  function ensureUI() {
    if (!highlight || !highlight.isConnected) highlight = ui('rtlp-highlight');
    if (!hud || !hud.isConnected) hud = ui('rtlp-hud');
  }

  function isOurs(el) {
    return !!el && (el.hasAttribute?.('data-rtlp-ui') || el.closest?.('[data-rtlp-ui]'));
  }

  function describe(el) {
    if (!el) return '';
    const text = (el.textContent || '').trim().replace(/\s+/g, ' ');
    return text.length > 90 ? text.slice(0, 90) + '…' : text;
  }

  function render() {
    ensureUI();
    if (!current) {
      highlight.style.display = 'none';
      return;
    }
    const r = current.getBoundingClientRect();
    highlight.style.display = 'block';
    highlight.style.top = r.top + 'px';
    highlight.style.left = r.left + 'px';
    highlight.style.width = r.width + 'px';
    highlight.style.height = r.height + 'px';

    const { selector, count } = NS.selector.generate(current, { exact });
    hud.style.display = 'block';
    hud.innerHTML = '';

    const head = document.createElement('div');
    head.textContent = `<${current.tagName.toLowerCase()}> — ${describe(current) || 'no text'}`;
    hud.appendChild(head);

    const sel = document.createElement('code');
    sel.className = 'rtlp-sel';
    sel.textContent = selector;
    hud.appendChild(sel);

    const cnt = document.createElement('div');
    cnt.className = 'rtlp-count';
    cnt.textContent =
      count === 1
        ? 'matches this element only'
        : `matches ${count} elements — the rule applies to all of them`;
    hud.appendChild(cnt);

    const keys = document.createElement('div');
    keys.className = 'rtlp-keys';
    keys.innerHTML =
      '<kbd>Click</kbd> force RTL &nbsp; <kbd>Shift</kbd>+click force LTR &nbsp; ' +
      '<kbd>Alt</kbd>+click this element only &nbsp; <kbd>↑</kbd>/<kbd>↓</kbd> parent/child &nbsp; ' +
      '<kbd>Esc</kbd> exit' +
      (exact ? '<br><b>exact mode</b> (Alt held)' : '');
    hud.appendChild(keys);
  }

  function setCurrent(el) {
    if (el === current) return;
    current = el;
    render();
  }

  function onMove(e) {
    point = { x: e.clientX, y: e.clientY };
    exact = e.altKey;
    const el = document.elementFromPoint(e.clientX, e.clientY);
    if (!el || isOurs(el)) return;
    setCurrent(el);
  }

  function onKey(e) {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      stop();
      return;
    }
    if (e.key === 'ArrowUp' && current && current.parentElement) {
      e.preventDefault();
      e.stopPropagation();
      const parent = current.parentElement;
      if (parent !== document.documentElement) setCurrent(parent);
      return;
    }
    if (e.key === 'ArrowDown' && current) {
      e.preventDefault();
      e.stopPropagation();
      // Descend towards whatever is under the cursor.
      const deep = document.elementFromPoint(point.x, point.y);
      let node = deep;
      while (node && node.parentElement && node.parentElement !== current) node = node.parentElement;
      if (node && node !== current && current.contains(node)) setCurrent(node);
      return;
    }
    if (e.key === 'Alt' || e.altKey) {
      exact = true;
      render();
    }
  }

  function onKeyUp(e) {
    if (e.key === 'Alt') {
      exact = false;
      render();
    }
  }

  function swallow(e) {
    if (isOurs(e.target)) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.stopImmediatePropagation) e.stopImmediatePropagation();
  }

  function onClick(e) {
    if (isOurs(e.target)) return;
    swallow(e);
    if (!current) return;
    const dir = e.shiftKey ? 'ltr' : 'rtl';
    const { selector, count } = NS.selector.generate(current, { exact: e.altKey });
    const picked = { selector, dir, exact: !!e.altKey, count, element: current };
    stop();
    if (onPick) onPick(picked);
  }

  const reposition = () => {
    if (active) render();
  };

  function start(callback) {
    if (active) {
      stop();
      return;
    }
    onPick = callback;
    active = true;
    current = null;
    document.documentElement.classList.add('rtlp-picking');
    ensureUI();
    render();

    window.addEventListener('mousemove', onMove, true);
    window.addEventListener('click', onClick, true);
    window.addEventListener('mousedown', swallow, true);
    window.addEventListener('mouseup', swallow, true);
    window.addEventListener('pointerdown', swallow, true);
    window.addEventListener('contextmenu', swallow, true);
    window.addEventListener('keydown', onKey, true);
    window.addEventListener('keyup', onKeyUp, true);
    window.addEventListener('scroll', reposition, true);
    window.addEventListener('resize', reposition, true);
  }

  function stop() {
    if (!active) return;
    active = false;
    current = null;
    document.documentElement.classList.remove('rtlp-picking');
    if (highlight) highlight.style.display = 'none';
    if (hud) hud.style.display = 'none';

    window.removeEventListener('mousemove', onMove, true);
    window.removeEventListener('click', onClick, true);
    window.removeEventListener('mousedown', swallow, true);
    window.removeEventListener('mouseup', swallow, true);
    window.removeEventListener('pointerdown', swallow, true);
    window.removeEventListener('contextmenu', swallow, true);
    window.removeEventListener('keydown', onKey, true);
    window.removeEventListener('keyup', onKeyUp, true);
    window.removeEventListener('scroll', reposition, true);
    window.removeEventListener('resize', reposition, true);
  }

  NS.picker = {
    start,
    stop,
    get active() {
      return active;
    },
  };
})();
