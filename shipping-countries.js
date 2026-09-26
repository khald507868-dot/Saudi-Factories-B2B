(function(root){
  'use strict';
  // ISO 3166-1 country/territory codes; labels follow the browser's locale data.
  var codes=('AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW').split(' ');
  var en=new Intl.DisplayNames(['en'],{type:'region'}),ar=new Intl.DisplayNames(['ar'],{type:'region'});
  var aliases={ksa:'SA',sau:'SA','kingdom of saudi arabia':'SA','السعودية':'SA','السعوديه':'SA','المملكة العربية السعودية':'SA','المملكه العربيه السعوديه':'SA',uae:'AE',uk:'GB',usa:'US','united states of america':'US',turkey:'TR'};
  function normalize(value){return String(value||'').trim().toLowerCase().replace(/\s+/g,' ');}
  function code(value){
    var key=normalize(value);
    return aliases[key]||codes.find(function(c){return c.toLowerCase()===key||normalize(en.of(c))===key||normalize(ar.of(c))===key;})||'';
  }
  function list(lang){
    var labels=lang==='ar'?ar:en;
    return codes.map(function(c){return {code:c,value:en.of(c),name:labels.of(c)};}).sort(function(a,b){return a.name.localeCompare(b.name,lang==='ar'?'ar':'en');});
  }
  function searchKey(value){return normalize(value).normalize('NFD').replace(/[\u0300-\u036f\u064b-\u065f\u0670\u0640]/g,'').replace(/[أإآ]/g,'ا');}
  function search(query,lang){
    var key=searchKey(query),alias=aliases[normalize(query)];
    return list(lang).filter(function(c){return !key||c.code===alias||[c.code,c.value,ar.of(c.code)].some(function(name){return searchKey(name).includes(key);});});
  }
  function phoneSearch(query,lang){
    var labels=lang==='ar'?ar:en,key=searchKey(query),alias=aliases[normalize(query)];
    return Object.keys(root.SFShippingCallingCodes||{}).filter(function(c){
      return !key||c===alias||[c,en.of(c),ar.of(c),root.SFShippingCallingCodes[c]].some(function(name){return searchKey(name).includes(key);});
    }).map(function(c){return {value:c,name:labels.of(c)+' ('+root.SFShippingCallingCodes[c]+')'};}).sort(function(a,b){return a.name.localeCompare(b.name,lang==='ar'?'ar':'en');});
  }
  function readPhone(form){
    var region=form.elements.phone_country_iso.value,number=form.elements.phone.value.trim();
    if(!region)throw new Error('shipping_phone_code_required');
    var prefix=root.SFShippingCallingCodes[region]||'';
    if(region&&!prefix){
      if(Object.values(root.SFShippingCallingCodes).includes(region))prefix=region;
      else throw new Error('shipping_invalid_phone_code');
    }
    if(prefix){
      var compact=number.replace(/[٠-٩]/g,function(n){return String(n.charCodeAt(0)-1632);}).replace(/[۰-۹]/g,function(n){return String(n.charCodeAt(0)-1776);}).replace(/[\s().-]/g,'');
      if(compact.indexOf('00')===0)compact='+'+compact.slice(2);
      if(compact.charAt(0)==='+'){
        if(compact.indexOf(prefix)!==0||compact.length===prefix.length)throw new Error('shipping_invalid_phone_code');
        number=compact.slice(prefix.length);
      }
    }
    return {phone:number,phone_country_code:prefix||null,phone_country_iso:root.SFShippingCallingCodes[region]?region:null};
  }
  function bind(form,phone){
    var picker=form.querySelector(phone?'[data-phone-picker]':'[data-country-picker]');
    if(!picker||picker.dataset.bound)return;
    picker.dataset.bound='true';
    var select=form.elements[phone?'phone_country_iso':'country'],input=picker.querySelector('[data-country-search]'),toggle=picker.querySelector('[data-country-toggle]');
    var options=picker.querySelector('[role="listbox"]'),empty=picker.querySelector('[data-country-empty]');
    var lang=root.I18N.getLang(),visible=[],active=-1;
    function selectedName(){if(phone)return root.SFShippingCallingCodes[select.value]||select.value||'';var option=select.options[select.selectedIndex];return select.value&&option?option.textContent:'';}
    function close(){
      options.hidden=true;empty.hidden=true;input.setAttribute('aria-expanded','false');input.removeAttribute('aria-activedescendant');
      input.value=selectedName();input.setCustomValidity('');
    }
    function highlight(index){
      active=index;
      Array.from(options.children).forEach(function(el,i){el.classList.toggle('is-active',i===active);});
      if(active<0){input.removeAttribute('aria-activedescendant');return;}
      var item=options.children[active];input.setAttribute('aria-activedescendant',item.id);item.scrollIntoView({block:'nearest'});
    }
    function open(query){
      visible=phone?phoneSearch(query||'',lang):search(query||'',lang);
      // Keep a historical free-text country selectable until it is replaced.
      var saved=select.value;
      if(saved&&!(phone?root.SFShippingCallingCodes[saved]:code(saved))&&(!query||searchKey(saved).includes(searchKey(query))))visible.unshift({value:saved,name:selectedName()});
      options.replaceChildren();
      visible.forEach(function(c,i){
        var item=input.ownerDocument.createElement('div');item.id=options.id+'-'+i;item.setAttribute('role','option');
        item.setAttribute('aria-selected',String(c.value===select.value));item.dataset.countryIndex=String(i);item.textContent=c.name;options.appendChild(item);
      });
      options.hidden=false;empty.hidden=visible.length>0;input.setAttribute('aria-expanded','true');
      var selected=visible.findIndex(function(c){return c.value===select.value;});
      highlight(query?(visible.length?0:-1):(selected>=0?selected:visible.length?0:-1));
    }
    function choose(index){
      if(!visible[index]||input.disabled)return;
      select.value=visible[index].value;close();select.dispatchEvent(new Event('change',{bubbles:true}));
    }
    input.addEventListener('focus',function(){open();});
    input.addEventListener('input',function(){
      if(phone&&!input.value){select.value='';input.setCustomValidity('');select.dispatchEvent(new Event('change',{bubbles:true}));}
      else input.setCustomValidity(input.value===selectedName()?'':lang==='ar'?'اختر دولة من نتائج البحث.':'Choose a country from the search results.');open(input.value);
    });
    toggle.addEventListener('click',function(){var expanded=input.getAttribute('aria-expanded')==='true';input.focus();if(expanded)close();else open();});
    options.addEventListener('mousedown',function(event){event.preventDefault();});
    options.addEventListener('click',function(event){var item=event.target.closest('[data-country-index]');if(item&&options.contains(item))choose(Number(item.dataset.countryIndex));});
    input.addEventListener('keydown',function(event){
      var expanded=input.getAttribute('aria-expanded')==='true';
      if(event.key==='ArrowDown'||event.key==='ArrowUp'){
        event.preventDefault();if(!expanded){open();return;}
        if(visible.length)highlight((active+(event.key==='ArrowDown'?1:-1)+visible.length)%visible.length);
      }else if(expanded&&event.key==='Enter'){event.preventDefault();choose(active);}
      else if(expanded&&event.key==='Escape'){event.preventDefault();event.stopPropagation();close();}
      else if(event.key==='Tab')close();
    });
    picker.addEventListener('focusout',function(event){if(!picker.contains(event.relatedTarget))close();});
    close();
  }
  root.SFShippingCountries={code:code,list:list,search:search,phoneSearch:phoneSearch,readPhone:readPhone,bind:bind};
})(window);
