/* Supabase-backed messaging service. The conversation list is intentionally
 * lightweight; messages and private attachment URLs load only for the chat
 * that the user opens. */
(function (root) {
  "use strict";

  var CONVERSATION_SELECT = "id, factory_id, individual_id, last_message_at, created_at";
  var LEGACY_CONVERSATION_SELECT =
    CONVERSATION_SELECT + ", factories(name, logo), " +
    "profiles!conversations_individual_id_fkey(full_name, company_image), " +
    "messages(id, sender_id, body, attachment_url, attachment_type, created_at)";
  var MESSAGE_SELECT = "id, sender_id, body, attachment_url, attachment_type, created_at";

  function ready() {
    if (!root.sb || !root.SF_USER) return Promise.reject(new Error("يجب تسجيل الدخول للرسائل"));
    return Promise.resolve();
  }

  function validFactoryId(value) {
    var id = Number(value);
    return Number.isInteger(id) && id > 0 ? id : null;
  }

  function validConversationId(value) {
    var id = Number(value);
    return Number.isInteger(id) && id > 0 ? id : null;
  }

  function messageTime(message) {
    var time = new Date(message.created_at).getTime();
    return isNaN(time) ? 0 : time;
  }

  function mapMessage(message, currentId) {
    return {
      id: message.id,
      from: message.sender_id === currentId ? "mine" : "theirs",
      type: message.attachment_type || "text",
      text: message.body || "",
      src: message.signed_url || "",
      at: messageTime(message)
    };
  }

  function signMessages(messages) {
    var jobs = [];

    (messages || []).forEach(function (message) {
      if (!message.attachment_url) return;
      jobs.push(
        root.sb.storage.from("chat-media")
          .createSignedUrl(message.attachment_url, 3600)
          .then(function (res) {
            if (!res.error && res.data) message.signed_url = res.data.signedUrl;
          })
          .catch(function () {
            /* تبقى الرسالة النصية ظاهرة حتى لو تعذّر توقيع المرفق مؤقتًا. */
          })
      );
    });

    return Promise.all(jobs).then(function () { return messages || []; });
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
      return rows || [];
    });
  }

  function summaryToThread(row) {
    var lastAt = row.last_message_created_at || row.last_message_at;
    var updated = new Date(lastAt || 0).getTime();
    return {
      id: String(row.conversation_id),
      conversation_id: row.conversation_id,
      factory_id: row.factory_id,
      name: row.peer_name || "",
      role: row.peer_role || "",
      avatar: row.peer_avatar || "",
      messages: [],
      messagesLoaded: false,
      lastMessage: row.last_message_created_at ? {
        from: row.last_message_sender_id === root.SF_USER.id ? "mine" : "theirs",
        type: row.last_message_type || "text",
        text: row.last_message_body || "",
        at: new Date(row.last_message_created_at).getTime()
      } : null,
      unread: Math.max(0, Number(row.unread_count || 0)),
      updated: isNaN(updated) ? 0 : updated
    };
  }

  function legacyToThread(row, currentId) {
    var factory = row.factories || {};
    var individual = row.profiles || {};
    var isFactory = root.SF_USER && row.individual_id !== root.SF_USER.id;
    var peer = row.peer || {};
    var messages = (row.messages || []).slice().sort(function (a, b) {
      return messageTime(a) - messageTime(b) || Number(a.id || 0) - Number(b.id || 0);
    }).map(function (message) {
      return mapMessage(message, currentId);
    });
    return {
      id: String(row.id),
      conversation_id: row.id,
      factory_id: row.factory_id,
      name: peer.peer_name || (isFactory ? (individual.full_name || "") : (factory.name || "")),
      role: peer.peer_role || (isFactory ? "individual" : "factory"),
      avatar: peer.peer_avatar || (isFactory ? (individual.company_image || "") : (factory.logo || "")),
      messages: messages,
      messagesLoaded: true,
      lastMessage: messages.length ? messages[messages.length - 1] : null,
      unread: 0,
      updated: new Date(row.last_message_at || row.created_at).getTime()
    };
  }

  function shellToThread(row) {
    var peer = row.peer || {};
    return {
      id: String(row.id),
      conversation_id: row.id,
      factory_id: row.factory_id,
      name: peer.peer_name || "",
      role: peer.peer_role || "",
      avatar: peer.peer_avatar || "",
      messages: [],
      messagesLoaded: false,
      lastMessage: null,
      unread: 0,
      updated: new Date(row.last_message_at || row.created_at).getTime()
    };
  }

  function loadLegacy() {
    return root.sb.from("conversations")
      .select(LEGACY_CONVERSATION_SELECT)
      .order("last_message_at", { ascending: false })
      .then(function (res) {
        if (res.error) throw res.error;
        return addPeerMetadata(res.data || []);
      }).then(function (rows) {
        var rawMessages = [];
        rows.forEach(function (row) {
          (row.messages || []).forEach(function (message) { rawMessages.push(message); });
        });
        return signMessages(rawMessages).then(function () { return rows; });
      }).then(function (rows) {
        var out = {};
        rows.forEach(function (row) {
          out[String(row.id)] = legacyToThread(row, root.SF_USER.id);
        });
        return out;
      });
  }

  function threadFromRow(row) {
    return addPeerMetadata([row]).then(function (rows) {
      return shellToThread(rows[0]);
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
        return root.sb.rpc("get_conversation_summaries");
      }).then(function (res) {
        if (res.error) return loadLegacy();

        var out = {};
        (res.data || []).forEach(function (row) {
          out[String(row.conversation_id)] = summaryToThread(row);
        });
        return out;
      });
    },

    loadMessages: function (conversationId) {
      return ready().then(function () {
        var id = validConversationId(conversationId);
        if (!id) throw new Error("معرّف المحادثة غير صالح");
        return root.sb.from("messages")
          .select(MESSAGE_SELECT)
          .eq("conversation_id", id)
          .order("created_at", { ascending: true })
          .order("id", { ascending: true });
      }).then(function (res) {
        if (res.error) throw res.error;
        return signMessages(res.data || []);
      }).then(function (rows) {
        return rows.map(function (message) {
          return mapMessage(message, root.SF_USER.id);
        });
      });
    },

    markRead: function (conversationId) {
      return ready().then(function () {
        var id = validConversationId(conversationId);
        if (!id) throw new Error("معرّف المحادثة غير صالح");
        return root.sb.rpc("mark_conversation_read", { p_conversation_id: id });
      }).then(function (res) {
        if (res.error) {
          /* توافق مؤقت قبل تطبيق ترحيل العدّاد. */
          return root.sb.from("messages")
            .update({ read_at: new Date().toISOString() })
            .eq("conversation_id", Number(conversationId))
            .neq("sender_id", root.SF_USER.id)
            .is("read_at", null)
            .then(function (fallback) {
              if (fallback.error) throw fallback.error;
              return 0;
            });
        }
        return Number(res.data || 0);
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
        }).select(MESSAGE_SELECT).single();
      }).then(function (messageRes) {
        if (messageRes.error) throw messageRes.error;
        return signMessages([messageRes.data]).then(function (rows) { return rows[0]; });
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
        }).select(MESSAGE_SELECT).single();
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
