/* Supabase-backed messaging service. Conversations and messages live on the
 * server; private attachments are exposed through short-lived signed URLs. */
(function (root) {
  "use strict";

  var CONVERSATION_SELECT =
    "id, factory_id, individual_id, last_message_at, created_at, " +
    "factories(name, logo), profiles!conversations_individual_id_fkey(full_name, company_image), " +
    "messages(id, sender_id, body, attachment_url, attachment_type, created_at)";

  function ready() {
    if (!root.sb || !root.SF_USER) return Promise.reject(new Error("يجب تسجيل الدخول للرسائل"));
    return Promise.resolve();
  }

  function validFactoryId(value) {
    var id = Number(value);
    return Number.isInteger(id) && id > 0 ? id : null;
  }

  function messageTime(message) {
    var time = new Date(message.created_at).getTime();
    return isNaN(time) ? 0 : time;
  }

  function signAttachments(rows) {
    var jobs = [];

    (rows || []).forEach(function (row) {
      (row.messages || []).forEach(function (message) {
        if (!message.attachment_url) return;

        jobs.push(
          root.sb.storage.from("chat-media")
            .createSignedUrl(message.attachment_url, 3600)
            .then(function (res) {
              if (!res.error && res.data) message.signed_url = res.data.signedUrl;
            })
            .catch(function () {
              /* تبقى الرسالة ظاهرة حتى لو تعذّر توقيع المرفق مؤقتًا. */
            })
        );
      });
    });

    return Promise.all(jobs).then(function () { return rows || []; });
  }

  function addPeerMetadata(rows) {
    return root.sb.rpc("get_conversation_peers").then(function (res) {
      if (res.error) return rows || [];

      var peers = {};
      (res.data || []).forEach(function (peer) {
        peers[String(peer.conversation_id)] = peer;
      });
      (rows || []).forEach(function (row) {
        row.peer = peers[String(row.id)] || null;
      });
      return rows || [];
    }).catch(function () {
      /* توافق مؤقت قبل تطبيق ترحيل get_conversation_peers. */
      return rows || [];
    });
  }

  function toThread(row, currentId) {
    var factory = row.factories || {};
    var individual = row.profiles || {};
    var isFactory = root.SF_USER && row.individual_id !== root.SF_USER.id;
    var peer = row.peer || {};
    return {
      id: String(row.id),
      conversation_id: row.id,
      factory_id: row.factory_id,
      name: peer.peer_name || (isFactory ? (individual.full_name || "") : (factory.name || "")),
      role: peer.peer_role || (isFactory ? "individual" : "factory"),
      avatar: peer.peer_avatar || (isFactory ? (individual.company_image || "") : (factory.logo || "")),
      messages: (row.messages || []).slice().sort(function (a, b) {
        return messageTime(a) - messageTime(b) || Number(a.id || 0) - Number(b.id || 0);
      }).map(function (message) {
        return {
          id: message.id,
          from: message.sender_id === currentId ? "mine" : "theirs",
          type: message.attachment_type || "text",
          text: message.body || "",
          src: message.signed_url || "",
          at: messageTime(message)
        };
      }),
      updated: new Date(row.last_message_at || row.created_at).getTime()
    };
  }

  function threadFromRow(row) {
    return addPeerMetadata([row]).then(signAttachments).then(function (rows) {
      return toThread(rows[0], root.SF_USER.id);
    });
  }

  function findConversation(factoryId) {
    return root.sb.from("conversations")
      .select(CONVERSATION_SELECT)
      .eq("factory_id", factoryId)
      .eq("individual_id", root.SF_USER.id)
      .maybeSingle();
  }

  function insertConversation(factoryId) {
    return root.sb.from("conversations").insert({
      factory_id: factoryId,
      individual_id: root.SF_USER.id
    }).select(CONVERSATION_SELECT).single();
  }

  root.SFMessages = {
    load: function () {
      return ready().then(function () {
        return root.sb.from("conversations")
          .select(CONVERSATION_SELECT)
          .order("last_message_at", { ascending: false });
      }).then(function (res) {
        if (res.error) throw res.error;
        return addPeerMetadata(res.data || []);
      }).then(signAttachments).then(function (rows) {
        var out = {};
        rows.forEach(function (row) {
          out[String(row.id)] = toThread(row, root.SF_USER.id);
        });
        return out;
      });
    },

    listFactories: function () {
      return ready().then(function () {
        return root.sb.from("factories")
          .select("id, name, logo")
          .eq("status", "approved")
          .order("name", { ascending: true });
      }).then(function (res) {
        if (res.error) throw res.error;
        return res.data || [];
      });
    },

    ensureFactoryConversation: function (factoryId) {
      return ready().then(function () {
        var id = validFactoryId(factoryId);
        if (!id) throw new Error("معرّف المصنع غير صالح");
        if (root.SF_PROFILE && root.SF_PROFILE.account_type === "factory") {
          throw new Error("حساب المصنع يستقبل محادثات العملاء ولا يبدأ محادثة مع مصنع آخر");
        }
        return findConversation(id).then(function (res) {
          return { id: id, response: res };
        });
      }).then(function (state) {
        var res = state.response;
        if (res.error) throw res.error;
        if (res.data) return threadFromRow(res.data);

        return insertConversation(state.id).then(function (created) {
          if (!created.error) return threadFromRow(created.data);

          /* طلبان متزامنان قد يصطدمان بالقيد الفريد؛ اقرأ الصف الفائز. */
          if (created.error.code === "23505") {
            return findConversation(state.id).then(function (retry) {
              if (retry.error) throw retry.error;
              if (!retry.data) throw created.error;
              return threadFromRow(retry.data);
            });
          }
          throw created.error;
        });
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
        if (messageRes.error) {
          throw messageRes.error;
        }
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
