// No service key is returned to the browser. The request cannot choose a user ID.
export function createDeleteAccountHandler(admin) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
  };
  const reply = (status, body) => new Response(JSON.stringify(body), {status, headers});
  return async function (request) {
    if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers});
    if (request.method !== 'POST') return reply(405, {error: 'method_not_allowed'});
    const token = request.headers.get('Authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!token) return reply(401, {error: 'invalid_session'});
    try {
      const {data, error} = await admin.auth.getUser(token);
      if (error || !data?.user) return reply(401, {error: 'invalid_session'});
      let body;
      try { body = await request.json(); } catch (_) { return reply(400, {error: 'confirmation_required'}); }
      if (body?.confirmation !== 'DELETE') return reply(400, {error: 'confirmation_required'});
      const id = data.user.id;
      // Storage must be removed through its API before Auth can delete its owner.
      // Every batch checks for orders first; all order statuses are preserved.
      for (let batch = 0; batch < 100; batch++) {
        const media = await admin.rpc('account_deletion_media', {target_user: id});
        if (media.error) {
          return reply(media.error.message === 'account_has_orders' ? 409 : 503, {
            error: media.error.message === 'account_has_orders' ? 'account_has_orders' : 'deletion_failed',
          });
        }
        if (!Array.isArray(media.data)) return reply(503, {error: 'deletion_failed'});
        if (media.data.length === 0) {
          const removed = await admin.auth.admin.deleteUser(id);
          if (removed.error) return reply(503, {error: 'deletion_failed'});
          return reply(200, {deleted: true});
        }
        const buckets = new Map();
        for (const file of media.data) {
          if (!buckets.has(file.bucket_id)) buckets.set(file.bucket_id, []);
          buckets.get(file.bucket_id).push(file.name);
        }
        for (const [bucket, paths] of buckets) {
          const removed = await admin.storage.from(bucket).remove(paths);
          if (removed.error) return reply(503, {error: 'deletion_failed'});
        }
      }
      return reply(503, {error: 'deletion_failed'});
    } catch (_) {
      return reply(503, {error: 'deletion_failed'});
    }
  };
}
