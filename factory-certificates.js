/* Public image gallery; ownership comes from the server's factory row. */
(function (root) {
  'use strict';
  var section, view, add, input, message, retry, viewer, factory, owner = false, working = false;
  var rows = [], version = 0;
  function t(key) { return root.I18N.t('cert_' + key); }
  function state(text, error) {
    message.textContent = text || ''; message.hidden = !text;
    message.classList.toggle('is-error', !!error);
  }
  function imageUrl(path) { return root.sb.storage.from('factory-certificates').getPublicUrl(path).data.publicUrl; }
  function render() {
    if (view.sfStopScroll) view.sfStopScroll();
    view.innerHTML = '';
    section.hidden = !owner && !rows.length;
    rows.forEach(function (row, index) {
      var cell = document.createElement('div'); cell.className = 'certificate-item';
      var open = document.createElement('button'); open.type = 'button'; open.className = 'certificate-open';
      open.setAttribute('data-certificate', row.id); open.setAttribute('aria-label', t('view') + ' ' + (index+1));
      var img = document.createElement('img'); img.src = imageUrl(row.image_path); img.alt = t('image') + ' ' + (index+1); img.loading = 'lazy';
      open.appendChild(img); cell.appendChild(open);
      if (owner) {
        var remove = document.createElement('button'); remove.type = 'button'; remove.className = 'certificate-delete';
        remove.textContent = '×'; remove.setAttribute('data-remove-certificate', row.id); remove.setAttribute('aria-label', t('delete'));
        remove.disabled = working; cell.appendChild(remove);
      }
      view.appendChild(cell);
    });
    if (rows.length) root.SFBestsellersScroll.mount(view, {
      itemSelector: '.certificate-item', sectionSelector: '.certificates-section', controlSelector: '.certificates-pause',
      copyClass: 'certificate-copy', repeatToFill: true, isPaused: function () { return viewer.open; }
    });
  }
  function load() {
    var token = ++version, all = [];
    retry.hidden = true; if (owner) state(t('loading'));
    function page(offset) {
      return root.sb.from('factory_certificates').select('id,image_path,created_at').eq('factory_id',factory.id)
        .order('created_at').order('id').range(offset,offset+99).then(function (r) {
          if (r.error) throw r.error; all = all.concat(r.data || []);
          return (r.data || []).length === 100 ? page(offset+100) : all;
        });
    }
    return page(0).then(function (data) {
      if (token !== version) return;
      rows = data; render(); state(!rows.length && owner ? t('empty') : '');
    }).catch(function () {
      if (token !== version) return;
      section.hidden = false; state(t('failed'),true); retry.hidden = false;
    });
  }
  function busy(value) {
    working = value; add.disabled = value;
    view.querySelectorAll('.certificate-delete').forEach(function (el) { el.disabled = value; });
  }
  async function upload(files) {
    if (!owner || working || !files.length) return;
    busy(true); state(t('uploading'));
    var failed = false;
    try {
      for (var file of files) {
        if (['image/jpeg','image/png','image/webp'].indexOf(file.type) === -1 || file.size > 5*1024*1024 || !file.size) throw new Error('invalid_image');
        // Decode before upload so renaming a PDF/video does not pass the picker.
        var bitmap = await createImageBitmap(file); bitmap.close();
        var uploaded = await root.SFUpload.uploadFile(file,'factory-certificates','certificates/'+factory.id,'image');
        var result = await root.sb.from('factory_certificates').insert({factory_id:factory.id,image_path:uploaded.path});
        if (result.error) {
          await root.sb.storage.from('factory-certificates').remove([uploaded.path]).catch(function () {});
          throw result.error;
        }
      }
    } catch (err) { failed = true; }
    finally { input.value = ''; await load(); busy(false); if (failed) { section.hidden = false; state(t('upload_failed'),true); } }
  }
  async function remove(row) {
    if (!owner || working || !root.confirm(t('confirm_delete'))) return;
    busy(true);
    try {
      var r = await root.sb.from('factory_certificates').delete().eq('id',row.id).eq('factory_id',factory.id).select('id');
      if (r.error || !r.data || !r.data.length) throw new Error('delete_failed');
      var cleanup = await root.sb.storage.from('factory-certificates').remove([row.image_path]).catch(function () { return {error:true}; });
      await load();
      if (cleanup.error) state(t('cleanup_failed'),true);
    } catch (err) { state(t('failed'),true); }
    finally { busy(false); }
  }
  root.SFCertificates = {
    mount: function (row) {
      if (!row || !root.sb) return;
      factory = row; owner = !!(root.SF_USER && row.owner_id === root.SF_USER.id && row.status === 'approved');
      if (!section) {
        section = document.getElementById('card-certificates'); view = document.getElementById('certificates-view');
        add = document.getElementById('certificates-add'); input = document.getElementById('certificates-input');
        message = document.getElementById('certificates-status'); retry = document.getElementById('certificates-retry');
        viewer = document.createElement('dialog'); viewer.className = 'certificate-viewer'; viewer.setAttribute('aria-label',t('title'));
        var close = document.createElement('button'); close.type = 'button'; close.className = 'certificate-viewer-close';
        close.textContent = '×'; close.setAttribute('aria-label',root.I18N.t('msg_cancel')); viewer.appendChild(close);
        var large = document.createElement('img'); large.alt = t('image'); viewer.appendChild(large); document.body.appendChild(viewer);
        close.addEventListener('click',function () { viewer.close(); });
        viewer.addEventListener('close',function () { large.removeAttribute('src'); });
        viewer.addEventListener('click',function (event) {
          if (event.target !== viewer) return;
          var rect=viewer.getBoundingClientRect();
          if (event.clientX<rect.left || event.clientX>rect.right || event.clientY<rect.top || event.clientY>rect.bottom) viewer.close();
        });
        add.addEventListener('click',function () { if (owner && !working) input.click(); });
        input.addEventListener('change',function () { upload(Array.from(input.files || [])); });
        retry.addEventListener('click',load);
        view.addEventListener('click',function (event) {
          var open = event.target.closest('[data-certificate]'), del = event.target.closest('[data-remove-certificate]');
          var id = open ? open.getAttribute('data-certificate') : del ? del.getAttribute('data-remove-certificate') : '';
          var item = rows.find(function (r) { return r.id === id; }); if (!item) return;
          if (del) remove(item); else { large.src = imageUrl(item.image_path); viewer.showModal(); }
        });
        root.addEventListener('beforeunload',function () { if (view.sfStopScroll) view.sfStopScroll(); });
      }
      add.hidden = !owner; section.hidden = !owner;
      return load();
    }
  };
})(window);
