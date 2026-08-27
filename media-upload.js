/* Shared, client-safe media uploader.
 * Only the publishable Supabase client is used here; authorization is enforced
 * by Storage policies. Secret keys must never be placed in this file. */
(function (root) {
  "use strict";

  var MAX_IMAGE_BYTES = 5 * 1024 * 1024;
  var MAX_VIDEO_BYTES = 50 * 1024 * 1024;
  var IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"];
  var VIDEO_TYPES = ["video/mp4", "video/webm", "video/quicktime"];

  function extension(type) {
    return ({
      "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp",
      "image/gif": "gif", "video/mp4": "mp4", "video/webm": "webm",
      "video/quicktime": "mov"
    })[type] || "bin";
  }

  function check(file, kind) {
    if (!file) throw new Error("لم يتم اختيار ملف");
    var allowed = kind === "video" ? VIDEO_TYPES : IMAGE_TYPES;
    var max = kind === "video" ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES;
    if (allowed.indexOf(file.type) === -1) throw new Error("نوع الملف غير مسموح");
    if (file.size > max) throw new Error("حجم الملف أكبر من الحد المسموح");
  }

  function uploadFile(file, bucket, folder, kind) {
    check(file, kind);
    if (!root.sb || !root.SF_USER) return Promise.reject(new Error("يجب تسجيل الدخول لرفع الملفات"));
    var path = String(root.SF_USER.id) + "/" + String(folder || "media") + "/" +
      (root.crypto && root.crypto.randomUUID ? root.crypto.randomUUID() : String(Date.now())) + "." + extension(file.type);
    return root.sb.storage.from(bucket).upload(path, file, {
      cacheControl: "3600",
      upsert: false,
      contentType: file.type
    }).then(function (res) {
      if (res.error) throw res.error;
      var url = root.sb.storage.from(bucket).getPublicUrl(path);
      return { path: path, url: url.data.publicUrl, bucket: bucket };
    });
  }

  function dataUrlToBlob(dataUrl) {
    var parts = dataUrl.split(",");
    var match = parts[0].match(/data:([^;]+);base64/);
    if (!match) throw new Error("صيغة الصورة غير صالحة");
    var binary = atob(parts[1]);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes], { type: match[1] });
  }

  root.SFUpload = {
    uploadFile: uploadFile,
    uploadDataUrl: function (dataUrl, bucket, folder, kind) {
      var blob = dataUrlToBlob(dataUrl);
      return uploadFile(blob, bucket, folder, kind || "image");
    },
    limits: { image: MAX_IMAGE_BYTES, video: MAX_VIDEO_BYTES }
  };
}(window));
