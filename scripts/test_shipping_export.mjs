import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
let lang='en';
const window={I18N:{getLang:()=>lang}};
vm.runInNewContext(fs.readFileSync(new URL('../shipping-export.js',import.meta.url),'utf8'),{window});
const api=window.SFShippingExport;
const elements=Object.fromEntries(Object.entries({destination_scope:'international',export_mode:'sea',export_sea_service:'fcl',export_container_type:'40ft_hc',export_container_count:'2',export_route:'port_to_port',export_origin_terminal:'Jeddah',export_incoterm:'FOB',export_named_place:'Jeddah',delivery_type:'door',port:'Dubai'}).map(([k,value])=>[k,{value}]));
elements.port.parentElement={};
elements.export_incoterm.options=['EXW','FOB','CFR','CIF','DDP'].map(value=>({value}));
const groups=new Map();
const form={elements,querySelector(selector){if(!groups.has(selector))groups.set(selector,{});return groups.get(selector);}};
api.sync(form);
assert(!groups.get('[data-export-sea]').hidden);assert(!groups.get('[data-export-fcl]').disabled);
assert(!groups.get('[data-export-origin]').disabled);assert(elements.port.required);assert.equal(elements.delivery_type.value,'port');
const p=api.read(form);assert.equal(p.container_count,2);assert.equal(p.container_type,'40ft_hc');
for(const count of ['0','1.5','1001','NaN']){elements.export_container_count.value=count;assert.throws(()=>api.read(form),/invalid_export/);}
elements.export_container_count.value='2';
elements.export_mode.value='air';api.sync(form);
assert(groups.get('[data-export-sea]').disabled);assert(groups.get('[data-export-fcl]').disabled);
assert.equal(elements.export_incoterm.value,'');assert(elements.export_incoterm.options[1].disabled);
elements.export_incoterm.value='CIF';assert.throws(()=>api.read(form),/invalid_export/);
elements.export_incoterm.value='DDP';elements.export_route.value='door_to_door';api.sync(form);
assert(!elements.port.required);assert(elements.port.disabled);assert(elements.port.parentElement.hidden);
assert.equal(elements.delivery_type.value,'door');
const air=api.read(form);assert.equal(air.sea_service,null);assert.equal(air.container_count,null);assert.equal(air.origin_terminal,null);
for(const mode of ['air','road','rail','express','multimodal']){elements.export_mode.value=mode;assert.equal(api.read(form).transport_mode,mode);}
elements.export_mode.value='sea';elements.export_sea_service.value='lcl';api.sync(form);
assert(!groups.get('[data-export-lcl]').hidden);assert(groups.get('[data-export-fcl]').disabled);assert.equal(api.read(form).container_type,null);
elements.export_named_place.value='   ';assert.throws(()=>api.read(form),/invalid_export/);
elements.export_named_place.value='Dubai';elements.export_route.value='port_to_door';elements.export_origin_terminal.value='';
assert.throws(()=>api.read(form),/invalid_export/);
elements.destination_scope.value='domestic';api.sync(form);assert(groups.get('[data-export-sea]').disabled);assert(!elements.port.required);
const markup=api.markup({...p,named_place:'"><script>bad</script>'});assert(!markup.includes('<script>'));
for(const [name,count,selected] of [['export_mode',6,'sea'],['export_sea_service',5,'fcl'],['export_route',4,'port_to_port']]){
  const choices=markup.match(new RegExp('<select name="'+name+'" required>(.*?)</select>'))?.[1];
  assert(choices);assert.equal((choices.match(/<option /g)||[]).length,count+1);assert(choices.includes('value="'+selected+'" selected'));
}
assert(!markup.includes('type="radio"'));assert(api.summary(p,true).includes('Export preferences in this quote'));
assert(api.summary({...p,named_place:'<img src=x>'}).includes('&lt;img'));assert(!api.summary({...p,named_place:'<img src=x>'}).includes('<img'));
lang='ar';assert(api.markup(p).includes('خيارات التصدير'));assert(api.summary(p).includes('الشحن البحري'));
console.log('PASS export choices, FCL validation, conditional fields, stale-value removal, term compatibility, localization and escaped summaries');
