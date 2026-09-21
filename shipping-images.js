/* صور خاصة بالتغليف؛ تُخزّن المسارات فقط وتُعرض بروابط مؤقتة. */
(function(root){
  'use strict';
  var pending=false, version=0;
  var say=function(ar,en){return root.I18N.getLang()==='ar'?ar:en;};
  var pattern=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$/;
  function paths(el){try{var data=JSON.parse(el.dataset.paths||'[]');return Array.isArray(data)?data.filter(function(p){return typeof p==='string'&&pattern.test(p);}):[];}catch(_){return [];}}
  function node(tag,text){var el=document.createElement(tag);if(text)el.textContent=text;return el;}
  async function compress(file){
    if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>10485760)throw Error('image_type');
    var bitmap=await root.createImageBitmap(file);
    try{
      if(!bitmap.width||!bitmap.height||bitmap.width*bitmap.height>40000000)throw Error('image_type');
      var scale=Math.min(1,1600/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');
      canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));
      var ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);
      var blob=await new Promise(function(resolve){canvas.toBlob(resolve,'image/jpeg',0.82);});
      if(!blob||blob.size>5242880)throw Error('image_type');return blob;
    }finally{bitmap.close();}
  }
  async function showImage(img,link,path,stamp){
    try{
      var result=await root.sb.storage.from('shipment-images').createSignedUrl(path,600);
      if(result.error)throw result.error;
      var url=new URL(result.data.signedUrl,root.SUPABASE_URL);
      if(url.origin!==new URL(root.SUPABASE_URL).origin||!['https:','http:'].includes(url.protocol))throw Error('image_url');
      if(stamp!==version||!img.isConnected)return;
      img.src=url.href;link.href=url.href;
    }catch(_){if(stamp===version&&img.isConnected)img.alt=say('تعذّر تحميل الصورة؛ حدّث الصفحة للمحاولة.','Image unavailable; refresh to retry.');}
  }
  function paint(el,stamp){
    var editable=el.dataset.editable==='true',data=paths(el),list=el.querySelector('[data-photo-list]');
    list.replaceChildren();
    data.forEach(function(path,index){
      var card=node('div'),link=node('a'),img=node('img');card.className='shipping-photo';
      link.target='_blank';link.rel='noopener noreferrer';img.alt=say('صورة التغليف ','Packing photo ')+(index+1);img.loading='lazy';
      link.append(img);card.append(link);
      if(editable){var remove=node('button',say('حذف الصورة','Remove image'));remove.type='button';remove.className='secondary';remove.disabled=pending;
        remove.addEventListener('click',function(){if(pending)return;el.dataset.paths=JSON.stringify(paths(el).filter(function(p){return p!==path;}));paint(el,stamp);});card.append(remove);}
      list.append(card);showImage(img,link,path,stamp);
    });
    if(!data.length&&!editable)list.append(node('span',say('لا توجد صور تغليف.','No packing photos.')));
  }
  function bind(host,orderId,append){
    var stamp=append?version:++version;
    host.querySelectorAll('[data-shipping-photos]').forEach(function(el){
      if(el.dataset.bound==='true')return;el.dataset.bound='true';
      var title=node('p',say('صور التغليف','Packing photos')),list=node('div');list.className='shipping-photo-list';list.dataset.photoList='';el.append(title,list);
      if(el.dataset.editable==='true'){
        var label=node('label',say('إضافة صور','Add images')),input=node('input'),note=node('p');
        input.type='file';input.accept='image/jpeg,image/png,image/webp';input.multiple=true;label.append(input);
        note.className='shipping-note';note.textContent=say('اختياري: 5 صور لكل مجموعة و20 للشحنة. JPG أو PNG أو WebP، حتى 10 ميجابايت للصورة قبل الضغط.','Optional: 5 images per group and 20 per shipment. JPG, PNG or WebP, up to 10 MB per image before compression.');
        var status=node('p');status.setAttribute('role','status');status.className='shipping-photo-status';el.append(label,note,status);
        input.addEventListener('change',async function(){
          var files=Array.from(input.files||[]);input.value='';if(!files.length||pending)return;
          var total=0;host.querySelectorAll('[data-shipping-photos][data-editable="true"]').forEach(function(group){total+=paths(group).length;});
          if(files.length+paths(el).length>5||files.length+total>20){status.textContent=say('الحد 5 صور للمجموعة و20 صورة للشحنة.','Limit: 5 images per group and 20 per shipment.');return;}
          pending=true;var controls=Array.from(host.querySelectorAll('button,input,select,textarea')).map(function(control){var old=control.disabled;control.disabled=true;return [control,old];});
          status.textContent=say('جارٍ رفع الصور…','Uploading images…');
          try{
            for(var file of files){
              var blob=await compress(file);if(stamp!==version||!el.isConnected)return;
              var path=orderId+'/'+root.crypto.randomUUID()+'.jpg';
              var result=await root.sb.storage.from('shipment-images').upload(path,blob,{contentType:'image/jpeg',upsert:false});
              if(result.error)throw result.error;
              if(stamp!==version||!el.isConnected)return;
              el.dataset.paths=JSON.stringify(paths(el).concat(path));paint(el,stamp);
            }
            status.textContent=say('تم رفع الصور. اضغط تأكيد بيانات الشحنة لحفظها مع التغليف.','Images uploaded. Confirm shipment details to save them with the packing.');
          }catch(error){if(stamp===version)status.textContent=error.message==='image_type'?say('اختر صورة JPG أو PNG أو WebP صالحة لا تتجاوز 10 ميجابايت.','Choose a valid JPG, PNG or WebP image up to 10 MB.'):
            say('تعذّر رفع بعض الصور. تحقق من الاتصال وتفعيل خدمة صور الشحن ثم أعد المحاولة. الصور التي اكتمل رفعها باقية.','Some images could not upload. Check your connection and shipping image setup, then retry. Completed uploads are kept.');
          }finally{pending=false;controls.forEach(function(pair){if(pair[0].isConnected)pair[0].disabled=pair[1];});if(stamp===version&&el.isConnected)paint(el,stamp);}
        });
      }
      paint(el,stamp);
    });
  }
  root.SFShippingImages={bind:bind,paths:paths,isBusy:function(){return pending;}};
})(window);
