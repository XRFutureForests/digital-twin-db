import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

/**
 * Initializes and returns a Supabase client with SERVICE_ROLE privileges
 *
 * The SERVICE_ROLE_KEY grants full database access without row-level security
 * restrictions. Use only for trusted server-side operations. This should never
 * be exposed to clients.
 *
 * @returns {SupabaseClient} Authenticated Supabase client instance
 * @throws {Error} If SUPABASE_SERVICE_ROLE_KEY is not configured
 *
 * @example
 * const supabase = getSupabaseClient()
 * const { data, error } = await supabase
 *   .from('Sensors')
 *   .select('*')
 */
export function getSupabaseClient() {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || 'http://kong:8000'
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseKey) {
        throw new Error('SUPABASE_SERVICE_ROLE_KEY not configured')
    }

    return createClient(supabaseUrl, supabaseKey)
}
