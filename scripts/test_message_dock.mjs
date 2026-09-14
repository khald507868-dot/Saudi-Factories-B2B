// Offline regression checks for the factory page's conversation list and badge.
// Run: node scripts/test_message_dock.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../web-factory.html', import.meta.url), 'utf8');
const start = html.indexOf('      /* ===== لوحة المراسلات =====');
const end = html.indexOf('      /* ===== المنشورات =====', start);
assert(start > 0 && end > start);

function element(tag = 'div') {
  const classes = new Set();
  return {
    tag, children: [], textContent: '', style: {}, attributes: {}, events: {},
    classList: {
      contains: key => classes.has(key),
      remove: key => classes.delete(key),
      toggle(key, value = !classes.has(key)) {
        if (value) classes.add(key); else classes.delete(key);
        return value;
      },
    },
    set innerHTML(value) { assert.equal(value, ''); this.children = []; },
    appendChild(child) { this.children.push(child); },
    setAttribute(key, value) { this.attributes[key] = value; },
    addEventListener(key, fn) { this.events[key] = fn; },
  };
}
const ids = ['msg-dock', 'msg-dock-head', 'msg-dock-list', 'msg-dock-empty', 'msg-dock-count', 'msg-dock-avatar'];
const nodes = Object.fromEntries(ids.map(id => [id, element()]));
const windowEvents = {}, documentEvents = {}, timers = new Map();
let timerId = 0, change, fail = false, removed = false, loader = null;
let threads = {
  1: { name: 'First contact', updated: 10, unread: 3, messages: [], lastMessage: { text: 'Latest message' } },
  2: { name: 'Second contact', updated: 20, unread: 4, messages: [], lastMessage: { type: 'image' } },
  3: { name: 'Read contact', updated: 5, unread: 0, messages: [] },
};
const context = vm.createContext({
  document: {
    hidden: false, getElementById: id => nodes[id], createElement: element,
    addEventListener: (key, fn) => { documentEvents[key] = fn; },
  },
  I18N: { t: key => ({ msg_panel_title: 'Messaging', msg_photo: 'Photo', msg_video: 'Video' })[key] },
  SF_AUTH_READY: Promise.resolve(), SF_USER: { id: 'signed-in-user' },
  SFMessages: {
    load: () => loader ? loader() : fail ? Promise.reject(new Error('offline')) : Promise.resolve(threads),
    subscribe(fn) { change = fn; return 'channel'; },
    markRead() { assert.fail('Opening the list must not mark chats as read'); },
  },
  sb: { removeChannel(channel) { assert.equal(channel, 'channel'); removed = true; } },
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; },
  clearTimeout(id) { timers.delete(id); },
  addEventListener(key, fn) { windowEvents[key] = fn; },
  console: { warn() {} },
});
context.window = context;
vm.runInContext(html.slice(start, end), context);
const settle = () => new Promise(resolve => setImmediate(resolve));
async function flush() {
  const tasks = [...timers.values()]; timers.clear();
  await Promise.all(tasks.map(fn => fn())); await settle();
}
const badge = nodes['msg-dock-count'], list = nodes['msg-dock-list'];
await settle();
assert.equal(list.children.length, 3, 'read and unread contacts remain visible');
assert.equal(badge.textContent, '7', 'count messages, not contacts or unread threads');
assert(badge.classList.contains('is-on'));
assert.deepEqual(list.children.map(row => row.href), [
  'web-messages.html?open=2', 'web-messages.html?open=1', 'web-messages.html?open=3',
]);
assert.equal(list.children[0].children[1].children[1].textContent, 'Photo');
assert.equal(list.children[1].children[1].children[1].textContent, 'Latest message');
nodes['msg-dock-head'].events.click(); await settle();
assert.equal(nodes['msg-dock-head'].attributes['aria-expanded'], 'true');
assert.equal(badge.textContent, '7');

threads[1].unread = 0; threads[2].unread = 0;
change(); await flush();
assert.equal(badge.textContent, '');
assert(!badge.classList.contains('is-on'));
assert.equal(list.children.length, 3, 'reading all messages does not remove contacts');

threads[2].unread = 5;
windowEvents.focus(); await flush();
assert.equal(badge.textContent, '5');
threads[2].unread = 2;
documentEvents.visibilitychange(); await flush();
assert.equal(badge.textContent, '2');
threads[2].unread = 1;
windowEvents.pageshow(); await flush();
assert.equal(badge.textContent, '1');

fail = true; change(); await flush();
assert.equal(badge.textContent, '');
assert.equal(list.children.length, 3, 'network failure retains contact list');
fail = false; change(); await flush();
assert.equal(badge.textContent, '1');

const deferred = [];
loader = () => new Promise(resolve => deferred.push(resolve));
const stale = context.refreshDock(), current = context.refreshDock();
deferred[1](threads); await current;
deferred[0]({ 9: { name: 'Stale result', unread: 99 } }); await stale;
assert.equal(badge.textContent, '1', 'out-of-order responses do not restore stale counts');
loader = null;
threads = {}; await context.refreshDock();
assert.equal(list.children.length, 0);
assert.equal(nodes['msg-dock-empty'].style.display, '');
assert(!badge.classList.contains('is-on'));
windowEvents.beforeunload(); assert(removed);
console.log('PASS unread message sum, all contacts retained, previews, chat links, zero count, realtime/read refresh, return-to-page refresh, failure recovery, stale-response protection, and cleanup');
