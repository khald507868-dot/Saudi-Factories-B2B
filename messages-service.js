/* Supabase-backed messaging service. Attachments stay behind the same API;
 * text messages are persisted here and protected by database RLS. */
(function (root) {
  "use strict";

  function ready() {
    if (!root.sb || !root.SF_USER) return Promise.reject(new Error("يجب تسجيل الدخول للرسائل"));
    return Promise.resolve();
  }

  function factoryIdFromThread(id) {
    var match = String(id || "").match(/^factory-(\d+)$/);
    return match ? Number(match[1]) : null;
  }

  function toThread(row, currentId) {
    var factory = row.factories || {};
    var individual = row.profiles || {};
    var isFactory = root.SF_USER && row.individual_id !== root.SF_USER.id;
    return {
      id: String(row.id),
      conversation_id: row.id,
      factory_id: row.factory_id,
      name: isFactory ? (individual.full_name || "") : (factory.name || ""),
      role: isFactory ? "individual" : "factory",
      avatar: isFactory ? (individual.company_image || "") : (factory.logo || ""),
      messages: (row.messages || []).map(function (message) {
        return {
          id: message.id,
          from: message.sender_id === currentId ? "mine" : "theirs",
          type: message.attachment_type || "text",
          text: message.body || "",
          src: message.attachment_url || "",
          at: new Date(message.created_at).getTime()
        };
      }),
      updated: new Date(row.last_message_at || row.created_at).getTime()
    };
  }

  root.SFMessages = {
    load: function () {
      return ready().then(function () {
        return root.sb.from("conversations").select(
          "id, factory_id, individual_id, last_message_at, created_at, " +
          "factories(name, logo), profiles!conversations_individual_id_fkey(full_name, company_image), " +
          "messages(id, sender_id, body, attachment_url, attachment_type, created_at)"
        ).order("last_message_at", { ascending: false });
      }).then(function (res) {
        if (res.error) throw res.error;
        var out = {};
        (res.data || []).forEach(function (row) {
          out[String(row.id)] = toThread(row, root.SF_USER.id);
        });
        return out;
      });
    },

    ensureFactoryConversation: function (factoryId) {
      return ready().then(function () {
        return root.sb.from("conversations").select(
          "id, factory_id, individual_id, last_message_at, created_at, factories(name, logo), " +
          "profiles!conversations_individual_id_fkey(full_name, company_image), messages(id, sender_id, body, attachment_url, attachment_type, created_at)"
        ).eq("factory_id", factoryId).eq("individual_id", root.SF_USER.id).maybeSingle();
      }).then(function (res) {
        if (res.error) throw res.error;
        if (res.data) return toThread(res.data, root.SF_USER.id);
        return root.sb.from("conversations").insert({
          factory_id: Number(factoryId), individual_id: root.SF_USER.id
        }).select(
          "id, factory_id, individual_id, last_message_at, created_at, factories(name, logo), " +
          "profiles!conversations_individual_id_fkey(full_name, company_image), messages(id, sender_id, body, attachment_url, attachment_type, created_at)"
        ).single();
      }).then(function (res) {
        if (res.error) throw res.error;
        return res.id ? toThread(res, root.SF_USER.id) : res;
      });
    },

    sendAttachment: function (conversationId, file, type) {
      return ready().then(function () {
        var extension = (file.name || "bin").split(".").pop().toLowerCase().replace(/[^a-z0-9]/g, "") || "bin";
        var path = root.SF_USER.id + "/" + (root.crypto && root.crypto.randomUUID ? root.crypto.randomUUID() : String(Date.now())) + "." + extension;
        return root.sb.storage.from("chat-media").upload(path, file, { upsert: false, contentType: file.type || undefined });
      }).then(function (uploadRes) {
        if (uploadRes.error) throw uploadRes.error;
        return root.sb.from("messages").insert({
          conversation_id: Number(conversationId),
          sender_id: root.SF_USER.id,
          body: "",
          attachment_url: uploadRes.data.path,
          attachment_type: type
        }).select("id, sender_id, body, attachment_url, attachment_type, created_at").single();
      }).then(function (messageRes) {
        if (messageRes.error) throw messageRes.error;
        return root.sb.storage.from("chat-media").createSignedUrl(messageRes.data.attachment_url, 3600).then(function (urlRes) {
          if (urlRes.error) throw urlRes.error;
          messageRes.data.signed_url = urlRes.data.signedUrl;
          return messageRes.data;
        });
      });
    },

    sendText: function (conversationId, text) {
      return ready().then(function () {
        return root.sb.from("messages").insert({
          conversation_id: Number(conversationId),
          sender_id: root.SF_USER.id,
          body: String(text || "").slice(0, 10000),
          attachment_url: "",
          attachment_type: ""
        }).select("id, sender_id, body, attachment_url, attachment_type, created_at").single();
      }).then(function (res) {
        if (res.error) throw res.error;
        return res.data;
      });
    },

    subscribe: function (onChange) {
      if (!root.sb || !root.SF_USER) return null;
      return root.sb.channel("sf-messages-" + root.SF_USER.id)
        .on("postgres_changes", { event: "*", schema: "public", table: "messages" }, onChange)
        .subscribe();
    }
  };
}(window));
