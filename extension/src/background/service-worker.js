/* RTL Picker — service worker.
 * Owns the keyboard commands and the toolbar badge. All real work happens in
 * the content script; this just routes intent to the active tab.
 */
importScripts('/src/core/settings.js');

const store = self.__RTLP.settings;

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab || null;
}

function send(tabId, message) {
  // A tab without our content script (chrome://, the Web Store) will reject —
  // that's expected, not an error worth surfacing.
  chrome.tabs.sendMessage(tabId, message).catch(() => {});
}

async function paintBadge(tab) {
  if (!tab || !tab.id) return;
  const settings = await store.get();
  const origin = store.originOf(tab.url || '');
  const on = origin && store.siteEnabled(settings, origin);
  try {
    await chrome.action.setBadgeText({ tabId: tab.id, text: on ? '' : 'off' });
    await chrome.action.setBadgeBackgroundColor({ tabId: tab.id, color: '#6b7280' });
  } catch {
    /* tab closed mid-flight */
  }
}

chrome.commands.onCommand.addListener(async (command) => {
  const tab = await activeTab();
  if (!tab || !tab.id) return;

  if (command === 'start-picker') {
    send(tab.id, { type: 'rtlp:pick' });
    return;
  }

  if (command === 'toggle-site') {
    const origin = store.originOf(tab.url || '');
    if (!origin) return;
    const settings = await store.get();
    await store.setSiteEnabled(origin, !store.siteEnabled(settings, origin));
    paintBadge(tab);
  }
});

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    paintBadge(await chrome.tabs.get(tabId));
  } catch {
    /* gone */
  }
});

chrome.tabs.onUpdated.addListener((_tabId, info, tab) => {
  if (info.status === 'complete' || info.url) paintBadge(tab);
});

chrome.storage.onChanged.addListener(async (changes, area) => {
  if (area !== 'local' || !changes[store.KEY]) return;
  paintBadge(await activeTab());
});

chrome.runtime.onInstalled.addListener(async () => {
  // Materialise defaults so the popup has something concrete to read.
  await store.save(await store.get());
});
