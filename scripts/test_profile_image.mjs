// Exercise the actual profile image handler, including server persistence and reload.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const page = readFileSync(new URL('../web-profile.html', import.meta.url), 'utf8');
const initialization = page.match(/var companyImageData = .*;/)[0];
const handler = page.slice(page.indexOf('      var imageTrigger ='), page.indexOf('      var editableFields ='));
const flush = () => new Promise(resolve => setImmediate(resolve));
const oldUrl = 'https://storage.example/old.jpg';
const newUrl = 'https://storage.example/user/profile/new.jpg';
const database = { company_image: oldUrl };

function setup(options = {}) {
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {
      style: {}, listeners: {}, attributes: {}, files: [{}], textContent: '', value: '',
      classList: { add() {} },
      addEventListener(name, fn) { this.listeners[name] = fn; },
      setAttribute(name, value) { this.attributes[name] = value; },
      removeAttribute(name) { delete this[name]; },
      replaceChildren(...children) { this.children = children; },
      click() { this.clicked = true; }
    });
    return nodes.get(id);
  };
  let cache = JSON.stringify({ companyImage: oldUrl, name: 'Saved name' });
  const calls = [];
  const serverProfile = { ...database };
  const context = vm.createContext({
    Promise, console, serverProfile, savedAccount: JSON.parse(cache),
    imageUploadPending: false, profileSavePending: false,
    checkFilled() {},
    sfSafeHttpUrl(url) { return /^https?:\/\//.test(url || '') ? url : ''; },
    I18N: { t: key => key },
    SF_USER: { id: 'user-id' }, SF_PROFILE: serverProfile,
    document: {
      getElementById: node,
      createElement(tag) {
        if (tag === 'canvas') return { getContext: () => ({ drawImage() {} }), toDataURL: () => 'data:image/jpeg;base64,abc' };
        return { tag };
      }
    },
    localStorage: {
      getItem() { if (options.cacheError) throw Error('Storage unavailable'); return cache; },
      setItem(key, value) { cache = value; }
    },
    FileReader: class {
      readAsDataURL() {
        if (options.readError) this.onerror(Error('Read failed'));
        else this.onload({ target: { result: 'data:image/png;base64,abc' } });
      }
    },
    Image: class {
      width = 800; height = 600;
      set src(value) {
        if (options.decodeError) this.onerror(Error('Decode failed'));
        else this.onload();
      }
    },
    SFUpload: {
      async uploadDataUrl(data, bucket, folder, kind) {
        calls.push({ upload: { data, bucket, folder, kind } });
        if (options.uploadError) throw Error('Upload failed');
        if (options.waitUpload) await options.waitUpload;
        return { url: newUrl };
      }
    },
    sb: {
      from(table) {
        assert.equal(table, 'profiles');
        return { update(patch) {
          assert.deepEqual(Object.keys(patch), ['company_image'], 'Do not submit other pending fields');
          calls.push({ patch });
          return { eq(key, id) {
            assert.equal(key, 'id'); assert.equal(id, 'user-id');
            return { select(columns) {
              assert.equal(columns, 'company_image');
              return { async single() {
                if (options.waitSave) await options.waitSave;
                if (options.saveError) return { error: Error('Save rejected') };
                if (options.noRow) return { data: null };
                Object.assign(database, patch);
                return { data: { ...database } };
              } };
            } };
          } };
        } };
      }
    },
    addEventListener(name, fn) { node('window').listeners[name] = fn; }
  });
  context.window = context;
  vm.runInContext(initialization + '\n' + handler, context);
  return {
    context, node, calls, cache: () => JSON.parse(cache),
    choose() { node('f-company-image').listeners.change(); }
  };
}

let releaseSave;
const app = setup({ waitSave: new Promise(resolve => { releaseSave = resolve; }) });
app.choose();
assert.equal(app.context.imageUploadPending, true);
assert.equal(app.node('image-upload-trigger').disabled, true);
await flush();
assert.equal(app.node('image-save-status').textContent, 'msg_uploading');
assert.equal(app.context.companyImageData, oldUrl, 'Preview is not a saved URL');
assert.equal(app.cache().companyImage, oldUrl);
app.choose();
assert.equal(app.calls.filter(call => call.upload).length, 1, 'Prevent overlapping saves');
let prevented = false;
app.node('window').listeners.beforeunload({ preventDefault() { prevented = true; } });
assert.equal(prevented, true);
releaseSave(); await flush();
assert.equal(database.company_image, newUrl);
assert.equal(app.cache().companyImage, newUrl);
assert.equal(app.cache().name, 'Saved name');
assert.equal(app.context.SF_PROFILE.company_image, newUrl);
assert.equal(app.node('dash-avatar').children[0].src, newUrl);
assert.equal(app.node('image-save-status').textContent, 'admin_cat_saved');
assert.equal(app.context.imageUploadPending, false);
assert.equal(app.node('f-company-image').value, '');
assert.equal(setup().node('image-preview').src, newUrl, 'Reload displays server image, despite stale local cache');

