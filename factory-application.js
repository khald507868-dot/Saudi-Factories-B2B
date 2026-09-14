(function (root) {
  'use strict';
  var fields = [
    ['name', 'field_name', 200, true],
    ['commercial_register', 'field_cr', 10, true],
    ['industrial_license', 'field_industrial_license', 10, true],
    ['address_city', 'factory_address_city', 200],
    ['address_district', 'factory_address_district', 200],
    ['address_short', 'factory_address_short', 200],
    ['address_building', 'factory_address_building', 200],
    ['address_secondary', 'factory_address_secondary', 200],
    ['address_postal', 'factory_address_postal', 200],
    ['address_street', 'factory_address_street', 200]
  ];
  var edit = document.getElementById('edit-application');
  var form = document.getElementById('application-form');
  var fieldBox = document.getElementById('application-fields');
  var status = document.getElementById('application-status');
  var access = null, editing = false, busy = false;
  var inputs = {};

  fields.forEach(function (field) {
    var label = document.createElement('label');
    var name = document.createElement('span');
    name.textContent = I18N.t(field[1]);
    var input = document.createElement('input');
    input.name = field[0];
    input.maxLength = field[2];
    input.required = !!field[3];
    if (field[0] === 'commercial_register' || field[0] === 'industrial_license') {
      input.inputMode = 'numeric';
      input.pattern = '[0-9]{1,10}';
      input.dir = 'ltr';
    }
    label.append(name, input);
    fieldBox.appendChild(label);
    inputs[field[0]] = input;
  });
  function message(key) { status.textContent = key ? I18N.t(key) : ''; }
  function setBusy(value) {
    busy = value;
    form.querySelectorAll('button,input').forEach(function (el) { el.disabled = value; });
    edit.disabled = value;
    document.getElementById('gate-signout').disabled = value;
  }
  function close() {
    editing = false;
    form.hidden = true;
    edit.hidden = !access || access.state !== 'rejected';
    document.getElementById('check-approval').hidden = false;
    document.querySelector('.account-gate').classList.remove('editing-application');
    message('');
  }
  edit.addEventListener('click', async function () {
    if (busy || !access || access.state !== 'rejected') return;
    editing = true;
    setBusy(true); message('auth_checking');
    try {
      var result = await sb.from('factories').select(fields.map(function (f) { return f[0]; }).join(',') + ',status')
        .eq('owner_id', access.user.id).single();
      if (result.error || !result.data) throw result.error || new Error('unavailable');
      if (result.data.status !== 'rejected') {
        close();
        root.dispatchEvent(new Event('sf:application-resubmitted'));
        return;
      }
      fields.forEach(function (field) { inputs[field[0]].value = result.data[field[0]] || ''; });
      form.hidden = false;
      edit.hidden = true;
      document.getElementById('check-approval').hidden = true;
      document.querySelector('.account-gate').classList.add('editing-application');
      message('');
    } catch (_) { editing = false; message('auth_check_failed'); }
    finally { setBusy(false); }
    if (!form.hidden) inputs.industrial_license.focus();
  });
  document.getElementById('application-cancel').addEventListener('click', function () {
    if (busy) return;
    close(); edit.focus();
  });
  form.addEventListener('submit', async function (event) {
    event.preventDefault();
    if (busy || !editing || !form.reportValidity()) return;
    var details = {};
    fields.forEach(function (field) { details[field[0]] = inputs[field[0]].value.trim(); });
    setBusy(true); message('auth_checking');
    try {
      var result = await sb.rpc('resubmit_factory_application', { details: details });
      if (result.error || !result.data || result.data.status !== 'pending') throw result.error || new Error('unavailable');
      access = null;
      close();
      root.dispatchEvent(new Event('sf:application-resubmitted'));
    } catch (error) {
      message(error && error.message === 'invalid_application_details' ? 'auth_application_invalid' : 'auth_application_failed');
    } finally { setBusy(false); }
  });
  root.SFFactoryApplication = {
    isEditing: function () { return editing; },
    updateAccess: function (value) { access = value; edit.hidden = !value || value.state !== 'rejected'; }
  };
})(window);
