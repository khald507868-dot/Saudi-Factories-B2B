import { createClient } from 'npm:@supabase/supabase-js@2';
import { createDeleteAccountHandler } from './handler.mjs';

// Supabase supplies these secrets to deployed Edge Functions.
const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  {auth: {persistSession: false, autoRefreshToken: false}},
);
Deno.serve(createDeleteAccountHandler(admin));