for (const failure of ['uploadError', 'saveError', 'noRow', 'readError', 'decodeError']) {
  database.company_image = oldUrl;
  const test = setup({ [failure]: true });
  test.choose(); await flush();
  assert.equal(database.company_image, oldUrl, failure);
  assert.equal(test.node('image-preview').src, oldUrl, failure);
  assert.equal(test.cache().companyImage, oldUrl, failure);
  assert.equal(test.node('image-save-status').attributes['data-error'], 'true', failure);
  assert.equal(test.context.imageUploadPending, false, failure);
  assert.equal(test.node('image-upload-trigger').disabled, false, failure);
}
database.company_image = '';
const firstFailure = setup({ saveError: true });
// Remove the legacy fallback too, as on a new account.
firstFailure.context.companyImageData = '';
firstFailure.choose(); await flush();
assert.equal(firstFailure.node('image-preview').style.display, 'none');
assert.equal(firstFailure.node('image-upload-icon').style.display, '');

const noCache = setup({ cacheError: true });
noCache.choose(); await flush();
assert.equal(database.company_image, newUrl);
assert.equal(noCache.node('image-save-status').textContent, 'admin_cat_saved');
assert.equal(setup().node('image-preview').src, newUrl);

const busy = setup();
busy.context.profileSavePending = true;
busy.choose(); await flush();
assert.equal(busy.calls.length, 0, 'Do not race a full profile submission');
busy.node('image-delete').listeners.click(); await flush();
assert.equal(busy.calls.length, 0, 'Deletion must not race a full profile submission either');

database.company_image = oldUrl;
let releaseDelete;
const deleting = setup({ waitSave: new Promise(resolve => { releaseDelete = resolve; }) });
assert.equal(deleting.node('image-delete').hidden, false);
deleting.node('image-delete').listeners.click(); await flush();
assert.equal(deleting.node('image-delete').disabled, true);
assert.equal(deleting.node('image-save-status').textContent, 'profile_image_deleting');
assert.equal(deleting.node('image-preview').src, oldUrl, 'Keep image until server confirms deletion');
deleting.node('image-delete').listeners.click();
deleting.choose(); await flush();
assert.equal(deleting.calls.length, 1, 'Prevent duplicate deletion and concurrent upload');
releaseDelete(); await flush();
assert.equal(database.company_image, '');
assert.equal(deleting.cache().companyImage, '');
assert.equal(deleting.cache().name, 'Saved name');
assert.equal(deleting.context.companyImageData, '');
assert.equal(deleting.context.SF_PROFILE.company_image, '');
assert.equal(deleting.node('image-preview').style.display, 'none');
assert.equal(deleting.node('image-delete').hidden, true);
assert.equal(deleting.node('dash-avatar').textContent, '\u{1f464}');
assert.equal(deleting.node('image-save-status').textContent, 'profile_image_deleted');
assert.equal(deleting.node('image-upload-trigger').disabled, false);
const afterDeletion = setup(); // deliberately stale cache still contains oldUrl
assert.equal(afterDeletion.context.companyImageData, '', 'Server deletion overrides stale cached image');
assert.equal(afterDeletion.node('image-preview').style.display, 'none');
assert.equal(afterDeletion.node('image-delete').hidden, true);
afterDeletion.node('image-delete').listeners.click(); await flush();
assert.equal(afterDeletion.calls.length, 0, 'No deletion request without an image');
afterDeletion.choose(); await flush();
assert.equal(database.company_image, newUrl, 'Can upload again after deletion');
assert.equal(afterDeletion.node('image-delete').hidden, false);

for (const failure of ['saveError', 'noRow']) {
  database.company_image = oldUrl;
  const failedDelete = setup({ [failure]: true });
  failedDelete.node('image-delete').listeners.click(); await flush();
  assert.equal(database.company_image, oldUrl);
  assert.equal(failedDelete.context.companyImageData, oldUrl);
  assert.equal(failedDelete.cache().companyImage, oldUrl);
  assert.equal(failedDelete.node('image-preview').src, oldUrl);
  assert.equal(failedDelete.node('image-delete').hidden, false);
  assert.equal(failedDelete.node('image-delete').disabled, false);
  assert.equal(failedDelete.node('image-save-status').attributes['data-error'], 'true');
}
const noDeleteCache = setup({ cacheError: true });
noDeleteCache.node('image-delete').listeners.click(); await flush();
assert.equal(database.company_image, '');
assert.equal(noDeleteCache.node('image-save-status').textContent, 'profile_image_deleted');
assert.equal(setup().node('image-preview').style.display, 'none');

console.log('PASS profile image: upload/delete persistence, stale-cache reload, owner filter, unchanged drafts, concurrent-save guard, failure rollback, blocked local storage, reupload after deletion');
