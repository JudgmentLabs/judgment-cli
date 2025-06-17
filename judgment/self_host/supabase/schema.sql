

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "timescaledb" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."metric" AS (
	"metric" "text",
	"score" double precision
);


ALTER TYPE "public"."metric" OWNER TO "postgres";


CREATE TYPE "public"."experiment" AS (
	"name" "text",
	"task" "text",
	"metrics" "public"."metric"[],
	"creator" "text",
	"updated_at" timestamp with time zone
);


ALTER TYPE "public"."experiment" OWNER TO "postgres";


CREATE TYPE "public"."role" AS ENUM (
    'admin',
    'developer',
    'owner',
    'viewer'
);


ALTER TYPE "public"."role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_on_demand_judgees"("org_id" "uuid", "count" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE organizations
    SET on_demand_judgees = COALESCE(on_demand_judgees, 0) + count
    WHERE id = org_id;
    
    RETURN FOUND;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."add_on_demand_judgees"("org_id" "uuid", "count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_on_demand_traces"("org_id" "uuid", "count" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE organizations
    SET on_demand_traces = COALESCE(on_demand_traces, 0) + count
    WHERE id = org_id;
    
    RETURN FOUND;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."add_on_demand_traces"("org_id" "uuid", "count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."backfill_token_usage_from_traces"("days_back" integer DEFAULT 30, "batch_size" integer DEFAULT 100) RETURNS TABLE("traces_processed" integer, "traces_skipped" integer, "tokens_updated" bigint, "cost_updated" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_start_date TIMESTAMPTZ;
    v_traces_processed INTEGER := 0;
    v_traces_skipped INTEGER := 0;
    v_tokens_updated BIGINT := 0;
    v_cost_updated DECIMAL(10, 6) := 0;
    v_result JSONB;
    v_trace_id UUID;
    v_trace_ids UUID[];
BEGIN
    -- Calculate the start date
    v_start_date := NOW() - (days_back * INTERVAL '1 day');
    
    -- Get all eligible trace IDs first and store in an array
    SELECT ARRAY_AGG(t.trace_id)
    INTO v_trace_ids
    FROM public.traces t
    JOIN public.projects p ON t.project_id = p.project_id
    JOIN public.organizations o ON p.organization_id = o.id  -- Join with organizations to ensure they exist
    WHERE t.created_at >= v_start_date
    AND t.token_counts IS NOT NULL
    AND jsonb_typeof(t.token_counts) = 'object'
    LIMIT batch_size;
    
    -- Process each trace in the array
    IF v_trace_ids IS NOT NULL THEN
        FOREACH v_trace_id IN ARRAY v_trace_ids
        LOOP
            BEGIN
                -- Process each trace and capture the result
                v_result := public.update_token_usage_from_trace(v_trace_id);
                
                -- Count the trace as processed
                v_traces_processed := v_traces_processed + 1;
                
                -- Add tokens and cost from the result if successful
                IF v_result->'success' = 'true' THEN
                    v_tokens_updated := v_tokens_updated + COALESCE((v_result->'total_tokens')::BIGINT, 0);
                    v_cost_updated := v_cost_updated + COALESCE((v_result->'total_cost')::DECIMAL, 0);
                ELSE
                    -- Count as skipped if not successful
                    v_traces_skipped := v_traces_skipped + 1;
                    RAISE NOTICE 'Skipped trace %: %', v_trace_id, v_result->'message';
                END IF;
            EXCEPTION WHEN OTHERS THEN
                -- Just count as skipped and continue with the next trace
                v_traces_skipped := v_traces_skipped + 1;
                RAISE NOTICE 'Error processing trace %: %', v_trace_id, SQLERRM;
            END;
        END LOOP;
    END IF;
    
    -- Return the results
    RETURN QUERY SELECT v_traces_processed, v_traces_skipped, v_tokens_updated, v_cost_updated;
END;
$$;


ALTER FUNCTION "public"."backfill_token_usage_from_traces"("days_back" integer, "batch_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."batch_update_trace_metadata"("trace_ids_array" "uuid"[], "metadata_json" "jsonb") RETURNS TABLE("trace_id" "uuid", "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  UPDATE traces
  SET 
    metadata = metadata_json,
    updated_at = NOW()
  WHERE trace_id = ANY(trace_ids_array)
  RETURNING trace_id, updated_at;
END;
$$;


ALTER FUNCTION "public"."batch_update_trace_metadata"("trace_ids_array" "uuid"[], "metadata_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_percentiles"("p_values" numeric[]) RETURNS "json"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  sorted_values NUMERIC[];
  n INTEGER;
  result JSON;
BEGIN
  -- Handle empty array
  IF p_values IS NULL OR array_length(p_values, 1) IS NULL THEN
    RETURN json_build_object(
      'p1', 0, 'p25', 0, 'p50', 0, 'p75', 0, 'p95', 0, 'p99', 0,
      'min', 0, 'max', 0, 'avg', 0
    );
  END IF;
  
  -- Sort values
  SELECT array_agg(v ORDER BY v) INTO sorted_values FROM unnest(p_values) AS v;
  SELECT array_length(sorted_values, 1) INTO n;
  
  -- Calculate percentiles
  SELECT json_build_object(
    'p1', sorted_values[GREATEST(1, FLOOR(n * 0.01)::int)],
    'p25', sorted_values[GREATEST(1, FLOOR(n * 0.25)::int)],
    'p50', sorted_values[GREATEST(1, FLOOR(n * 0.50)::int)],
    'p75', sorted_values[GREATEST(1, FLOOR(n * 0.75)::int)],
    'p95', sorted_values[GREATEST(1, FLOOR(n * 0.95)::int)],
    'p99', sorted_values[GREATEST(1, FLOOR(n * 0.99)::int)],
    'min', sorted_values[1],
    'max', sorted_values[n],
    'avg', (SELECT AVG(v) FROM unnest(sorted_values) AS v)
  ) INTO result;
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."calculate_percentiles"("p_values" numeric[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_percentiles"("p_values" "anyarray") RETURNS "json"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  sorted_values NUMERIC[];
  n INTEGER;
  result JSON;
BEGIN
  -- Handle empty array
  IF p_values IS NULL OR array_length(p_values, 1) IS NULL THEN
    RETURN json_build_object(
      'p1', 0, 'p25', 0, 'p50', 0, 'p75', 0, 'p95', 0, 'p99', 0,
      'min', 0, 'max', 0, 'avg', 0
    );
  END IF;
  
  -- Convert input array to numeric array and sort values
  SELECT array_agg(v::NUMERIC ORDER BY v::NUMERIC) INTO sorted_values FROM unnest(p_values) AS v;
  SELECT array_length(sorted_values, 1) INTO n;
  
  -- Calculate percentiles
  SELECT json_build_object(
    'p1', sorted_values[GREATEST(1, FLOOR(n * 0.01)::int)],
    'p25', sorted_values[GREATEST(1, FLOOR(n * 0.25)::int)],
    'p50', sorted_values[GREATEST(1, FLOOR(n * 0.50)::int)],
    'p75', sorted_values[GREATEST(1, FLOOR(n * 0.75)::int)],
    'p95', sorted_values[GREATEST(1, FLOOR(n * 0.95)::int)],
    'p99', sorted_values[GREATEST(1, FLOOR(n * 0.99)::int)],
    'min', sorted_values[1],
    'max', sorted_values[n],
    'avg', (SELECT AVG(v) FROM unnest(sorted_values) AS v)
  ) INTO result;
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."calculate_percentiles"("p_values" "anyarray") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_and_reset_organizations"("days_between_resets" integer DEFAULT 30) RETURNS TABLE("organization_id" "uuid", "was_reset" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    org_record RECORD;
    now_timestamp TIMESTAMPTZ := NOW();
    reset_needed BOOLEAN;
BEGIN
    -- Loop through all organizations
    FOR org_record IN 
        SELECT id, reset_at
        FROM organizations
    LOOP
        -- Initialize return values
        organization_id := org_record.id;
        was_reset := FALSE;
        
        -- Check if reset_at is NULL
        IF org_record.reset_at IS NULL THEN
            -- Set initial reset_at without resetting
            UPDATE organizations
            SET reset_at = now_timestamp
            WHERE id = org_record.id;
            
            -- Return this organization with was_reset = FALSE
            RETURN NEXT;
            CONTINUE;
        END IF;
        
        -- Check if enough days have passed since last reset
        IF (now_timestamp - org_record.reset_at) >= (days_between_resets * INTERVAL '1 day') THEN
            -- Reset organization counts
            UPDATE organizations
            SET judgees_ran = 0,
                traces_ran = 0,
                reset_at = now_timestamp
            WHERE id = org_record.id;
            
            -- Reset user-organization resources for all users in this org
            UPDATE user_org_resources
            SET judgees_ran = 0,
                traces_ran = 0,
                updated_at = now_timestamp,
                last_reset_at = now_timestamp
            WHERE organization_id = org_record.id;
            
            -- Set was_reset to TRUE
            was_reset := TRUE;
        END IF;
        
        -- Return this organization with appropriate was_reset value
        RETURN NEXT;
    END LOOP;
    
    RETURN;
EXCEPTION
    WHEN OTHERS THEN
        -- In case of error, return the error information
        RAISE NOTICE 'Error in check_and_reset_organizations: %', SQLERRM;
        RETURN;
END;
$$;


ALTER FUNCTION "public"."check_and_reset_organizations"("days_between_resets" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_organization_exists"("input_organization_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM organizations o
    WHERE o.id = input_organization_id
  );
END;$$;


ALTER FUNCTION "public"."check_organization_exists"("input_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_user_exists"("email_input" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  return exists (
    select 1
    from auth.users
    where email = email_input
  );
end;
$$;


ALTER FUNCTION "public"."check_user_exists"("email_input" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_default_organization"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  new_org_id UUID;
  user_full_name TEXT;
BEGIN
  -- Get user's name for the organization name
  SELECT CONCAT(NEW.first_name, ' ', CASE WHEN NEW.last_name = 'NULL' THEN '' ELSE NEW.last_name END, '''s Organization') 
  INTO user_full_name;
  
  -- Create a new organization for the user
  INSERT INTO public.organizations (
    name
    -- All other fields will use their default values from the table definition
  ) VALUES (
    user_full_name -- Use user's name in the organization name
  )
  RETURNING id INTO new_org_id;
  
  -- Create the user-organization relationship with 'admin' role
  INSERT INTO public.user_organizations (
    user_id,
    organization_id,
    role
  ) VALUES (
    NEW.id, -- The user_id from the newly inserted user_data row
    new_org_id,
    'admin'::public.role -- Give the user admin role in their personal organization
  );
  
  RAISE NOTICE 'Created organization % for user %', new_org_id, NEW.id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_default_organization"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_on_demand_judgees"("organization_id" "uuid", "decrement_by" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Use advisory lock to prevent race conditions
    PERFORM pg_advisory_xact_lock(hashtext(organization_id::text));
    
    -- Keep the same update logic, just add the lock
    UPDATE organizations
    SET on_demand_judgees = GREATEST(0, on_demand_judgees - decrement_by)
    WHERE id = organization_id;
    
    -- Original function returns void, so maintain that
EXCEPTION
    WHEN OTHERS THEN
        -- Original function doesn't handle errors, so we'll just log
        RAISE WARNING 'Error decrementing on_demand_judgees for org %: %', organization_id, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."decrement_on_demand_judgees"("organization_id" "uuid", "decrement_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_on_demand_traces"("organization_id" "uuid", "decrement_by" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE public.organizations
  SET on_demand_traces = GREATEST(0, on_demand_traces - decrement_by)
  WHERE id = organization_id;
END;
$$;


ALTER FUNCTION "public"."decrement_on_demand_traces"("organization_id" "uuid", "decrement_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_organization_judgees_ran"("organization_id" "uuid", "decrement_by" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE organizations
  SET judgees_ran = GREATEST(0, judgees_ran - decrement_by)
  WHERE id = organization_id;
END;
$$;


ALTER FUNCTION "public"."decrement_organization_judgees_ran"("organization_id" "uuid", "decrement_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_organization_traces_ran"("organization_id" "uuid", "decrement_by" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE organizations
  SET traces_ran = GREATEST(0, traces_ran - decrement_by)
  WHERE id = organization_id;
END;
$$;


ALTER FUNCTION "public"."decrement_organization_traces_ran"("organization_id" "uuid", "decrement_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_user_org_judgees_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
BEGIN
  UPDATE user_org_resources
  SET judgees_ran = GREATEST(0, judgees_ran - decrement_by)
  WHERE user_id = $1 AND organization_id = $2;
END;
$_$;


ALTER FUNCTION "public"."decrement_user_org_judgees_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_user_org_traces_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
BEGIN
  UPDATE user_org_resources
  SET traces_ran = GREATEST(0, traces_ran - decrement_by)
  WHERE user_id = $1 AND organization_id = $2;
END;
$_$;


ALTER FUNCTION "public"."decrement_user_org_traces_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fetch_detailed_trace_errors_by_projects"("project_ids_array" "uuid"[], "start_date" timestamp with time zone DEFAULT NULL::timestamp with time zone, "end_date" timestamp with time zone DEFAULT NULL::timestamp with time zone, "limit_results" integer DEFAULT 1000) RETURNS TABLE("project_id" "uuid", "project_name" "text", "trace_id" "uuid", "trace_name" "text", "span_id" "uuid", "error" "jsonb", "error_type" "text", "error_message" "text", "error_traceback" "text", "created_at" timestamp with time zone, "span_type" "text", "function_name" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.project_name,
        t.trace_id,
        t.name as trace_name,
        ts.span_id,
        ts.error,
        -- Extract error type (simple approach)
        COALESCE(ts.error->>'type', 'Unknown') as error_type,
        -- Extract error message (simple approach)
        COALESCE(ts.error->>'message', 'No message available') as error_message,
        -- Extract traceback (simple approach - just convert to text)
        COALESCE(ts.error->>'traceback', '') as error_traceback,
        ts.created_at,
        ts.span_type,
        ts.function as function_name
    FROM projects p
    JOIN traces t ON p.project_id = t.project_id
    JOIN trace_spans ts ON t.trace_id = ts.trace_id
    WHERE 
        p.project_id = ANY(project_ids_array)
        AND ts.error IS NOT NULL
        AND (start_date IS NULL OR ts.created_at >= start_date)
        AND (end_date IS NULL OR ts.created_at <= end_date)
    ORDER BY ts.created_at DESC
    LIMIT limit_results;
END;
$$;


ALTER FUNCTION "public"."fetch_detailed_trace_errors_by_projects"("project_ids_array" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone, "limit_results" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_auth_users"("user_ids" "uuid"[]) RETURNS TABLE("id" "uuid", "email" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  return query
  select au.id, au.email
  from auth.users au
  where au.id = any(user_ids);
end;
$$;


ALTER FUNCTION "public"."get_auth_users"("user_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_usage_metrics"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") RETURNS TABLE("customer_id" "text", "customer_name" "text", "total_tokens" bigint, "prompt_tokens" bigint, "completion_tokens" bigint, "total_cost" numeric, "trace_count" bigint, "last_activity" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH customer_traces AS (
        SELECT 
            t.customer_id,
            t.trace_id,
            t.created_at,
            t.aggregate_token_usage
        FROM traces t
        WHERE t.project_id = ANY(project_ids_array)
            AND t.created_at >= start_date_iso::timestamp with time zone
            AND t.created_at <= end_date_iso::timestamp with time zone
            AND t.customer_id IS NOT NULL
            AND t.customer_id != ''
    ),
    customer_aggregates AS (
        SELECT 
            ct.customer_id,
            NULL::TEXT as customer_name, -- We don't have customer names in traces table
            COALESCE(SUM((ct.aggregate_token_usage->>'total_tokens')::bigint), 0) as total_tokens,
            COALESCE(SUM((ct.aggregate_token_usage->>'prompt_tokens')::bigint), 0) as prompt_tokens,
            COALESCE(SUM((ct.aggregate_token_usage->>'completion_tokens')::bigint), 0) as completion_tokens,
            COALESCE(SUM((ct.aggregate_token_usage->>'total_cost_usd')::numeric), 0) as total_cost,
            COUNT(ct.trace_id) as trace_count,
            MAX(ct.created_at) as last_activity
        FROM customer_traces ct
        WHERE ct.aggregate_token_usage IS NOT NULL
        GROUP BY ct.customer_id
    )
    SELECT 
        ca.customer_id,
        ca.customer_name,
        ca.total_tokens,
        ca.prompt_tokens,
        ca.completion_tokens,
        ca.total_cost,
        ca.trace_count,
        ca.last_activity
    FROM customer_aggregates ca
    WHERE ca.total_tokens > 0 OR ca.total_cost > 0
    ORDER BY ca.total_cost DESC, ca.total_tokens DESC;
END;
$$;


ALTER FUNCTION "public"."get_customer_usage_metrics"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_summary"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSONB;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN '{}'::JSONB;
  END IF;
  
  -- Calculate summary metrics
  WITH trace_data AS (
    SELECT
      t.trace_id,
      t.created_at,
      COALESCE(t.duration, 0) AS duration,
      COALESCE((t.token_counts->>'prompt_tokens')::FLOAT, 0) AS prompt_tokens,
      COALESCE((t.token_counts->>'completion_tokens')::FLOAT, 0) AS completion_tokens,
      COALESCE((t.token_counts->>'total_tokens')::FLOAT, 0) AS total_tokens,
      0.0 AS cost, -- Placeholder since cost column doesn't exist
      0 AS error_count, -- Placeholder since error_count column doesn't exist
      0 AS tool_calls_count -- Placeholder since tool_calls_count column doesn't exist
    FROM traces t
    WHERE t.project_id = ANY(v_project_ids)
      AND t.created_at >= v_start_date
  )
  SELECT jsonb_build_object(
    'totalTokens', COALESCE(SUM(total_tokens), 0),
    'totalCost', COALESCE(SUM(cost), 0),
    'totalTraces', COUNT(trace_id),
    'totalErrors', COALESCE(SUM(error_count), 0),
    'promptTokens', COALESCE(SUM(prompt_tokens), 0),
    'completionTokens', COALESCE(SUM(completion_tokens), 0),
    'averageTokensPerRun', CASE WHEN COUNT(trace_id) > 0 THEN COALESCE(SUM(total_tokens) / COUNT(trace_id), 0) ELSE 0 END,
    'averageCostPerRun', CASE WHEN COUNT(trace_id) > 0 THEN COALESCE(SUM(cost) / COUNT(trace_id), 0) ELSE 0 END,
    'averageToolCallsPerRun', CASE WHEN COUNT(trace_id) > 0 THEN COALESCE(SUM(tool_calls_count) / COUNT(trace_id), 0) ELSE 0 END
  ) INTO v_result
  FROM trace_data;
  
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_dashboard_summary"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid") RETURNS TABLE("dataset_alias" "text", "is_sequence" boolean)
    LANGUAGE "sql"
    AS $$
    SELECT 
        d.dataset_alias,
        d.is_sequence
    FROM datasets d
    JOIN project_datasets pd ON d.dataset_id = pd.dataset_id
    WHERE pd.project_id = input_project_id;
$$;


ALTER FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid", "input_is_sequence" boolean) RETURNS TABLE("dataset_alias" "text")
    LANGUAGE "sql"
    AS $$
    select d.dataset_alias
    from datasets d
    join project_datasets pd on d.dataset_id = pd.dataset_id
    where pd.project_id = input_project_id
      and d.is_sequence = input_is_sequence;
$$;


ALTER FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid", "input_is_sequence" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_aliases_by_project_and_trace"("input_project_id" "uuid") RETURNS TABLE("dataset_alias" "text", "is_trace" boolean)
    LANGUAGE "sql"
    AS $$
    SELECT 
        d.dataset_alias,
        d.is_trace
    FROM datasets d
    JOIN project_datasets pd ON d.dataset_id = pd.dataset_id
    WHERE pd.project_id = input_project_id;
$$;


ALTER FUNCTION "public"."get_dataset_aliases_by_project_and_trace"("input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_sequence"("input_project_id" "uuid", "input_dataset_alias" "text", "input_root_sequence_id" "uuid") RETURNS SETOF "record"
    LANGUAGE "sql"
    AS $$
    select 
        s.*,
        e.*
    from project_datasets pd
    join datasets d on d.dataset_id = pd.dataset_id
    join sequences s on s.dataset_id = d.dataset_id
    left join examples e on s.sequence_id = e.sequence_id
    where
        pd.project_id = input_project_id and
        d.dataset_alias = input_dataset_alias and
        s.root_sequence_id = input_root_sequence_id
    order by s.sequence_order, e.sequence_order;
$$;


ALTER FUNCTION "public"."get_dataset_sequence"("input_project_id" "uuid", "input_dataset_alias" "text", "input_root_sequence_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_stats"("input_dataset_id" "uuid") RETURNS TABLE("created_at" timestamp with time zone, "updated_at" timestamp with time zone, "example_count" integer, "trace_count" integer, "is_trace" boolean)
    LANGUAGE "plpgsql"
    AS $$BEGIN
    RETURN QUERY
    SELECT
        MIN(d.created_at) AS created_at,
        GREATEST(
            COALESCE(MAX(e.created_at), MIN(d.created_at)),
            COALESCE(MAX(dt.created_at), MIN(d.created_at))
        ) AS updated_at,
        COUNT(DISTINCT e.example_id)::INTEGER AS example_count,
        COUNT(DISTINCT dt.trace_id)::INTEGER AS trace_count,
        BOOL_OR(d.is_trace) AS is_trace
    FROM 
        datasets d
    LEFT JOIN 
        examples e ON d.dataset_id = e.dataset_id
    LEFT JOIN 
        dataset_traces dt ON d.dataset_id = dt.dataset_id
    WHERE
        d.dataset_id = input_dataset_id;
END;$$;


ALTER FUNCTION "public"."get_dataset_stats"("input_dataset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_stats_by_project"("input_project_id" "uuid") RETURNS TABLE("dataset_alias" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "example_count" integer, "sequence_count" integer, "is_sequence" boolean)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.dataset_alias AS dataset_alias,
        MIN(d.created_at) AS created_at,
        GREATEST(MAX(e.created_at), MIN(d.created_at)) AS updated_at,
        COUNT(DISTINCT e.example_id)::INTEGER AS example_count,
        COUNT(DISTINCT s.root_sequence_id)::INTEGER as sequence_count,
        BOOL_OR(d.is_sequence) AS is_sequence
    FROM 
        project_datasets pd
    JOIN 
        datasets d ON pd.dataset_id = d.dataset_id
    LEFT JOIN 
        examples e ON d.dataset_id = e.dataset_id
    LEFT JOIN 
        sequences s ON d.dataset_id = s.dataset_id
    WHERE 
        pd.project_id = input_project_id
    GROUP BY 
        d.dataset_alias, d.dataset_id;
END;
$$;


ALTER FUNCTION "public"."get_dataset_stats_by_project"("input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dataset_stats_by_project_v2"("input_project_id" "uuid") RETURNS TABLE("dataset_alias" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "example_count" integer, "trace_count" integer, "is_trace" boolean)
    LANGUAGE "plpgsql"
    AS $$BEGIN
    RETURN QUERY
    SELECT
        d.dataset_alias AS dataset_alias,
        MIN(d.created_at) AS created_at,
        GREATEST(
            COALESCE(MAX(e.created_at), MIN(d.created_at)),
            COALESCE(MAX(dt.created_at), MIN(d.created_at))
        ) AS updated_at,
        COUNT(DISTINCT e.example_id)::INTEGER AS example_count,
        COUNT(DISTINCT dt.trace_id)::INTEGER AS trace_count,
        BOOL_OR(d.is_trace) AS is_trace
    FROM 
        project_datasets pd
    JOIN 
        datasets d ON pd.dataset_id = d.dataset_id
    LEFT JOIN 
        examples e ON d.dataset_id = e.dataset_id
    LEFT JOIN 
        dataset_traces dt ON d.dataset_id = dt.dataset_id
    WHERE
        pd.project_id = input_project_id
    GROUP BY 
        d.dataset_alias, d.dataset_id;
END;$$;


ALTER FUNCTION "public"."get_dataset_stats_by_project_v2"("input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_examples_for_experiment_run"("project_id_input" "uuid", "experiment_name_input" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    result jsonb;
begin
    select to_jsonb(er) || jsonb_build_object(
        'examples',
        (
            select jsonb_agg(example_with_scores order by example_with_scores->>'created_at')
            from (
                select to_jsonb(e) || jsonb_build_object(
                    'scorer_data',
                    (
                        select jsonb_agg(to_jsonb(sd))
                        from scorer_data sd
                        where sd.example_id = e.example_id
                    )
                ) as example_with_scores
                from examples e
                where e.experiment_run_id = er.id
            ) sub
        )
    )
    into result
    from experiment_runs er
    where er.project_id = project_id_input
      and er.name = experiment_name_input;

    return result;
end;
$$;


ALTER FUNCTION "public"."get_examples_for_experiment_run"("project_id_input" "uuid", "experiment_name_input" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_experiment_runs_by_ids"("experiment_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") RETURNS TABLE("experiment_run_id" "uuid", "experiment_id" "uuid", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "metrics" "jsonb", "status" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    experiment_runs.experiment_run_id,
    experiment_runs.experiment_id,
    experiment_runs.created_at,
    experiment_runs.updated_at,
    experiment_runs.metrics,
    experiment_runs.status
  FROM experiment_runs
  WHERE experiment_runs.experiment_id = ANY(experiment_ids_array)
    AND experiment_runs.created_at >= start_date_iso::timestamp
    AND experiment_runs.created_at <= end_date_iso::timestamp
  ORDER BY experiment_runs.created_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_experiment_runs_by_ids"("experiment_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_experiment_summaries_by_project"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) RETURNS TABLE("name" "text", "created_at" timestamp with time zone, "creator_name" "text", "is_sequence" boolean, "example_count" integer, "sequence_count" integer, "scorers" "jsonb")
    LANGUAGE "sql"
    AS $$
    SELECT
        er.name,
        er.created_at,
        ud.first_name || ' ' || ud.last_name AS creator_name,
        er.is_sequence,

        -- Count examples linked to this experiment_run
        (
            SELECT COUNT(*)
            FROM public.examples e
            WHERE e.experiment_run_id = er.id
        ) AS example_count,

        -- Count root sequences (parent_sequence_id IS NULL)
        (
            SELECT COUNT(*)
            FROM public.sequences s
            WHERE s.experiment_run_id = er.id
              AND s.parent_sequence_id IS NULL
        ) AS sequence_count,

        -- Scorer data grouped by name across both examples and sequences
        (
            SELECT jsonb_object_agg(name, scores)
            FROM (
                SELECT
                    sd.name,
                    jsonb_agg(sd.score) FILTER (WHERE sd.score IS NOT NULL) AS scores
                FROM public.scorer_data sd
                WHERE sd.example_id IN (
                    SELECT e.example_id
                    FROM public.examples e
                    WHERE e.experiment_run_id = er.id
                )
                OR sd.sequence_id IN (
                    SELECT s.sequence_id
                    FROM public.sequences s
                    WHERE s.experiment_run_id = er.id
                     -- AND s.parent_sequence_id IS NULL -- comment this out because we still want scores for sub-sequences
                )
                GROUP BY sd.name
            ) AS scorer_group
        ) AS scorers

    FROM public.experiment_runs er
    JOIN public.user_data ud ON ud.id = er.user_id
    WHERE er.project_id = project_id_input
      AND er.created_at BETWEEN start_timestamp_input AND end_timestamp_input
    ORDER BY er.created_at DESC;
$$;


ALTER FUNCTION "public"."get_experiment_summaries_by_project"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_experiment_summaries_by_project_v2"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) RETURNS TABLE("name" "text", "created_at" timestamp with time zone, "creator_name" "text", "is_trace" boolean, "example_count" integer, "trace_count" integer, "scorers" "jsonb")
    LANGUAGE "sql"
    AS $$
    SELECT
        er.name,
        er.created_at,
        ud.first_name || ' ' || ud.last_name AS creator_name,
        er.is_trace,

        -- Count examples linked directly to this experiment_run
        (
            SELECT COUNT(*)
            FROM public.examples e
            WHERE e.experiment_run_id = er.id
        ) AS example_count,

        -- Count traces linked to this experiment_run
        (
            SELECT COUNT(*)
            FROM public.traces t
            WHERE t.experiment_run_id = er.id
        ) AS trace_count,

        -- Scorer data grouped by name across direct examples and traced examples
        (
            SELECT jsonb_object_agg(name, scores)
            FROM (
                SELECT
                    sd.name,
                    jsonb_agg(sd.score) FILTER (WHERE sd.score IS NOT NULL) AS scores
                FROM public.scorer_data sd
                LEFT JOIN public.examples e ON e.example_id = sd.example_id
                LEFT JOIN public.trace_spans ts ON
                    ts.span_id = COALESCE(e.trace_span_id, sd.trace_span_id)
                LEFT JOIN public.traces t ON t.trace_id = ts.trace_id
                WHERE 
                    (e.experiment_run_id = er.id)
                    OR (t.experiment_run_id = er.id)
                GROUP BY sd.name
            ) grouped_scores
        ) AS scorers
    FROM public.experiment_runs er
    JOIN public.user_data ud ON ud.id = er.user_id
    WHERE er.project_id = project_id_input
      AND er.created_at BETWEEN start_timestamp_input AND end_timestamp_input
    ORDER BY er.created_at DESC;
$$;


ALTER FUNCTION "public"."get_experiment_summaries_by_project_v2"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_experiment_summaries_by_project_v3"("project_id_input" "uuid", "start_timestamp_input" timestamp without time zone, "end_timestamp_input" timestamp without time zone) RETURNS TABLE("name" "text", "created_at" timestamp with time zone, "creator_name" "text", "is_trace" boolean, "example_count" integer, "trace_count" integer, "scorers" "jsonb")
    LANGUAGE "sql"
    AS $$
  SELECT
      er.name,
      er.created_at,
      ud.first_name || ' ' || ud.last_name AS creator_name,
      er.is_trace,

      -- Count examples linked directly to this experiment_run
      (
          SELECT COUNT(*)
          FROM public.examples e
          WHERE e.experiment_run_id = er.id
      ) AS example_count,

      -- Count traces linked to this experiment_run
      (
          SELECT COUNT(*)
          FROM public.traces t
          WHERE t.experiment_run_id = er.id
      ) AS trace_count,

      -- Scorer data grouped by name across direct examples and traced examples
      (
          SELECT jsonb_object_agg(name, scores)
          FROM (
              SELECT
                  sd.name,
                  jsonb_agg(
                      jsonb_build_object(
                          'score', sd.score,
                          'success', sd.success
                      )
                  ) FILTER (WHERE sd.score IS NOT NULL OR sd.success IS NOT NULL) AS scores
              FROM public.scorer_data sd
              LEFT JOIN public.examples e ON e.example_id = sd.example_id
              LEFT JOIN public.trace_spans ts ON
                  ts.span_id = COALESCE(e.trace_span_id, sd.trace_span_id)
              LEFT JOIN public.traces t ON t.trace_id = ts.trace_id
              WHERE 
                  (e.experiment_run_id = er.id)
                  OR (t.experiment_run_id = er.id)
              GROUP BY sd.name
          ) grouped_scores
      ) AS scorers

  FROM public.experiment_runs er
  JOIN public.user_data ud ON ud.id = er.user_id
  WHERE er.project_id = project_id_input
    AND er.created_at BETWEEN start_timestamp_input AND end_timestamp_input
  ORDER BY er.created_at DESC;
$$;


ALTER FUNCTION "public"."get_experiment_summaries_by_project_v3"("project_id_input" "uuid", "start_timestamp_input" timestamp without time zone, "end_timestamp_input" timestamp without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_experiment_summaries_by_project_v4"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) RETURNS TABLE("name" "text", "created_at" timestamp with time zone, "creator_name" "text", "is_trace" boolean, "example_count" bigint, "trace_count" bigint, "scorers" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
    WITH experiment_runs AS (
        SELECT
            er.id,
            er.name,
            er.created_at,
            ud.first_name || ' ' || ud.last_name AS creator_name,
            er.is_trace
        FROM public.experiment_runs er
        JOIN public.user_data ud ON ud.id = er.user_id
        WHERE er.project_id = project_id_input
          AND er.created_at BETWEEN start_timestamp_input AND end_timestamp_input
    ),
    -- Get all scorer data with experiment run mapping in one pass
    base_scorer_data AS (
        SELECT
            CASE 
                WHEN e.experiment_run_id IS NOT NULL THEN e.experiment_run_id
                WHEN t.experiment_run_id IS NOT NULL THEN t.experiment_run_id
            END AS experiment_run_id,
            sd.name AS scorer_name,
            CASE 
                WHEN t.trace_id IS NOT NULL THEN t.trace_id::text  -- Always use trace_id if available
                WHEN e.example_id IS NOT NULL AND e.trace_span_id IS NULL THEN e.example_id::text  -- Only use example_id if not linked to trace
                ELSE sd.example_id::text  -- Fallback
            END AS unit_id,
            sd.score,
            sd.success
        FROM public.scorer_data sd
        LEFT JOIN public.examples e ON e.example_id = sd.example_id
        LEFT JOIN public.trace_spans ts ON ts.span_id = COALESCE(e.trace_span_id, sd.trace_span_id)
        LEFT JOIN public.traces t ON t.trace_id = ts.trace_id
        WHERE (e.experiment_run_id IN (SELECT id FROM experiment_runs))
           OR (t.experiment_run_id IN (SELECT id FROM experiment_runs))
    ),
    -- Aggregate scores by unit (example or trace)
    aggregated_scores AS (
        SELECT
            experiment_run_id,
            scorer_name,
            unit_id,
            AVG(score) AS avg_score,
            CASE 
                WHEN COUNT(CASE WHEN success IS NOT NULL THEN 1 END) = 0 THEN NULL
                WHEN BOOL_AND(success) IS TRUE THEN TRUE
                ELSE FALSE
            END AS aggregated_success
        FROM base_scorer_data
        GROUP BY experiment_run_id, scorer_name, unit_id
    ),
    -- Get all unique units per experiment for proper indexing
    experiment_units AS (
        SELECT 
            experiment_run_id,
            unit_id,
            ROW_NUMBER() OVER (PARTITION BY experiment_run_id ORDER BY unit_id) AS unit_index
        FROM (
            SELECT DISTINCT experiment_run_id, unit_id
            FROM aggregated_scores
        ) distinct_units
    ),
    -- Get all unique scorers per experiment
    experiment_scorers AS (
        SELECT DISTINCT experiment_run_id, scorer_name
        FROM aggregated_scores
    ),
    -- Create complete matrix with null padding
    complete_matrix AS (
        SELECT 
            eu.experiment_run_id,
            es.scorer_name,
            eu.unit_id,
            eu.unit_index,
            ags.avg_score,
            ags.aggregated_success
        FROM experiment_units eu
        CROSS JOIN experiment_scorers es
        LEFT JOIN aggregated_scores ags ON 
            ags.experiment_run_id = eu.experiment_run_id
            AND ags.unit_id = eu.unit_id 
            AND ags.scorer_name = es.scorer_name
        WHERE eu.experiment_run_id = es.experiment_run_id
    ),
    -- Build aligned scorer arrays
    scorer_arrays AS (
        SELECT 
            experiment_run_id,
            scorer_name,
            jsonb_agg(
                CASE 
                    WHEN avg_score IS NOT NULL OR aggregated_success IS NOT NULL 
                    THEN jsonb_build_object('score', avg_score, 'success', aggregated_success)
                    ELSE jsonb_build_object('score', null, 'success', null)
                END 
                ORDER BY unit_index
            ) AS scores
        FROM complete_matrix
        GROUP BY experiment_run_id, scorer_name
    ),
    -- Build final scorer objects
    final_scorers AS (
        SELECT 
            experiment_run_id,
            jsonb_object_agg(scorer_name, scores) AS scorers
        FROM scorer_arrays
        GROUP BY experiment_run_id
    )
    SELECT
        er.name,
        er.created_at,
        er.creator_name,
        er.is_trace,
        -- Count examples linked directly to this experiment_run
        (SELECT COUNT(*) FROM public.examples e WHERE e.experiment_run_id = er.id) AS example_count,
        -- Count traces linked to this experiment_run  
        (SELECT COUNT(*) FROM public.traces t WHERE t.experiment_run_id = er.id) AS trace_count,
        COALESCE(fs.scorers, '{}'::jsonb) AS scorers
    FROM experiment_runs er
    LEFT JOIN final_scorers fs ON fs.experiment_run_id = er.id
    ORDER BY er.created_at DESC;
$$;


ALTER FUNCTION "public"."get_experiment_summaries_by_project_v4"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_experiments_by_project"("input_project_id" "uuid") RETURNS SETOF "public"."experiment"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH metrics AS (
        SELECT
            sq.name AS name,
            ARRAY_AGG(ROW(sq.metric, sq.score)::metric) AS metrics
        FROM
            (
                SELECT
                    er.eval_result_run AS name,
                    sd->>'name' AS metric,
                    AVG((sd->>'score')::FLOAT) AS score
                FROM 
                    eval_results er
                JOIN
                    LATERAL jsonb_array_elements(er.result->'scorers_data') AS sd ON jsonb_typeof(er.result->'scorers_data') = 'array'
                WHERE
                    er.project_id = input_project_id
                GROUP BY
                    er.eval_result_run,
                    sd->>'name'
                ORDER BY
                    sd->>'name'
            ) AS sq
        GROUP BY
            sq.name
    ),
    updated_at AS (
        SELECT
            er.eval_result_run AS name,
            MAX(er.created_at) AS updated_at
        FROM
            eval_results er
        WHERE
            er.project_id = input_project_id
        GROUP BY
            er.eval_result_run
    )
    SELECT DISTINCT ON (er.eval_result_run)
        er.eval_result_run::TEXT AS name,
        COALESCE((string_to_array(er.eval_result_run, '/'))[2], 'default') AS task,
        m.metrics AS metrics,
        ud.first_name || ' ' || ud.last_name AS creator,
        ua.updated_at AS updated_at
    FROM
        eval_results er
    JOIN
        user_data ud ON ud.id = er.user_id
    JOIN
        metrics m ON m.name = er.eval_result_run
    JOIN
        updated_at ua ON ua.name = er.eval_result_run
    WHERE
        er.project_id = input_project_id;
END;
$$;


ALTER FUNCTION "public"."get_experiments_by_project"("input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_latency_metrics"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "json"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSON;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN json_build_object(
      'trace_latency', '[]'::json,
      'llm_latency', '[]'::json,
      'tool_latency', '[]'::json,
      'trace_percentiles', '{}'::json,
      'llm_percentiles', '{}'::json,
      'tool_percentiles', '{}'::json
    );
  END IF;
  
  -- Get trace latency data
  WITH trace_data AS (
    SELECT
      t.trace_id,
      t.created_at,
      t.duration * 1000 AS latency, -- Multiply by 1000 for frontend display
      p.project_name
    FROM traces t
    JOIN projects p ON t.project_id = p.project_id
    WHERE t.project_id = ANY(v_project_ids)
      AND t.created_at >= v_start_date
      AND t.duration IS NOT NULL
    ORDER BY t.created_at
    LIMIT 10000 -- Set a high limit to effectively get all data
  ),
  llm_data AS (
    SELECT
      ts.trace_id,
      ts.created_at,
      ts.duration * 1000 AS latency, -- Multiply by 1000 for frontend display
      COALESCE(ts.function, 'Unknown') AS function
    FROM trace_spans ts
    JOIN traces t ON ts.trace_id = t.trace_id
    WHERE t.project_id = ANY(v_project_ids)
      AND ts.created_at >= v_start_date
      AND ts.span_type = 'llm'
      AND ts.duration IS NOT NULL
    ORDER BY ts.created_at
    LIMIT 10000 -- Set a high limit to effectively get all data
  ),
  tool_data AS (
    SELECT
      ts.trace_id,
      ts.created_at,
      ts.duration * 1000 AS latency, -- Multiply by 1000 for frontend display
      ts.span_type AS tool_type,
      COALESCE(ts.function, 'Unknown') AS function
    FROM trace_spans ts
    JOIN traces t ON ts.trace_id = t.trace_id
    WHERE t.project_id = ANY(v_project_ids)
      AND ts.created_at >= v_start_date
      AND ts.span_type = 'tool'
      AND ts.duration IS NOT NULL
    ORDER BY ts.created_at
    LIMIT 10000 -- Set a high limit to effectively get all data
  ),
  trace_durations AS (
    SELECT array_agg(latency) AS values FROM trace_data
  ),
  llm_durations AS (
    SELECT array_agg(latency) AS values FROM llm_data
  ),
  tool_types AS (
    SELECT DISTINCT tool_type FROM tool_data
  ),
  tool_percentiles AS (
    SELECT
      tt.tool_type,
      calculate_percentiles(ARRAY(
        SELECT td.latency
        FROM tool_data td
        WHERE td.tool_type = tt.tool_type
      )) AS percentiles
    FROM tool_types tt
  )
  
  SELECT json_build_object(
    'trace_latency', COALESCE((
      SELECT json_agg(
        json_build_object(
          'timestamp', created_at,
          'latency', latency,
          'trace_id', trace_id,
          'project_name', project_name
        )
      )
      FROM trace_data
    ), '[]'::json),
    'llm_latency', COALESCE((
      SELECT json_agg(
        json_build_object(
          'timestamp', created_at,
          'latency', latency,
          'trace_id', trace_id,
          'function', function
        )
      )
      FROM llm_data
    ), '[]'::json),
    'tool_latency', COALESCE((
      SELECT json_agg(
        json_build_object(
          'timestamp', created_at,
          'latency', latency,
          'trace_id', trace_id,
          'tool_type', tool_type,
          'function', function
        )
      )
      FROM tool_data
    ), '[]'::json),
    'trace_percentiles', COALESCE((
      SELECT calculate_percentiles(values) FROM trace_durations
    ), '{}'::json),
    'llm_percentiles', COALESCE((
      SELECT calculate_percentiles(values) FROM llm_durations
    ), '{}'::json),
    'tool_percentiles', COALESCE((
      SELECT json_object_agg(
        tool_type,
        percentiles
      )
      FROM tool_percentiles
    ), '{}'::json)
  ) INTO v_result;
  
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_latency_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid") RETURNS TABLE("eval_result_run" "text")
    LANGUAGE "sql"
    AS $$
    select eval_result_run
    from eval_results
    where project_id = project
    group by eval_result_run
    order by max(created_at) desc
    limit 10;
$$;


ALTER FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid", "run_limit" integer) RETURNS TABLE("eval_result_run" "text")
    LANGUAGE "sql"
    AS $$
    select eval_result_run
    from eval_results
    where project_id = project
    group by eval_result_run
    order by max(created_at) desc
    limit run_limit;
$$;


ALTER FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid", "run_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_llm_span_details"("trace_ids_array" "uuid"[], "start_date_iso" "text") RETURNS TABLE("inputs" "jsonb", "span_id" "uuid", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    trace_spans.inputs,
    trace_spans.span_id,
    trace_spans.created_at
  FROM trace_spans
  WHERE trace_id = ANY(trace_ids_array)
    AND span_type = 'llm'
    AND trace_spans.created_at >= start_date_iso::timestamp
  ORDER BY trace_spans.created_at ASC;
END;
$$;


ALTER FUNCTION "public"."get_llm_span_details"("trace_ids_array" "uuid"[], "start_date_iso" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."trace_spans" (
    "span_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parent_span_id" "uuid",
    "created_at" timestamp with time zone,
    "function" "text",
    "depth" integer,
    "span_type" "text",
    "inputs" "jsonb",
    "output" "jsonb",
    "duration" double precision,
    "trace_id" "uuid",
    "annotation" "jsonb",
    "additional_metadata" "jsonb",
    "agent_name" "text",
    "error" "jsonb",
    "expected_tools" "jsonb",
    "has_evaluation" boolean DEFAULT false NOT NULL,
    "state_after" "jsonb",
    "state_before" "jsonb"
);


ALTER TABLE "public"."trace_spans" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_llm_spans_by_trace_ids"("trace_ids_array" "uuid"[], "start_date_iso" "text", "span_type_filter" "text") RETURNS SETOF "public"."trace_spans"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM trace_spans
  WHERE trace_id = ANY(trace_ids_array)
    AND span_type = span_type_filter
    AND trace_spans.created_at >= start_date_iso::timestamp;
END;
$$;


ALTER FUNCTION "public"."get_llm_spans_by_trace_ids"("trace_ids_array" "uuid"[], "start_date_iso" "text", "span_type_filter" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_llm_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSONB;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN '{}'::JSONB;
  END IF;
  
  -- Calculate LLM usage metrics
  WITH llm_data AS (
    SELECT
      t.trace_id,
      t.created_at,
      COALESCE((t.token_counts->>'total_tokens')::FLOAT, 0) AS total_tokens,
      0.0 AS cost, -- Placeholder since cost column doesn't exist
      COALESCE((t.entries->>'model')::TEXT, 'unknown') AS model -- Extract model from entries JSONB
    FROM traces t
    WHERE t.project_id = ANY(v_project_ids)
      AND t.created_at >= v_start_date
  ),
  daily_data AS (
    SELECT
      DATE_TRUNC('day', created_at) AS day,
      SUM(total_tokens) AS tokens,
      SUM(cost) AS cost
    FROM llm_data
    GROUP BY DATE_TRUNC('day', created_at)
    ORDER BY DATE_TRUNC('day', created_at)
  ),
  hourly_data AS (
    SELECT
      DATE_TRUNC('hour', created_at) AS hour,
      SUM(total_tokens) AS tokens,
      SUM(cost) AS cost
    FROM llm_data
    GROUP BY DATE_TRUNC('hour', created_at)
    ORDER BY DATE_TRUNC('hour', created_at)
  ),
  model_data AS (
    SELECT
      model,
      COUNT(*) AS count,
      SUM(total_tokens) AS tokens,
      SUM(cost) AS cost
    FROM llm_data
    GROUP BY model
    ORDER BY COUNT(*) DESC
  )
  SELECT jsonb_build_object(
    'totalTokens', COALESCE(SUM(total_tokens), 0),
    'totalCost', COALESCE(SUM(cost), 0),
    'byDay', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'day', day,
          'tokens', tokens,
          'cost', cost
        )
      ) FROM daily_data),
      '[]'::jsonb
    ),
    'byHour', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'hour', hour,
          'tokens', tokens,
          'cost', cost
        )
      ) FROM hourly_data),
      '[]'::jsonb
    ),
    'models', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'model', model,
          'count', count,
          'tokens', tokens,
          'cost', cost
        )
      ) FROM model_data),
      '[]'::jsonb
    )
  ) INTO v_result
  FROM llm_data;
  
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_llm_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_organization_members"("org_id" "uuid") RETURNS TABLE("user_id" "uuid", "email" "text", "first_name" "text", "last_name" "text", "role" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    return query
    select 
        uo.user_id,
        ud.user_email as email,
        ud.first_name,
        ud.last_name,
        uo.role::text,
        uo.created_at
    from user_organizations uo
    left join user_data ud on ud.id = uo.user_id
    where uo.organization_id = org_id;
end;
$$;


ALTER FUNCTION "public"."get_organization_members"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_organization_token_usage"("org_id" "uuid") RETURNS TABLE("total_tokens" bigint, "prompt_tokens" bigint, "completion_tokens" bigint, "total_cost" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(uor.total_tokens), 0) as total_tokens,
        COALESCE(SUM(uor.prompt_tokens), 0) as prompt_tokens,
        COALESCE(SUM(uor.completion_tokens), 0) as completion_tokens,
        COALESCE(SUM(uor.total_cost), 0.0) as total_cost
    FROM
        user_org_resources uor
    WHERE
        uor.organization_id = org_id;
END;
$$;


ALTER FUNCTION "public"."get_organization_token_usage"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_id"("input_project_name" "text", "input_organization_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    output_project_id UUID;
BEGIN
    SELECT
        p.project_id INTO output_project_id
    FROM
        projects p
    WHERE
        p.project_name = input_project_name AND
        p.organization_id = input_organization_id;
    RETURN output_project_id;
END;
$$;


ALTER FUNCTION "public"."get_project_id"("input_project_name" "text", "input_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_ids_for_org"("p_organization_id" "uuid", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "uuid"[]
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  project_ids UUID[];
BEGIN
  IF p_project_name IS NULL THEN
    SELECT array_agg(project_id) INTO project_ids
    FROM projects
    WHERE organization_id = p_organization_id;
  ELSE
    SELECT array_agg(project_id) INTO project_ids
    FROM projects
    WHERE organization_id = p_organization_id
      AND project_name = p_project_name;
  END IF;
  
  RETURN project_ids;
END;
$$;


ALTER FUNCTION "public"."get_project_ids_for_org"("p_organization_id" "uuid", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_stats"("org_id" "uuid", "u_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("project_id" "uuid", "project_name" "text", "first_name" "text", "last_name" "text", "updated_at" timestamp with time zone, "total_eval_runs" integer, "total_traces" integer)
    LANGUAGE "plpgsql"
    AS $$BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.project_name,
        u.first_name,
        u.last_name,
        COALESCE(GREATEST(MAX(er.created_at), MAX(t.created_at)), p.created_at) AS updated_at,-- Use GREATEST to get the maximum timestamp from
        COUNT(DISTINCT er.eval_result_run)::INTEGER AS total_eval_runs,
        COUNT(DISTINCT t.trace_id)::INTEGER AS total_traces
    FROM 
        projects p
    LEFT JOIN 
        eval_results er ON p.project_id = er.project_id
    LEFT JOIN 
        traces t ON p.project_id = t.project_id
    LEFT JOIN 
        user_data u ON p.creator_id = u.id
    WHERE 
        p.organization_id = org_id -- Removed the condition AND (u_id IS NULL OR p.creator_id = u_id)
    GROUP BY 
        p.project_id, p.project_name, u.first_name, u.last_name;
END;$$;


ALTER FUNCTION "public"."get_project_stats"("org_id" "uuid", "u_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_summaries"("org_id" "uuid") RETURNS TABLE("project_id" "uuid", "project_name" "text", "first_name" "text", "last_name" "text", "updated_at" timestamp with time zone, "total_experiment_runs" integer, "total_traces" integer)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.project_name,
        u.first_name,
        u.last_name,
        COALESCE(GREATEST(MAX(er.created_at), MAX(t.created_at)), p.created_at) AS updated_at,
        COUNT(DISTINCT er.id)::INTEGER AS total_experiment_runs,
        COUNT(DISTINCT t.trace_id)::INTEGER AS total_traces
    FROM 
        projects p
    LEFT JOIN 
        experiment_runs er ON p.project_id = er.project_id
    LEFT JOIN 
        traces t ON p.project_id = t.project_id
    LEFT JOIN 
        user_data u ON p.creator_id = u.id
    WHERE 
        p.organization_id = org_id
    GROUP BY 
        p.project_id, p.project_name, u.first_name, u.last_name;
END;
$$;


ALTER FUNCTION "public"."get_project_summaries"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_summaries_v2"("org_id" "uuid") RETURNS TABLE("project_id" "uuid", "project_name" "text", "first_name" "text", "last_name" "text", "updated_at" timestamp with time zone, "total_experiment_runs" integer, "total_traces" integer)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.project_name,
        u.first_name,
        u.last_name,
        COALESCE(GREATEST(MAX(er.created_at), MAX(t.created_at)), p.created_at) AS updated_at,
        COUNT(DISTINCT er.id)::INTEGER AS total_experiment_runs,
        COUNT(DISTINCT t.trace_id) FILTER (WHERE t.offline_mode = FALSE)::INTEGER AS total_traces
    FROM 
        projects p
    LEFT JOIN 
        experiment_runs er ON p.project_id = er.project_id
    LEFT JOIN 
        traces t ON p.project_id = t.project_id
    LEFT JOIN 
        user_data u ON p.creator_id = u.id
    WHERE 
        p.organization_id = org_id
    GROUP BY 
        p.project_id, p.project_name, u.first_name, u.last_name;
END;
$$;


ALTER FUNCTION "public"."get_project_summaries_v2"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_summaries_v3"("org_id" "uuid") RETURNS TABLE("project_id" "uuid", "project_name" "text", "first_name" "text", "last_name" "text", "updated_at" timestamp with time zone, "total_experiment_runs" integer, "total_datasets" integer, "total_traces" integer)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.project_id,
        p.project_name,
        u.first_name,
        u.last_name,
        COALESCE(GREATEST(MAX(er.created_at), MAX(t.created_at)), p.created_at) AS updated_at,
        COUNT(DISTINCT er.id)::INTEGER AS total_experiment_runs,
        COUNT(DISTINCT pd.dataset_id)::INTEGER AS total_datasets,
        COUNT(DISTINCT t.trace_id) FILTER (WHERE t.offline_mode = FALSE)::INTEGER AS total_traces
    FROM 
        projects p
    LEFT JOIN 
        experiment_runs er ON p.project_id = er.project_id
    LEFT JOIN 
        traces t ON p.project_id = t.project_id
    LEFT JOIN 
        user_data u ON p.creator_id = u.id
    LEFT JOIN
        project_datasets pd on p.project_id = pd.project_id
    WHERE 
        p.organization_id = org_id
    GROUP BY 
        p.project_id, p.project_name, u.first_name, u.last_name;
END;
$$;


ALTER FUNCTION "public"."get_project_summaries_v3"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSONB;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN '[]'::JSONB;
  END IF;
  
  -- Calculate project usage metrics
  WITH project_data AS (
    SELECT
      p.project_id,
      p.project_name,
      COUNT(t.trace_id) AS trace_count,
      COALESCE(SUM((t.token_counts->>'total_tokens')::FLOAT), 0) AS total_tokens,
      0.0 AS total_cost -- Placeholder since cost column doesn't exist
    FROM projects p
    LEFT JOIN traces t ON p.project_id = t.project_id AND t.created_at >= v_start_date
    WHERE p.project_id = ANY(v_project_ids)
    GROUP BY p.project_id, p.project_name
    ORDER BY COUNT(t.trace_id) DESC
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'projectId', project_id,
      'projectName', project_name,
      'traceCount', trace_count,
      'totalTokens', total_tokens,
      'totalCost', total_cost
    )
  ) INTO v_result
  FROM project_data;
  
  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;


ALTER FUNCTION "public"."get_project_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_root_sequences_summary"("input_dataset_id" "uuid") RETURNS TABLE("root_sequence_id" "uuid", "root_sequence_name" "text", "latest_created_at" timestamp with time zone)
    LANGUAGE "sql"
    AS $$
    select 
        s.root_sequence_id,
        max(case when s.sequence_id = s.root_sequence_id then s.name end) as root_sequence_name,
        max(s.created_at) as latest_created_at
    from 
        sequences s
    where 
        s.dataset_id = input_dataset_id
    group by 
        s.root_sequence_id
$$;


ALTER FUNCTION "public"."get_root_sequences_summary"("input_dataset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_slack_team_ids_for_user"("user_uuid" "uuid") RETURNS TABLE("team_id" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT sc.team_id
    FROM slack_configs sc
    WHERE sc.user_id = user_uuid;
END;
$$;


ALTER FUNCTION "public"."get_slack_team_ids_for_user"("user_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_spans_by_trace_ids"("trace_ids" "uuid"[]) RETURNS TABLE("span_id" "uuid", "trace_id" "uuid", "span_type" "text", "created_at" timestamp with time zone, "inputs" "jsonb", "outputs" "jsonb", "function" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ts.span_id,
    ts.trace_id,
    ts.span_type,
    ts.created_at,
    ts.inputs,
    ts.outputs,
    ts.function
  FROM trace_spans ts
  WHERE ts.trace_id = ANY(trace_ids)
  AND ts.span_type = 'llm';
END;
$$;


ALTER FUNCTION "public"."get_spans_by_trace_ids"("trace_ids" "uuid"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_start_date_from_time_range"("p_time_range" "text") RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_now TIMESTAMP WITH TIME ZONE := now();
  v_start_date TIMESTAMP WITH TIME ZONE;
BEGIN
  CASE p_time_range
    WHEN '1h' THEN
      v_start_date := v_now - INTERVAL '1 hour';
    WHEN '24h' THEN
      v_start_date := v_now - INTERVAL '1 day';
    WHEN '7d' THEN
      v_start_date := v_now - INTERVAL '7 days';
    WHEN '30d' THEN
      v_start_date := v_now - INTERVAL '30 days';
    WHEN 'all' THEN
      v_start_date := v_now - INTERVAL '10 years'; -- Effectively "all time"
    ELSE
      v_start_date := v_now - INTERVAL '7 days'; -- Default to 7 days
  END CASE;
  
  RETURN v_start_date;
END;
$$;


ALTER FUNCTION "public"."get_start_date_from_time_range"("p_time_range" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_token_breakdown_metrics"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSONB;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN '{}'::JSONB;
  END IF;
  
  -- Calculate token breakdown metrics
  WITH token_data AS (
    SELECT
      t.trace_id,
      t.created_at,
      COALESCE((t.entries->>'model')::TEXT, 'unknown') AS model, -- Extract model from entries JSONB
      COALESCE((t.token_counts->>'prompt_tokens')::FLOAT, 0) AS prompt_tokens,
      COALESCE((t.token_counts->>'completion_tokens')::FLOAT, 0) AS completion_tokens,
      COALESCE((t.token_counts->>'total_tokens')::FLOAT, 0) AS total_tokens,
      0.0 AS cost -- Placeholder since cost column doesn't exist
    FROM traces t
    WHERE t.project_id = ANY(v_project_ids)
      AND t.created_at >= v_start_date
  ),
  model_data AS (
    SELECT
      model,
      SUM(prompt_tokens) AS prompt_tokens,
      SUM(completion_tokens) AS completion_tokens,
      SUM(total_tokens) AS total_tokens,
      SUM(cost) AS cost
    FROM token_data
    GROUP BY model
    ORDER BY SUM(total_tokens) DESC
  ),
  daily_data AS (
    SELECT
      DATE_TRUNC('day', created_at) AS day,
      SUM(prompt_tokens) AS prompt_tokens,
      SUM(completion_tokens) AS completion_tokens,
      SUM(total_tokens) AS total_tokens,
      SUM(cost) AS cost
    FROM token_data
    GROUP BY DATE_TRUNC('day', created_at)
    ORDER BY DATE_TRUNC('day', created_at)
  ),
  summary_data AS (
    SELECT
      SUM(prompt_tokens) AS prompt_tokens,
      SUM(completion_tokens) AS completion_tokens,
      SUM(total_tokens) AS total_tokens,
      SUM(cost) AS cost
    FROM token_data
  )
  SELECT jsonb_build_object(
    'byModel', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'model', model,
          'promptTokens', prompt_tokens,
          'completionTokens', completion_tokens,
          'totalTokens', total_tokens,
          'cost', cost
        )
      ) FROM model_data),
      '[]'::jsonb
    ),
    'byDay', COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'day', day,
          'promptTokens', prompt_tokens,
          'completionTokens', completion_tokens,
          'totalTokens', total_tokens,
          'cost', cost
        )
      ) FROM daily_data),
      '[]'::jsonb
    ),
    'usedModels', COALESCE(
      (SELECT jsonb_agg(DISTINCT model) FROM token_data),
      '[]'::jsonb
    ),
    'summary', COALESCE(
      (SELECT jsonb_build_object(
        'promptTokens', prompt_tokens,
        'completionTokens', completion_tokens,
        'totalTokens', total_tokens,
        'cost', cost
      ) FROM summary_data),
      '{}'::jsonb
    )
  ) INTO v_result;
  
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_token_breakdown_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_token_usage_by_span_ids"("span_ids" "uuid"[]) RETURNS TABLE("id" "uuid", "trace_span_id" "uuid", "prompt_tokens" integer, "completion_tokens" integer, "total_tokens" integer, "model" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    tu.id,
    tu.trace_span_id,
    tu.prompt_tokens,
    tu.completion_tokens,
    tu.total_tokens,
    tu.model,
    tu.created_at
  FROM token_usage tu
  WHERE tu.trace_span_id = ANY(span_ids);
END;
$$;


ALTER FUNCTION "public"."get_token_usage_by_span_ids"("span_ids" "uuid"[]) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."trace_span_token_usage" (
    "trace_span_id" "uuid" NOT NULL,
    "prompt_tokens" integer DEFAULT 0,
    "completion_tokens" integer DEFAULT 0,
    "total_tokens" integer DEFAULT 0,
    "prompt_tokens_cost_usd" numeric(10,6) DEFAULT 0,
    "completion_tokens_cost_usd" numeric(10,6) DEFAULT 0,
    "total_cost_usd" numeric(10,6) DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "model_name" "text"
);


ALTER TABLE "public"."trace_span_token_usage" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_token_usage_for_spans"("span_ids_array" "uuid"[], "start_date_iso" "text") RETURNS SETOF "public"."trace_span_token_usage"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM trace_span_token_usage
  WHERE trace_span_id = ANY(span_ids_array)
    AND trace_span_token_usage.created_at >= start_date_iso::timestamp
  ORDER BY trace_span_token_usage.created_at ASC;
END;
$$;


ALTER FUNCTION "public"."get_token_usage_for_spans"("span_ids_array" "uuid"[], "start_date_iso" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tokens_for_user"("user_id" "uuid") RETURNS "json"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    access_token text;
    refresh_token text;
    now_epoch numeric := extract(epoch from now());
    access_expires numeric := now_epoch + 3600;    -- Access token expires in 1 hour
    refresh_expires numeric := now_epoch + 604800; -- Refresh token expires in 7 days
    secret text := current_setting('jwt.secret', true);
BEGIN
    -- Generate the access token with standard claims:
    access_token := extensions.sign(
       json_build_object(
         'sub', user_id,
         'iat', now_epoch,
         'exp', access_expires
       )::json,   -- must be JSON, not text
       secret,
       'HS256'    -- algorithm name
    );
    
    -- Generate the refresh token; include a claim to distinguish its type.
    refresh_token := extensions.sign(
       json_build_object(
         'sub', user_id,
         'iat', now_epoch,
         'exp', refresh_expires,
         'type', 'refresh'
       )::json,   -- must be JSON
       secret,
       'HS256'
    );

    RETURN json_build_object(
         'access_token', access_token,
         'refresh_token', refresh_token,
         'expires_in', 3600
    );
END;
$$;


ALTER FUNCTION "public"."get_tokens_for_user"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tool_spans_by_trace_ids"("trace_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) RETURNS TABLE("span_id" "uuid", "span_type" "text", "created_at" timestamp with time zone, "trace_id" "uuid", "function" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ts.span_id,
    ts.span_type,
    ts.created_at,
    ts.trace_id,
    ts.function
  FROM trace_spans ts
  WHERE ts.trace_id = ANY(trace_ids)
  AND ts.span_type = 'tool'
  AND ts.created_at >= start_date
  AND ts.created_at <= end_date;
END;
$$;


ALTER FUNCTION "public"."get_tool_spans_by_trace_ids"("trace_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tool_usage_for_traces"("trace_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") RETURNS TABLE("span_id" "uuid", "span_type" "text", "created_at" timestamp with time zone, "trace_id" "uuid", "function" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    trace_spans.span_id,
    trace_spans.span_type,
    trace_spans.created_at,
    trace_spans.trace_id,
    trace_spans.function
  FROM trace_spans
  WHERE trace_spans.trace_id = ANY(trace_ids_array)
    AND trace_spans.span_type = 'tool'
    AND trace_spans.created_at >= start_date_iso::timestamp
    AND trace_spans.created_at <= end_date_iso::timestamp;
END;
$$;


ALTER FUNCTION "public"."get_tool_usage_for_traces"("trace_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tool_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSONB;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN '[]'::JSONB;
  END IF;
  
  -- Calculate tool usage metrics
  WITH tool_data AS (
    SELECT
      ts.function AS tool_name,
      COUNT(*) AS call_count,
      AVG(ts.duration) * 1000 AS avg_latency,
      0 AS error_count -- Using 0 as placeholder since error column doesn't exist
    FROM trace_spans ts
    JOIN traces t ON ts.trace_id = t.trace_id
    WHERE t.project_id = ANY(v_project_ids)
      AND ts.created_at >= v_start_date
      AND ts.span_type = 'tool'
      AND ts.function IS NOT NULL
    GROUP BY ts.function
    ORDER BY COUNT(*) DESC
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'toolName', tool_name,
      'callCount', call_count,
      'avgLatency', avg_latency,
      'errorCount', error_count,
      'errorRate', CASE WHEN call_count > 0 THEN (error_count::float / call_count) * 100 ELSE 0 END
    )
  ) INTO v_result
  FROM tool_data;
  
  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;


ALTER FUNCTION "public"."get_tool_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_aggregates"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result_json JSONB;
BEGIN
    WITH per_trace AS (
        SELECT
            t.trace_id,
            t.duration,
            t.name AS trace_name,
            t.created_at,
            t.has_notification,
            t.token_counts,
            ud.first_name,
            ud.last_name,
            scored.scores
        FROM traces t
        JOIN user_data ud ON t.user_id = ud.id
        LEFT JOIN LATERAL (
            SELECT 
                jsonb_object_agg(sc.scorer_name, jsonb_build_object(
                    'mean', sc.avg_score,
                    'median', sc.median_score,
                    'max', sc.max_score,
                    'min', sc.min_score,
                    'raw_scores', sc.raw_scores
                )) AS scores
            FROM (
                SELECT
                    scorer->>'name' AS scorer_name,
                    AVG((scorer->>'score')::numeric) AS avg_score,
                    percentile_cont(0.5) WITHIN GROUP (ORDER BY (scorer->>'score')::numeric) AS median_score,
                    MAX((scorer->>'score')::numeric) AS max_score,
                    MIN((scorer->>'score')::numeric) AS min_score,
                    jsonb_agg((scorer->>'score')::numeric) AS raw_scores
                FROM trace_spans ts
                JOIN eval_results er ON ts.span_id = er.trace_span_id
                CROSS JOIN LATERAL jsonb_array_elements(er.result->'scorers_data') AS scorer
                WHERE ts.trace_id = t.trace_id
                GROUP BY scorer->>'name'
            ) AS sc
        ) scored ON TRUE
        WHERE t.project_id = input_project_id
          AND t.created_at BETWEEN start_time AND end_time
    )
    SELECT jsonb_object_agg(
             pt.trace_id,
             jsonb_build_object(
               'trace_name', pt.trace_name,
               'latency', pt.duration,
               'timestamp', pt.created_at,
               'has_notification', pt.has_notification,
               'token_counts', pt.token_counts,
               'creator', pt.first_name || ' ' || pt.last_name,
               'scores', pt.scores
             )
           )
    INTO result_json
    FROM per_trace pt;
    
    RETURN result_json;
END;
$$;


ALTER FUNCTION "public"."get_trace_aggregates"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_spans_paginated"("trace_ids_array" "uuid"[], "span_type_filter" "text" DEFAULT NULL::"text", "start_date_iso" "text" DEFAULT NULL::"text", "limit_val" integer DEFAULT 1000, "offset_val" integer DEFAULT 0) RETURNS TABLE("span_id" "uuid", "trace_id" "uuid", "span_type" "text", "name" "text", "created_at" timestamp with time zone, "duration" double precision, "function" "text", "inputs" "jsonb", "outputs" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    trace_spans.span_id,
    trace_spans.trace_id,
    trace_spans.span_type,
    trace_spans.name,
    trace_spans.created_at,
    trace_spans.duration,
    trace_spans.function,
    trace_spans.inputs,
    trace_spans.outputs
  FROM trace_spans
  WHERE trace_spans.trace_id = ANY(trace_ids_array)
    AND (span_type_filter IS NULL OR trace_spans.span_type = span_type_filter)
    AND (start_date_iso IS NULL OR trace_spans.created_at >= start_date_iso::timestamp)
  ORDER BY trace_spans.created_at ASC
  LIMIT limit_val
  OFFSET offset_val;
END;
$$;


ALTER FUNCTION "public"."get_trace_spans_paginated"("trace_ids_array" "uuid"[], "span_type_filter" "text", "start_date_iso" "text", "limit_val" integer, "offset_val" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_summaries_by_project"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result_json JSONB;
BEGIN
    SELECT jsonb_agg(trace_info) INTO result_json
    FROM (
        SELECT
            t.trace_id,
            t.name AS trace_name,
            t.duration AS latency,
            t.created_at AS timestamp,
            t.has_notification,
            t.aggregate_token_usage,
            ud.first_name || ' ' || ud.last_name AS creator,
            (
                SELECT jsonb_object_agg(sc.name, sc.raw_scores)
                FROM (
                    SELECT
                        sd.name,
                        jsonb_agg(sd.score) FILTER (WHERE sd.score IS NOT NULL) AS raw_scores
                    FROM trace_spans ts
                    JOIN examples e ON e.trace_span_id = ts.span_id
                    JOIN scorer_data sd ON sd.example_id = e.example_id
                    WHERE ts.trace_id = t.trace_id
                    GROUP BY sd.name
                ) sc
            ) AS scores
        FROM traces t
        JOIN user_data ud ON t.user_id = ud.id
        WHERE t.project_id = input_project_id
          AND t.created_at BETWEEN start_time AND end_time
        ORDER BY t.created_at DESC
    ) AS trace_info;

    RETURN result_json;
END;
$$;


ALTER FUNCTION "public"."get_trace_summaries_by_project"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_summaries_by_project_v2"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$DECLARE
    result_json JSONB;
BEGIN
    SELECT jsonb_agg(trace_info) INTO result_json
    FROM (
        SELECT
            t.trace_id,
            t.name AS trace_name,
            t.duration AS latency,
            t.created_at AS timestamp,
            t.has_notification,
            t.aggregate_token_usage,
            COALESCE(ud.first_name, 'Judgment') || ' ' || COALESCE(ud.last_name, 'Customer') AS creator,
            (
                SELECT jsonb_object_agg(sc.name, sc.raw_scores)
                FROM (
                    SELECT
                        sd.name,
                        jsonb_agg(sd.score) FILTER (WHERE sd.score IS NOT NULL) AS raw_scores
                    FROM trace_spans ts
                    JOIN examples e ON e.trace_span_id = ts.span_id
                    JOIN scorer_data sd ON sd.example_id = e.example_id
                    WHERE ts.trace_id = t.trace_id
                    GROUP BY sd.name
                ) sc
            ) AS scores
        FROM traces t
        JOIN user_data ud ON t.user_id = ud.id
        WHERE t.offline_mode = FALSE
          AND t.project_id = input_project_id
          AND t.created_at BETWEEN start_time AND end_time
        ORDER BY t.created_at DESC
    ) AS trace_info;

    RETURN result_json;
END;$$;


ALTER FUNCTION "public"."get_trace_summaries_by_project_v2"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_summaries_by_project_v3"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result_json JSONB;
BEGIN
    SELECT jsonb_agg(trace_info) INTO result_json
    FROM (
        SELECT
            t.trace_id,
            t.name AS trace_name,
            t.duration AS latency,
            t.created_at AS timestamp,
            t.has_notification,
            t.aggregate_token_usage,
            COALESCE(ud.first_name, 'Judgment') || ' ' || COALESCE(ud.last_name, 'Customer') AS creator,
            (
                SELECT jsonb_object_agg(sc.name, sc.score_summary)
                FROM (
                    SELECT
                        sd.name,
                        jsonb_build_object(
                            'mean', ROUND(AVG(sd.score)::numeric, 2),
                            'success', BOOL_AND(sd.success)
                        ) AS score_summary
                    FROM trace_spans ts
                    JOIN examples e ON e.trace_span_id = ts.span_id
                    JOIN scorer_data sd ON sd.example_id = e.example_id
                    WHERE ts.trace_id = t.trace_id
                    GROUP BY sd.name
                ) sc
            ) AS scores
        FROM traces t
        JOIN user_data ud ON t.user_id = ud.id
        WHERE t.offline_mode = FALSE
          AND t.project_id = input_project_id
          AND t.created_at BETWEEN start_time AND end_time
        ORDER BY t.created_at DESC
    ) AS trace_info;

    RETURN result_json;
END;
$$;


ALTER FUNCTION "public"."get_trace_summaries_by_project_v3"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_summaries_for_experiment_v2"("experiment_run_names_input" "text"[], "project_id_input" "uuid") RETURNS TABLE("experiment_run_id" "uuid", "experiment_name" "text", "experiment_created_at" timestamp with time zone, "creator_name" "text", "is_trace" boolean, "trace_id" "uuid", "trace_name" "text", "latency" integer, "trace_created_at" timestamp with time zone, "has_notification" boolean, "aggregate_token_usage" "jsonb", "scorers" "jsonb")
    LANGUAGE "sql"
    AS $$
    SELECT
        er.id AS experiment_run_id,
        er.name AS experiment_name,
        er.created_at AS experiment_created_at,
        ud.first_name || ' ' || ud.last_name AS creator_name,
        er.is_trace,

        t.trace_id,
        t.name AS trace_name,
        t.duration,
        t.created_at AS trace_created_at,
        t.has_notification,
        t.aggregate_token_usage,

        (
            SELECT jsonb_object_agg(s.name, s.scores)
            FROM (
                SELECT
                    sd.name,
                    jsonb_agg(sd.score) FILTER (WHERE sd.score IS NOT NULL) AS scores
                FROM public.scorer_data sd
                LEFT JOIN public.examples e ON e.example_id = sd.example_id
                LEFT JOIN public.trace_spans ts ON ts.span_id = COALESCE(e.trace_span_id, sd.trace_span_id)
                WHERE ts.trace_id = t.trace_id
                GROUP BY sd.name
            ) s
        ) AS scorers

    FROM public.experiment_runs er
    JOIN public.traces t ON t.experiment_run_id = er.id
    JOIN public.user_data ud ON ud.id = er.user_id
    WHERE er.name = ANY (experiment_run_names_input)
      AND er.project_id = project_id_input
    ORDER BY er.created_at DESC, t.created_at DESC;
$$;


ALTER FUNCTION "public"."get_trace_summaries_for_experiment_v2"("experiment_run_names_input" "text"[], "project_id_input" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trace_summaries_for_experiment_v3"("experiment_run_names_input" "text"[], "project_id_input" "uuid") RETURNS SETOF "jsonb"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT jsonb_build_object(
        'experiment_run_id', er.id,
        'experiment_name', er.name,
        'experiment_created_at', er.created_at,
        'creator_name', ud.first_name || ' ' || ud.last_name,
        'is_trace', er.is_trace,

        'trace_id', t.trace_id,
        'trace_name', t.name,
        'duration', t.duration,
        'trace_created_at', t.created_at,
        'has_notification', t.has_notification,
        'aggregate_token_usage', t.aggregate_token_usage,

        'scorers', (
            SELECT jsonb_object_agg(
                s.name,
                jsonb_build_object(
                    'mean', s.mean_score,
                    'success', s.success
                )
            )
            FROM (
                SELECT
                    sd.name,
                    AVG(sd.score) FILTER (WHERE sd.score IS NOT NULL) AS mean_score,
                    BOOL_AND(sd.success) FILTER (WHERE sd.success IS NOT NULL) AS success
                FROM public.scorer_data sd
                LEFT JOIN public.examples e ON e.example_id = sd.example_id
                LEFT JOIN public.trace_spans ts ON ts.span_id = COALESCE(e.trace_span_id, sd.trace_span_id)
                WHERE ts.trace_id = t.trace_id
                GROUP BY sd.name
            ) s
        )
    )
    FROM public.experiment_runs er
    JOIN public.traces t ON t.experiment_run_id = er.id
    JOIN public.user_data ud ON ud.id = er.user_id
    WHERE er.name = ANY (experiment_run_names_input)
      AND er.project_id = project_id_input
    ORDER BY er.created_at DESC, t.created_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_trace_summaries_for_experiment_v3"("experiment_run_names_input" "text"[], "project_id_input" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_traces_by_filters"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text", "search_term" "text" DEFAULT NULL::"text", "limit_val" integer DEFAULT 100, "offset_val" integer DEFAULT 0) RETURNS TABLE("trace_id" "uuid", "name" "text", "created_at" timestamp with time zone, "duration" double precision, "project_id" "uuid", "metadata" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    traces.trace_id,
    traces.name,
    traces.created_at,
    traces.duration,
    traces.project_id,
    traces.metadata
  FROM traces
  WHERE traces.project_id = ANY(project_ids_array)
    AND traces.created_at >= start_date_iso::timestamp
    AND traces.created_at <= end_date_iso::timestamp
    AND (search_term IS NULL OR traces.name ILIKE '%' || search_term || '%')
  ORDER BY traces.created_at DESC
  LIMIT limit_val
  OFFSET offset_val;
END;
$$;


ALTER FUNCTION "public"."get_traces_by_filters"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text", "search_term" "text", "limit_val" integer, "offset_val" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_traces_by_projects_and_date"("project_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) RETURNS TABLE("trace_id" "uuid", "project_id" "uuid", "created_at" timestamp with time zone, "user_id" "uuid", "duration_ms" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.trace_id,
    t.project_id,
    t.created_at,
    t.user_id,
    t.duration_ms
  FROM traces t
  WHERE t.project_id = ANY(project_ids)
  AND t.created_at >= start_date
  AND t.created_at <= end_date;
END;
$$;


ALTER FUNCTION "public"."get_traces_by_projects_and_date"("project_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text" DEFAULT '7d'::"text", "p_project_name" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_start_date TIMESTAMP WITH TIME ZONE;
  v_project_ids UUID[];
  v_result JSONB;
BEGIN
  -- Get start date from time range
  v_start_date := get_start_date_from_time_range(p_time_range);
  
  -- Get project IDs for the organization
  SELECT get_project_ids_for_org(p_organization_id, p_project_name) INTO v_project_ids;
  
  -- Return empty result if no projects found
  IF v_project_ids IS NULL OR array_length(v_project_ids, 1) = 0 THEN
    RETURN '[]'::JSONB;
  END IF;
  
  -- Calculate user usage metrics
  WITH user_metrics AS (
    SELECT
      t.user_id,
      COUNT(t.trace_id) AS trace_count,
      COALESCE(SUM((t.token_counts->>'total_tokens')::FLOAT), 0) AS total_tokens,
      0.0 AS total_cost -- Placeholder since cost column doesn't exist
    FROM traces t
    WHERE t.project_id = ANY(v_project_ids)
      AND t.created_at >= v_start_date
    GROUP BY t.user_id
    ORDER BY COUNT(t.trace_id) DESC
  ),
  user_with_email AS (
    SELECT
      um.user_id,
      COALESCE(ud.user_email, 'unknown') AS email,
      COALESCE(ud.first_name, 'User') AS first_name,
      COALESCE(ud.last_name, '') AS last_name,
      um.trace_count,
      um.total_tokens,
      um.total_cost
    FROM user_metrics um
    LEFT JOIN user_data ud ON um.user_id::TEXT = ud.id::TEXT
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'userId', user_id,
      'email', email,
      'firstName', first_name,
      'lastName', last_name,
      'traceCount', trace_count,
      'totalTokens', total_tokens,
      'totalCost', total_cost
    )
  ) INTO v_result
  FROM user_with_email;
  
  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;


ALTER FUNCTION "public"."get_user_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_data"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
  default_model_cost JSONB := '{}';
  generated_judgment_api_key UUID := gen_random_uuid();
BEGIN
  -- Insert a new row into user_data including name, email, and defaults
  INSERT INTO public.user_data (
	id,
	user_email,
	first_name,
	last_name,
	model_cost,
	judgment_api_key
  )
  VALUES (
	NEW.id,
	NEW.email,
	COALESCE(NEW.raw_user_meta_data ->> 'first_name', 'Judgment'),
  COALESCE(NEW.raw_user_meta_data ->> 'last_name', 'Customer'),
	default_model_cost,
	generated_judgment_api_key
  );

  -- Keep your existing logic for api_key_to_id table
  INSERT INTO public.api_key_to_id (
	id,
	api_key
  )
  VALUES (
	NEW.id,
	generated_judgment_api_key
  );


  RAISE NOTICE 'Inserted new user data for user ID: % with judgment_api_key: %', NEW.id, generated_judgment_api_key;
  RETURN NEW;
END;$$;


ALTER FUNCTION "public"."handle_new_user_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_judgees_ran"("organization_id" "uuid", "increment_by" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Use advisory lock to prevent race conditions
    PERFORM pg_advisory_xact_lock(hashtext(organization_id::text));
    
    -- Keep the same update logic, just add the lock
    UPDATE organizations
    SET judgees_ran = judgees_ran + increment_by
    WHERE id = organization_id;
    
    -- Original function returns void, so maintain that
EXCEPTION
    WHEN OTHERS THEN
        -- Original function doesn't handle errors, so we'll just log
        RAISE WARNING 'Error incrementing judgees_ran for org %: %', organization_id, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."increment_judgees_ran"("organization_id" "uuid", "increment_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_on_demand_judgees"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer DEFAULT 1) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update the organization's on_demand_judgees count
    UPDATE organizations
    SET on_demand_judgees = COALESCE(on_demand_judgees, 0) + p_increment_by
    WHERE id = p_org_id;
    
    -- Insert or update the user_org_resources record
    INSERT INTO user_org_resources (user_id, organization_id, judgees_ran)
    VALUES (p_user_id, p_org_id, p_increment_by)
    ON CONFLICT (user_id, organization_id) 
    DO UPDATE SET judgees_ran = user_org_resources.judgees_ran + p_increment_by;
END;
$$;


ALTER FUNCTION "public"."increment_on_demand_judgees"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_on_demand_traces"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer DEFAULT 1) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update the organization's on_demand_traces count
    UPDATE organizations
    SET on_demand_traces = COALESCE(on_demand_traces, 0) + p_increment_by
    WHERE id = p_org_id;
    
    -- Insert or update the user_org_resources record
    INSERT INTO user_org_resources (user_id, organization_id, traces_ran)
    VALUES (p_user_id, p_org_id, p_increment_by)
    ON CONFLICT (user_id, organization_id) 
    DO UPDATE SET traces_ran = user_org_resources.traces_ran + p_increment_by;
END;
$$;


ALTER FUNCTION "public"."increment_on_demand_traces"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_traces_ran"("organization_id" "uuid", "increment_by" integer) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE organizations
  SET traces_ran = traces_ran + increment_by
  WHERE id = organization_id;
END;
$$;


ALTER FUNCTION "public"."increment_traces_ran"("organization_id" "uuid", "increment_by" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_user_org_judgees_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO user_org_resources (
        user_id,
        organization_id,
        judgees_ran,
        traces_ran,
        created_at,
        updated_at,
        last_reset_at
    )
    VALUES (
        p_user_id,
        p_org_id,
        p_increment,
        0,
        NOW(),
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, organization_id)
    DO UPDATE SET
        judgees_ran = COALESCE(user_org_resources.judgees_ran, 0) + p_increment,
        updated_at = NOW();
END;
$$;


ALTER FUNCTION "public"."increment_user_org_judgees_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_user_org_traces_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO user_org_resources (
        user_id,
        organization_id,
        judgees_ran,
        traces_ran,
        created_at,
        updated_at,
        last_reset_at
    )
    VALUES (
        p_user_id,
        p_org_id,
        0,
        p_increment,
        NOW(),
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id, organization_id)
    DO UPDATE SET
        traces_ran = COALESCE(user_org_resources.traces_ran, 0) + p_increment,
        updated_at = NOW();
END;
$$;


ALTER FUNCTION "public"."increment_user_org_traces_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insert_example_with_scorer_data"("example_row" "jsonb", "scorer_data_rows" "jsonb") RETURNS TABLE("example_id" "uuid", "inserted_example" "jsonb", "inserted_scorer_data" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
declare
  new_example_id uuid;
  scorer_item jsonb; -- Declare the loop variable type explicitly
  inserted_scorer_row jsonb; -- To hold the JSON of the newly inserted scorer_data row
  all_inserted_scorers jsonb := '[]'::jsonb; -- Accumulator for all inserted scorer_data rows
begin
  -- Insert the example and get its ID
  insert into public.examples (
    input, actual_output, expected_output, context, retrieval_context,
    additional_metadata, tools_called, expected_tools, name, dataset_id,
    sequence_id, sequence_order, trace_span_id, experiment_run_id
  )
  values (
    example_row->'input',
    example_row->'actual_output',
    example_row->'expected_output',
    example_row->'context',
    example_row->'retrieval_context',
    example_row->'additional_metadata',
    example_row->'tools_called',
    example_row->'expected_tools',
    example_row->>'name',
    (example_row->>'dataset_id')::uuid,
    (example_row->>'sequence_id')::uuid,
    (example_row->>'sequence_order')::integer,
    (example_row->>'trace_span_id')::uuid,
    (example_row->>'experiment_run_id')::uuid
  )
  returning examples.example_id into new_example_id;

  -- Insert each scorer_data row, referencing the new example_id
  -- The 'value' column is the default output column name for jsonb_array_elements
  for scorer_item in select value from jsonb_array_elements(scorer_data_rows) loop
    insert into public.scorer_data (
      example_id, sequence_id, name, error, score, reason, success, threshold,
      strict_mode, verbose_logs, evaluation_cost, evaluation_model, additional_metadata, trace_span_id
    )
    values (
      new_example_id,
      (scorer_item->>'sequence_id')::uuid,
      scorer_item->>'name',
      scorer_item->>'error',
      (scorer_item->>'score')::real,
      scorer_item->>'reason',
      (scorer_item->>'success')::boolean,
      (scorer_item->>'threshold')::real,
      (scorer_item->>'strict_mode')::boolean,
      scorer_item->>'verbose_logs',
      (scorer_item->>'evaluation_cost')::real,
      scorer_item->>'evaluation_model',
      scorer_item->'additional_metadata', -- This is JSONB, so use ->
      (scorer_item->>'trace_span_id')::uuid
    )
    returning row_to_json(public.scorer_data.*) into inserted_scorer_row;
    
    all_inserted_scorers := all_inserted_scorers || inserted_scorer_row;
  end loop;

  -- Return the inserted example and scorer_data as JSON
  return query
    select
      e.example_id,
      row_to_json(e.*) as example_data, 
      all_inserted_scorers as scorer_data
    from public.examples e
    where e.example_id = new_example_id;
end;
$$;


ALTER FUNCTION "public"."insert_example_with_scorer_data"("example_row" "jsonb", "scorer_data_rows" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_usage_based_enabled"("org_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    is_enabled boolean;
BEGIN
    -- Get a lock on the organization record to ensure consistent reads
    PERFORM pg_advisory_xact_lock(hashtext(org_id::text));
    
    SELECT usage_based_enabled INTO is_enabled
    FROM organizations
    WHERE id = org_id;
    
    RETURN COALESCE(is_enabled, false);
EXCEPTION
    WHEN OTHERS THEN
        -- Keep the same behavior on error
        RETURN false;
END;
$$;


ALTER FUNCTION "public"."is_usage_based_enabled"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_debug"("message" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RAISE NOTICE '%', message;
END;
$$;


ALTER FUNCTION "public"."log_debug"("message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."new_get_latest_eval_results"("project_id" "uuid", "max_experiments" integer) RETURNS TABLE("eval_result_run" "text", "eval_result" "jsonb", "user_data" "jsonb", "examples" "jsonb")
    LANGUAGE "sql" STABLE
    AS $_$WITH latest_experiments AS (
    SELECT 
      eval_result_run,
      MAX(created_at) AS experiment_created_at
    FROM eval_results
    WHERE project_id = $1
    GROUP BY eval_result_run
    ORDER BY MAX(created_at) DESC
    LIMIT $2
  )
  SELECT
    er.eval_result_run,
    to_jsonb(er) AS eval_result, -- All columns from eval_results
    to_jsonb(ud) AS user_data,   -- All columns from user_data
    (SELECT jsonb_agg(to_jsonb(ex)) FROM examples ex WHERE ex.eval_results_id = er.id) AS examples
  FROM eval_results er
  LEFT JOIN user_data ud ON ud.id = er.user_id -- Replace "user_id" with your actual FK column
  WHERE er.eval_result_run IN (SELECT eval_result_run FROM latest_experiments)
  ORDER BY er.eval_result_run, er.created_at DESC;$_$;


ALTER FUNCTION "public"."new_get_latest_eval_results"("project_id" "uuid", "max_experiments" integer) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."datasets" (
    "dataset_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "dataset_alias" "text" NOT NULL,
    "comments" "text",
    "source_file" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_trace" boolean,
    "cluster_id" "text"
);


ALTER TABLE "public"."datasets" OWNER TO "postgres";


COMMENT ON TABLE "public"."datasets" IS 'Stores examples for all datasets';



COMMENT ON COLUMN "public"."datasets"."created_at" IS 'When example was created';



CREATE OR REPLACE FUNCTION "public"."pull_dataset"("input_dataset_id" "uuid") RETURNS TABLE("like" "public"."datasets")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.*
    FROM
        datasets d
    WHERE
        e.dataset_id = dataset_id;
END;
$$;


ALTER FUNCTION "public"."pull_dataset"("input_dataset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pull_dataset_by_alias"("input_dataset_alias" "text", "input_project_id" "uuid") RETURNS TABLE("like" "public"."datasets")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.*
    FROM
        project_datasets pd
    JOIN
        datasets d ON d.dataset_id = pd.dataset_id
    WHERE
        pd.project_id = input_project_id AND
        d.dataset_alias = input_dataset_alias;
END;
$$;


ALTER FUNCTION "public"."pull_dataset_by_alias"("input_dataset_alias" "text", "input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pull_datasets_by_project"("input_project_id" "uuid") RETURNS TABLE("like" "public"."datasets")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.*
    FROM 
        project_datasets pd
    JOIN 
        datasets d ON pd.dataset_id = d.dataset_id
    WHERE 
        pd.project_id = input_project_id;
END;
$$;


ALTER FUNCTION "public"."pull_datasets_by_project"("input_project_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."examples" (
    "example_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "input" "jsonb",
    "actual_output" "jsonb",
    "expected_output" "jsonb",
    "context" "jsonb",
    "retrieval_context" "jsonb",
    "additional_metadata" "jsonb",
    "tools_called" "jsonb",
    "expected_tools" "jsonb",
    "name" "text",
    "created_at" timestamp with time zone DEFAULT ("now"() AT TIME ZONE 'utc'::"text"),
    "dataset_id" "uuid",
    "trace_span_id" "uuid",
    "experiment_run_id" "uuid"
);


ALTER TABLE "public"."examples" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pull_examples_by_dataset"("input_dataset_id" "uuid") RETURNS TABLE("like" "public"."examples")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.*
    FROM
        examples e
    WHERE
        e.dataset_id = input_dataset_id;
END;
$$;


ALTER FUNCTION "public"."pull_examples_by_dataset"("input_dataset_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pull_examples_by_project"("input_project_id" "uuid") RETURNS TABLE("dataset_alias" "text", "like" "public"."examples")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.dataset_alias,
        e as examples
    FROM 
        project_datasets pd
    JOIN 
        datasets d ON pd.dataset_id = d.dataset_id
    LEFT JOIN 
        examples e ON d.dataset_id = e.dataset_id
    WHERE 
        pd.project_id = input_project_id;
END;
$$;


ALTER FUNCTION "public"."pull_examples_by_project"("input_project_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_judgee_count"("user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
BEGIN
    -- Reset in user_org_resources table
    UPDATE user_org_resources 
    SET judgees_ran = 0
    WHERE user_id = $1;
    
    -- Reset in user_data table
    UPDATE user_data 
    SET judgees_ran = 0
    WHERE id = $1;
END;
$_$;


ALTER FUNCTION "public"."reset_judgee_count"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_organization_usage"("org_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
    user_record RECORD;
BEGIN
    -- Reset organization counts
    UPDATE organizations
    SET judgees_ran = 0,
        traces_ran = 0,
        reset_at = NOW(),
        on_demand_judgees = 0,
        on_demand_traces = 0
    WHERE id = org_id;
    
    -- Reset user-organization resources for all users in this org
    UPDATE user_org_resources
    SET judgees_ran = 0,
        traces_ran = 0,
        updated_at = NOW(),
        last_reset_at = NOW()
    WHERE organization_id = org_id;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;$$;


ALTER FUNCTION "public"."reset_organization_usage"("org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_trace_count"("user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
BEGIN
    -- Reset in user_org_resources table
    UPDATE user_org_resources 
    SET traces_ran = 0
    WHERE user_id = $1;
    
    -- Reset in user_data table
    UPDATE user_data 
    SET traces_ran = 0
    WHERE id = $1;
END;
$_$;


ALTER FUNCTION "public"."reset_trace_count"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_user_org_judgees_ran"("p_user_id" "uuid", "p_organization_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Insert or update the record
    INSERT INTO user_org_resources (user_id, organization_id, judgees_ran)
    VALUES (p_user_id, p_organization_id, 0)
    ON CONFLICT (user_id, organization_id)
    DO UPDATE SET
        judgees_ran = 0,
        updated_at = now();
END;
$$;


ALTER FUNCTION "public"."reset_user_org_judgees_ran"("p_user_id" "uuid", "p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_user_org_traces_ran"("p_user_id" "uuid", "p_organization_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Insert or update the record
    INSERT INTO user_org_resources (user_id, organization_id, traces_ran)
    VALUES (p_user_id, p_organization_id, 0)
    ON CONFLICT (user_id, organization_id)
    DO UPDATE SET
        traces_ran = 0,
        updated_at = now();
END;
$$;


ALTER FUNCTION "public"."reset_user_org_traces_ran"("p_user_id" "uuid", "p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rotate_api_key"() RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$DECLARE
  new_api_key UUID;
  user_id UUID := auth.uid(); -- Get the ID of the user calling the function from the JWT
BEGIN
  -- ==================================================
  -- SECURITY CHECK: Ensure the user is authenticated.
  -- ==================================================
  IF user_id IS NULL THEN
     RAISE EXCEPTION 'Authentication required: No user ID found in JWT.';
  END IF;

  -- Generate a new random UUID for the API key
  new_api_key := gen_random_uuid();
  RAISE NOTICE '[rotate_api_key] Generated new API key % for user %', new_api_key, user_id;

  -- Update the judgment_api_key in the user_data table for the authenticated user
  UPDATE public.user_data
  SET judgment_api_key = new_api_key
  WHERE id = user_id; -- Use the authenticated user's ID

  -- Check if the user_data update actually found and updated a row
  IF NOT FOUND THEN
      -- This case should ideally not happen for an authenticated user if your setup trigger works correctly,
      -- but it's good practice to check.
      RAISE EXCEPTION 'User Data Not Found: No user data found for authenticated user ID % in user_data table.', user_id;
  END IF;
  RAISE NOTICE '[rotate_api_key] Updated judgment_api_key in user_data for user %', user_id;

  -- ==================================================
  -- Update the api_key_to_id lookup table.
  -- Delete the old mapping and insert the new one based on the user_id.
  -- ==================================================
  DELETE FROM public.api_key_to_id
  WHERE id = user_id; -- Use the authenticated user's ID

  -- Check if the delete operation affected any rows (optional)
  IF FOUND THEN
      RAISE NOTICE '[rotate_api_key] Deleted old mapping from api_key_to_id for user %', user_id;
  ELSE
      RAISE WARNING '[rotate_api_key] No existing mapping found in api_key_to_id to delete for user %', user_id;
  END IF;

  -- Insert the new mapping between the user ID and the new API key
  INSERT INTO public.api_key_to_id (id, api_key)
  VALUES (user_id, new_api_key); -- Use the authenticated user's ID
  RAISE NOTICE '[rotate_api_key] Inserted new mapping into api_key_to_id for user %', user_id;

  -- Return the newly generated API key to the caller
  RETURN new_api_key;

EXCEPTION
    -- Catch any unexpected errors during the process
    WHEN OTHERS THEN
        RAISE EXCEPTION '[rotate_api_key] Error rotating API key for user %: %', user_id, SQLERRM;
END;$$;


ALTER FUNCTION "public"."rotate_api_key"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_backfill_in_batches"("days_back" integer DEFAULT 30, "batch_size" integer DEFAULT 100, "num_batches" integer DEFAULT 5) RETURNS TABLE("total_traces_processed" integer, "total_traces_skipped" integer, "total_tokens_updated" bigint, "total_cost_updated" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_total_processed INTEGER := 0;
    v_total_skipped INTEGER := 0;
    v_total_tokens BIGINT := 0;
    v_total_cost DECIMAL(10, 6) := 0;
    v_batch_result RECORD;
    i INTEGER;
BEGIN
    FOR i IN 1..num_batches LOOP
        SELECT * FROM public.backfill_token_usage_from_traces(days_back, batch_size) INTO v_batch_result;
        
        v_total_processed := v_total_processed + v_batch_result.traces_processed;
        v_total_skipped := v_total_skipped + v_batch_result.traces_skipped;
        v_total_tokens := v_total_tokens + v_batch_result.tokens_updated;
        v_total_cost := v_total_cost + v_batch_result.cost_updated;
        
        -- Exit if we processed fewer traces than the batch size (means we're done)
        IF v_batch_result.traces_processed + v_batch_result.traces_skipped < batch_size THEN
            EXIT;
        END IF;
    END LOOP;
    
    RETURN QUERY SELECT v_total_processed, v_total_skipped, v_total_tokens, v_total_cost;
END;
$$;


ALTER FUNCTION "public"."run_backfill_in_batches"("days_back" integer, "batch_size" integer, "num_batches" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_custom_judgee_limit"("org_id" "uuid", "new_limit" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE organizations
    SET judgees_custom_limit = new_limit
    WHERE id = org_id;
    
    RETURN FOUND;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."set_custom_judgee_limit"("org_id" "uuid", "new_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_custom_trace_limit"("org_id" "uuid", "new_limit" integer) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE organizations
    SET traces_custom_limit = new_limit
    WHERE id = org_id;
    
    RETURN FOUND;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."set_custom_trace_limit"("org_id" "uuid", "new_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_workspace_name"("p_workspace_name" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$DECLARE
  -- Renamed variable to avoid ambiguity with the table column
  v_user_id UUID := auth.uid();
  target_organization_id UUID;
BEGIN
  -- Security Check: Ensure the user is authenticated.
  IF v_user_id IS NULL THEN
     RAISE EXCEPTION 'Authentication required: No user ID found.';
  END IF;

  -- Find the organization associated with the user using the 'user_organizations' table.
  SELECT organization_id -- <<< ADJUST 'organization_id' column name if different
  INTO target_organization_id
  FROM public.user_organizations -- <<< USING 'user_organizations' TABLE NAME
  -- Explicitly qualify the table column and use the renamed variable
  WHERE public.user_organizations.user_id = v_user_id -- <<< CORRECTED: Table.Column = Variable
  ORDER BY created_at ASC -- Optional: ensure we get the first one. ADJUST 'created_at' if different.
  LIMIT 1;

  -- Check if an organization was found
  IF target_organization_id IS NULL THEN
      -- Consider returning JSON instead of raising exception for client handling
      RETURN jsonb_build_object('status', 'error', 'message', 'Organization not found: No organization linked to the current user via user_organizations.');
      -- RAISE EXCEPTION 'Organization not found: No organization linked to the current user via user_organizations.';
  END IF;

  RAISE NOTICE '[set_workspace_name] Found organization % for user % via user_organizations', target_organization_id, v_user_id;

  -- Update the organization's name in the 'organizations' table
  UPDATE public.organizations -- <<< ADJUST 'organizations' table name if different
  SET name = p_workspace_name
  WHERE id = target_organization_id; -- <<< ADJUST 'id' column name if different

  -- Check if the update was successful
  IF NOT FOUND THEN
      -- Consider returning JSON instead of raising exception
      RETURN jsonb_build_object('status', 'error', 'message', 'Update failed: Organization ID not found in organizations table.');
      -- RAISE EXCEPTION 'Update failed: Organization ID % not found in organizations table.', target_organization_id;
  END IF;

  RAISE NOTICE '[set_workspace_name] Updated name of organization % to %', target_organization_id, p_workspace_name;

  -- Return success status
  RETURN jsonb_build_object('status', 'success', 'organization_id', target_organization_id, 'new_name', p_workspace_name);

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[set_workspace_name] Error for user %: %', v_user_id, SQLERRM;
        RETURN jsonb_build_object('status', 'error', 'message', SQLERRM);
END;$$;


ALTER FUNCTION "public"."set_workspace_name"("p_workspace_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_update_token_usage_from_trace"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Call the existing update_token_usage_from_trace function with the new trace ID
    PERFORM public.update_token_usage_from_trace(NEW.trace_id);
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_update_token_usage_from_trace"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."truncate_trace_spans"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  TRUNCATE TABLE trace_spans;
END;
$$;


ALTER FUNCTION "public"."truncate_trace_spans"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_modified_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_modified_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_token_usage_from_trace"("p_trace_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_user_id UUID;
    v_organization_id UUID;
    v_token_counts JSONB;
    v_prompt_tokens BIGINT := 0;
    v_completion_tokens BIGINT := 0;
    v_total_tokens BIGINT := 0;
    v_total_cost DECIMAL(10, 6) := 0.0;
    v_created_at TIMESTAMPTZ;
    v_org_exists BOOLEAN;
BEGIN
    -- Get trace information
    SELECT 
        t.user_id, 
        p.organization_id,
        t.token_counts,
        t.created_at
    INTO 
        v_user_id, 
        v_organization_id,
        v_token_counts,
        v_created_at
    FROM 
        traces t
    JOIN 
        projects p ON t.project_id = p.project_id
    WHERE 
        t.trace_id = p_trace_id;
    
    -- If trace not found or token_counts is null, return error
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Trace not found'
        );
    END IF;
    
    IF v_token_counts IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'No token data found in trace'
        );
    END IF;
    
    -- Check if the organization exists
    SELECT EXISTS(SELECT 1 FROM organizations WHERE id = v_organization_id) INTO v_org_exists;
    
    IF NOT v_org_exists THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Organization not found',
            'organization_id', v_organization_id
        );
    END IF;
    
    -- Extract token counts from the JSONB, handling both integer and decimal values
    -- Convert to float first, then to bigint to avoid syntax errors
    v_prompt_tokens := COALESCE(FLOOR((v_token_counts->>'prompt_tokens')::FLOAT)::BIGINT, 0);
    v_completion_tokens := COALESCE(FLOOR((v_token_counts->>'completion_tokens')::FLOAT)::BIGINT, 0);
    v_total_tokens := COALESCE(FLOOR((v_token_counts->>'total_tokens')::FLOAT)::BIGINT, 0);
    
    -- If total_tokens is not set but we have prompt and completion, calculate it
    IF v_total_tokens = 0 AND (v_prompt_tokens > 0 OR v_completion_tokens > 0) THEN
        v_total_tokens := v_prompt_tokens + v_completion_tokens;
    END IF;
    
    -- Calculate cost (simple calculation, can be refined based on model)
    v_total_cost := (v_prompt_tokens * 0.0000015) + (v_completion_tokens * 0.000002);
    
    -- Update user_org_resources
    INSERT INTO user_org_resources (
        user_id,
        organization_id,
        prompt_tokens,
        completion_tokens,
        total_tokens,
        total_cost,
        last_activity
    )
    VALUES (
        v_user_id,
        v_organization_id,
        v_prompt_tokens,
        v_completion_tokens,
        v_total_tokens,
        v_total_cost,
        v_created_at
    )
    ON CONFLICT (user_id, organization_id) 
    DO UPDATE SET
        prompt_tokens = user_org_resources.prompt_tokens + v_prompt_tokens,
        completion_tokens = user_org_resources.completion_tokens + v_completion_tokens,
        total_tokens = user_org_resources.total_tokens + v_total_tokens,
        total_cost = user_org_resources.total_cost + v_total_cost,
        last_activity = GREATEST(user_org_resources.last_activity, v_created_at);
    
    -- Return success with token data
    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_user_id,
        'organization_id', v_organization_id,
        'prompt_tokens', v_prompt_tokens,
        'completion_tokens', v_completion_tokens,
        'total_tokens', v_total_tokens,
        'total_cost', v_total_cost
    );
END;
$$;


ALTER FUNCTION "public"."update_token_usage_from_trace"("p_trace_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_trace_aggregate_token_usage_json"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    usage_data JSONB;
    parent_trace_id UUID;
BEGIN
    -- Find the parent trace for the affected span
    SELECT ts.trace_id
    INTO parent_trace_id
    FROM public.trace_spans ts
    WHERE ts.span_id = COALESCE(NEW.trace_span_id, OLD.trace_span_id)
    LIMIT 1;

    -- If parent trace found, recalculate totals
    IF parent_trace_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'prompt_tokens', COALESCE(SUM(tsu.prompt_tokens), 0),
            'completion_tokens', COALESCE(SUM(tsu.completion_tokens), 0),
            'total_tokens', COALESCE(SUM(tsu.total_tokens), 0),
            'prompt_tokens_cost_usd', COALESCE(SUM(tsu.prompt_tokens_cost_usd), 0),
            'completion_tokens_cost_usd', COALESCE(SUM(tsu.completion_tokens_cost_usd), 0),
            'total_cost_usd', COALESCE(SUM(tsu.total_cost_usd), 0)
        )
        INTO usage_data
        FROM public.trace_spans ts
        JOIN public.trace_span_token_usage tsu ON tsu.trace_span_id = ts.span_id
        WHERE ts.trace_id = parent_trace_id;

        -- Update the aggregate_token_usage field on the trace
        UPDATE public.traces
        SET aggregate_token_usage = usage_data
        WHERE trace_id = parent_trace_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_trace_aggregate_token_usage_json"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = TIMEZONE('utc', NOW());
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_user_org_resources_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_user_org_resources_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_slack_token_ownership"("token_team_id" "text", "token_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    existing_user_id UUID;
BEGIN
    -- Check if team exists with different user
    SELECT user_id INTO existing_user_id
    FROM slack_configs
    WHERE team_id = token_team_id;
    
    IF existing_user_id IS NOT NULL AND existing_user_id != token_user_id THEN
        RETURN FALSE; -- Team already registered to another user
    END IF;
    
    RETURN TRUE;
END;
$$;


ALTER FUNCTION "public"."validate_slack_token_ownership"("token_team_id" "text", "token_user_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alerts" (
    "id" "uuid" NOT NULL,
    "example_id" "uuid" NOT NULL,
    "rule_name" "text" NOT NULL,
    "status" "text" NOT NULL,
    "conditions_result" "jsonb",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "rule_id" "text",
    "notification" "jsonb",
    "project_id" "uuid"
);


ALTER TABLE "public"."alerts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."annotation_queue" (
    "queue_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "trace_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "span_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "status" "text" DEFAULT 'pending'::"text",
    "name" "text",
    "project_id" "uuid"
);


ALTER TABLE "public"."annotation_queue" OWNER TO "postgres";


COMMENT ON COLUMN "public"."annotation_queue"."project_id" IS 'project id for a per project level selection';



CREATE TABLE IF NOT EXISTS "public"."api_key_to_id" (
    "api_key" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "public"."api_key_to_id" OWNER TO "postgres";


COMMENT ON TABLE "public"."api_key_to_id" IS 'Map user''s Judgment API Key to their ID for backend server purposes';



CREATE TABLE IF NOT EXISTS "public"."clusters" (
    "status" "text",
    "cluster_id" "text" NOT NULL,
    "cluster_identifier" "text"
);


ALTER TABLE "public"."clusters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_scorers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "conversation" "jsonb",
    "options" "jsonb",
    "user_id" "uuid" DEFAULT "gen_random_uuid"(),
    "slug" "text",
    "organization_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."custom_scorers" OWNER TO "postgres";


COMMENT ON COLUMN "public"."custom_scorers"."slug" IS 'Uniquely identify scorer';



CREATE TABLE IF NOT EXISTS "public"."dataset_traces" (
    "dataset_id" "uuid" NOT NULL,
    "trace_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."dataset_traces" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."experiment_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "project_id" "uuid" NOT NULL,
    "is_trace" boolean,
    "cluster_id" "text"
);


ALTER TABLE "public"."experiment_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invitations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "recipient_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "role" "public"."role" DEFAULT 'developer'::"public"."role",
    "email" character varying(255),
    "send_email" boolean DEFAULT false
);


ALTER TABLE "public"."invitations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."invitations"."email" IS 'Email address of the user being invited (used when recipient_user_id is not available)';



COMMENT ON COLUMN "public"."invitations"."send_email" IS 'Flag indicating whether an email should be sent for this invitation';



CREATE TABLE IF NOT EXISTS "public"."notification_preferences" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "text" NOT NULL,
    "organization_id" "text" NOT NULL,
    "evaluation_alerts_enabled" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notification_preferences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."org_to_stripe_id" (
    "id" "uuid" NOT NULL,
    "customer_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."org_to_stripe_id" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "judgees_ran" integer DEFAULT 0,
    "traces_ran" integer DEFAULT 0,
    "reset_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "subscription_tier" "text" DEFAULT 'developer'::"text",
    "judgees_custom_limit" integer,
    "traces_custom_limit" integer,
    "on_demand_judgees" integer DEFAULT 0,
    "on_demand_traces" integer DEFAULT 0,
    "usage_based_enabled" boolean DEFAULT false,
    "last_billed" timestamp with time zone,
    CONSTRAINT "check_judgees_ran_non_negative" CHECK (("judgees_ran" >= 0)),
    CONSTRAINT "check_traces_ran_non_negative" CHECK (("traces_ran" >= 0))
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."organizations"."usage_based_enabled" IS 'boolean value whether usage based pricing model is enabled';



CREATE TABLE IF NOT EXISTS "public"."project_datasets" (
    "project_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "dataset_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "public"."project_datasets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."projects" (
    "creator_id" "uuid" NOT NULL,
    "organization_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "project_name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT ("now"() AT TIME ZONE 'utc'::"text"),
    "project_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."scheduled_reports" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "project_name" "text",
    "email_addresses" "text"[] NOT NULL,
    "subject" "text",
    "frequency" "text" NOT NULL,
    "day_of_month" integer,
    "hour" integer NOT NULL,
    "minute" integer NOT NULL,
    "comparison_period" boolean DEFAULT false,
    "time_range_days" integer DEFAULT 7,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_sent_at" timestamp with time zone,
    "active" boolean DEFAULT true,
    "timezone" "text" DEFAULT 'UTC'::"text",
    "day_of_week" integer[]
);


ALTER TABLE "public"."scheduled_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."scorer_data" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "example_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "name" "text",
    "error" "text",
    "score" real,
    "reason" "text",
    "success" boolean,
    "threshold" real,
    "strict_mode" boolean,
    "verbose_logs" "text",
    "evaluation_cost" real,
    "evaluation_model" "text",
    "additional_metadata" "jsonb",
    "trace_span_id" "uuid"
);


ALTER TABLE "public"."scorer_data" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."self_hosted_endpoints" (
    "url" character varying NOT NULL,
    "custom_data" "json",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "aws_id" "uuid" DEFAULT "gen_random_uuid"(),
    "osiris_api_key" "uuid" DEFAULT "gen_random_uuid"()
);


ALTER TABLE "public"."self_hosted_endpoints" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."slack_configs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "team_id" "text" NOT NULL,
    "access_token" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "channels" "text"[] DEFAULT '{}'::"text"[],
    "mention_users" "text"[] DEFAULT '{}'::"text"[],
    "created_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    "updated_at" timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "public"."slack_configs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."traces" (
    "created_at" timestamp with time zone NOT NULL,
    "trace_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "duration" double precision NOT NULL,
    "token_counts" "jsonb",
    "project_id" "uuid" NOT NULL,
    "has_notification" boolean DEFAULT false,
    "entries" "jsonb",
    "aggregate_token_usage" "jsonb" DEFAULT '{}'::"jsonb",
    "customer_id" "text",
    "tags" "text"[],
    "cluster_id" "text",
    "dataset_id" "uuid",
    "experiment_run_id" "uuid",
    "offline_mode" boolean DEFAULT false
);


ALTER TABLE "public"."traces" OWNER TO "postgres";


COMMENT ON TABLE "public"."traces" IS 'Tracks traces from user workflows';



COMMENT ON COLUMN "public"."traces"."has_notification" IS 'Indicates whether a notification has been sent from async_eval_server';



COMMENT ON COLUMN "public"."traces"."customer_id" IS 'the customer_id of the customer of our users using the agent';



COMMENT ON COLUMN "public"."traces"."tags" IS 'optional tags for each trace';



CREATE TABLE IF NOT EXISTS "public"."user_data" (
    "id" "uuid" NOT NULL,
    "model_cost" "jsonb",
    "judgment_api_key" "uuid",
    "first_name" "text" DEFAULT 'Judgment'::"text" NOT NULL,
    "last_name" "text" DEFAULT 'Customer'::"text" NOT NULL,
    "judgee_ran" integer DEFAULT 0 NOT NULL,
    "traces_ran" integer DEFAULT 0 NOT NULL,
    "user_email" "text",
    "user_tier" "text" DEFAULT 'developer'::"text",
    "onboarded" boolean DEFAULT false,
    CONSTRAINT "user_data_first_name_check" CHECK (("length"("first_name") < 50)),
    CONSTRAINT "user_data_last_name_check" CHECK (("length"("last_name") < 50)),
    CONSTRAINT "user_data_tier_check" CHECK (("user_tier" = ANY (ARRAY['developer'::"text", 'pro'::"text", 'enterprise'::"text"])))
);


ALTER TABLE "public"."user_data" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_data"."judgment_api_key" IS 'User''s Judgment API Key to authenticate requests to server, can be updated';



COMMENT ON COLUMN "public"."user_data"."first_name" IS 'User''s First Name';



COMMENT ON COLUMN "public"."user_data"."last_name" IS 'User''s Last Name';



COMMENT ON COLUMN "public"."user_data"."user_email" IS 'User''s email address';



COMMENT ON COLUMN "public"."user_data"."user_tier" IS 'User''s subscription tier (developer, pro, enterprise)';



CREATE TABLE IF NOT EXISTS "public"."user_feedback" (
    "feedback_id" bigint NOT NULL,
    "user_id" "uuid" DEFAULT "gen_random_uuid"(),
    "feedback" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."user_feedback" OWNER TO "postgres";


ALTER TABLE "public"."user_feedback" ALTER COLUMN "feedback_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_feedback_feedback_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_org_resources" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "judgees_ran" integer DEFAULT 0,
    "traces_ran" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_reset_at" timestamp with time zone DEFAULT "now"(),
    "total_tokens" bigint DEFAULT 0,
    "prompt_tokens" bigint DEFAULT 0,
    "completion_tokens" bigint DEFAULT 0,
    "total_cost" numeric(10,6) DEFAULT 0.0,
    "last_activity" timestamp with time zone
);


ALTER TABLE "public"."user_org_resources" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_organizations" (
    "user_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role" "public"."role" DEFAULT 'developer'::"public"."role"
);


ALTER TABLE "public"."user_organizations" OWNER TO "postgres";


ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."annotation_queue"
    ADD CONSTRAINT "annotation_queue_pkey" PRIMARY KEY ("queue_id");



ALTER TABLE ONLY "public"."api_key_to_id"
    ADD CONSTRAINT "api_key_to_id_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."api_key_to_id"
    ADD CONSTRAINT "api_key_to_id_pkey" PRIMARY KEY ("api_key");



ALTER TABLE ONLY "public"."clusters"
    ADD CONSTRAINT "clusters_pkey" PRIMARY KEY ("cluster_id");



ALTER TABLE ONLY "public"."custom_scorers"
    ADD CONSTRAINT "custom_scorers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dataset_traces"
    ADD CONSTRAINT "dataset_traces_pkey" PRIMARY KEY ("dataset_id", "trace_id");



ALTER TABLE ONLY "public"."datasets"
    ADD CONSTRAINT "datasets_pkey" PRIMARY KEY ("dataset_id");



ALTER TABLE ONLY "public"."examples"
    ADD CONSTRAINT "examples_pkey" PRIMARY KEY ("example_id");



ALTER TABLE ONLY "public"."experiment_runs"
    ADD CONSTRAINT "experiment_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invitations"
    ADD CONSTRAINT "invitations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_data"
    ADD CONSTRAINT "new_user_data_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_preferences"
    ADD CONSTRAINT "notification_preferences_user_id_organization_id_key" UNIQUE ("user_id", "organization_id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_datasets"
    ADD CONSTRAINT "project_datasets_pkey" PRIMARY KEY ("project_id", "dataset_id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("project_id");



ALTER TABLE ONLY "public"."scheduled_reports"
    ADD CONSTRAINT "scheduled_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scorer_data"
    ADD CONSTRAINT "scorer_data_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."self_hosted_endpoints"
    ADD CONSTRAINT "self_hosted_endpoints_pkey" PRIMARY KEY ("url");



ALTER TABLE ONLY "public"."slack_configs"
    ADD CONSTRAINT "slack_configs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."slack_configs"
    ADD CONSTRAINT "slack_configs_team_id_key" UNIQUE ("team_id");



ALTER TABLE ONLY "public"."trace_span_token_usage"
    ADD CONSTRAINT "trace_span_token_usage_pkey" PRIMARY KEY ("trace_span_id");



ALTER TABLE ONLY "public"."trace_spans"
    ADD CONSTRAINT "trace_spans_pkey" PRIMARY KEY ("span_id");



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_pkey" PRIMARY KEY ("trace_id");



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_trace_id_key" UNIQUE ("trace_id");



ALTER TABLE ONLY "public"."user_data"
    ADD CONSTRAINT "user_data_judgment_api_key_key" UNIQUE ("judgment_api_key");



ALTER TABLE ONLY "public"."user_feedback"
    ADD CONSTRAINT "user_feedback_pkey" PRIMARY KEY ("feedback_id");



ALTER TABLE ONLY "public"."user_org_resources"
    ADD CONSTRAINT "user_org_resources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_org_resources"
    ADD CONSTRAINT "user_org_resources_user_id_organization_id_key" UNIQUE ("user_id", "organization_id");



ALTER TABLE ONLY "public"."user_organizations"
    ADD CONSTRAINT "user_organizations_pkey" PRIMARY KEY ("user_id", "organization_id");



ALTER TABLE ONLY "public"."org_to_stripe_id"
    ADD CONSTRAINT "user_stripe_mapping_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_alerts_project_id" ON "public"."alerts" USING "btree" ("project_id");



CREATE INDEX "idx_alerts_rule_id" ON "public"."alerts" USING "btree" ("rule_id");



CREATE INDEX "idx_dataset_id" ON "public"."datasets" USING "btree" ("dataset_id");



CREATE INDEX "idx_examples_dataset_id" ON "public"."examples" USING "btree" ("dataset_id");



CREATE INDEX "idx_examples_experiment_run_id" ON "public"."examples" USING "btree" ("experiment_run_id");



CREATE INDEX "idx_examples_trace_span_id" ON "public"."examples" USING "btree" ("trace_span_id");



CREATE INDEX "idx_experiment_runs_project_id" ON "public"."experiment_runs" USING "btree" ("project_id");



CREATE INDEX "idx_projects_organization_id" ON "public"."projects" USING "btree" ("organization_id", "project_id");



CREATE INDEX "idx_scheduled_reports_day_of_week" ON "public"."scheduled_reports" USING "gin" ("day_of_week");



CREATE INDEX "idx_scheduled_reports_org_id" ON "public"."scheduled_reports" USING "btree" ("organization_id");



CREATE INDEX "idx_scheduled_reports_user_id" ON "public"."scheduled_reports" USING "btree" ("user_id");



CREATE INDEX "idx_scorer_data_example_id" ON "public"."scorer_data" USING "btree" ("example_id");



CREATE INDEX "idx_scorer_data_trace_span_id" ON "public"."scorer_data" USING "btree" ("trace_span_id");



CREATE INDEX "idx_token_usage_span_created" ON "public"."trace_span_token_usage" USING "btree" ("trace_span_id", "created_at");



CREATE INDEX "idx_trace_spans_error_created_at" ON "public"."trace_spans" USING "btree" ("created_at" DESC) WHERE ("error" IS NOT NULL);



CREATE INDEX "idx_trace_spans_error_gin" ON "public"."trace_spans" USING "gin" ("error") WHERE ("error" IS NOT NULL);



CREATE INDEX "idx_trace_spans_error_not_null" ON "public"."trace_spans" USING "btree" ("trace_id") WHERE ("error" IS NOT NULL);



CREATE INDEX "idx_trace_spans_trace_id" ON "public"."trace_spans" USING "btree" ("trace_id");



CREATE INDEX "idx_trace_spans_trace_type_created" ON "public"."trace_spans" USING "btree" ("trace_id", "span_type", "created_at");



CREATE INDEX "idx_traces_customer_id_created_at" ON "public"."traces" USING "btree" ("customer_id", "created_at") WHERE ("customer_id" IS NOT NULL);



CREATE INDEX "idx_traces_customer_id_not_null" ON "public"."traces" USING "btree" ("customer_id") WHERE (("customer_id" IS NOT NULL) AND ("customer_id" <> ''::"text"));



CREATE INDEX "idx_traces_project_created_at" ON "public"."traces" USING "btree" ("project_id", "created_at" DESC);



CREATE INDEX "idx_traces_project_created_customer" ON "public"."traces" USING "btree" ("project_id", "created_at", "customer_id") WHERE ("customer_id" IS NOT NULL);



CREATE INDEX "idx_traces_project_customer_created" ON "public"."traces" USING "btree" ("project_id", "customer_id", "created_at") WHERE ("customer_id" IS NOT NULL);



CREATE INDEX "idx_traces_project_customer_created_at" ON "public"."traces" USING "btree" ("project_id", "customer_id", "created_at") WHERE ("customer_id" IS NOT NULL);



CREATE INDEX "idx_traces_project_id" ON "public"."traces" USING "btree" ("project_id");



CREATE INDEX "idx_traces_user_id" ON "public"."traces" USING "btree" ("user_id");



CREATE INDEX "organizations_subscription_tier_idx" ON "public"."organizations" USING "btree" ("subscription_tier");



CREATE INDEX "slack_configs_team_id_idx" ON "public"."slack_configs" USING "btree" ("team_id");



CREATE INDEX "slack_configs_user_id_idx" ON "public"."slack_configs" USING "btree" ("user_id");



CREATE INDEX "user_org_resources_organization_id_idx" ON "public"."user_org_resources" USING "btree" ("organization_id");



CREATE INDEX "user_org_resources_user_id_idx" ON "public"."user_org_resources" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "on_user_data_inserted" AFTER INSERT ON "public"."user_data" FOR EACH ROW EXECUTE FUNCTION "public"."create_default_organization"();



CREATE OR REPLACE TRIGGER "trigger_update_trace_aggregate_token_usage_json" AFTER INSERT OR DELETE OR UPDATE ON "public"."trace_span_token_usage" FOR EACH ROW EXECUTE FUNCTION "public"."update_trace_aggregate_token_usage_json"();



CREATE OR REPLACE TRIGGER "update_slack_configs_timestamp" BEFORE UPDATE ON "public"."slack_configs" FOR EACH ROW EXECUTE FUNCTION "public"."update_modified_column"();



CREATE OR REPLACE TRIGGER "update_token_usage_trigger" AFTER INSERT ON "public"."traces" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_update_token_usage_from_trace"();



CREATE OR REPLACE TRIGGER "update_user_org_resources_updated_at" BEFORE UPDATE ON "public"."user_org_resources" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_example_id_fkey" FOREIGN KEY ("example_id") REFERENCES "public"."examples"("example_id");



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."annotation_queue"
    ADD CONSTRAINT "annotation_queue_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id");



ALTER TABLE ONLY "public"."custom_scorers"
    ADD CONSTRAINT "custom_scorers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."custom_scorers"
    ADD CONSTRAINT "custom_scorers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_data"("id");



ALTER TABLE ONLY "public"."datasets"
    ADD CONSTRAINT "datasets_cluster_id_fkey" FOREIGN KEY ("cluster_id") REFERENCES "public"."clusters"("cluster_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."examples"
    ADD CONSTRAINT "examples_dataset_id_fkey" FOREIGN KEY ("dataset_id") REFERENCES "public"."datasets"("dataset_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."examples"
    ADD CONSTRAINT "examples_experiment_run_id_fkey" FOREIGN KEY ("experiment_run_id") REFERENCES "public"."experiment_runs"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."examples"
    ADD CONSTRAINT "examples_trace_span_id_fkey" FOREIGN KEY ("trace_span_id") REFERENCES "public"."trace_spans"("span_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."experiment_runs"
    ADD CONSTRAINT "experiment_runs_cluster_id_fkey" FOREIGN KEY ("cluster_id") REFERENCES "public"."clusters"("cluster_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."experiment_runs"
    ADD CONSTRAINT "experiment_runs_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."experiment_runs"
    ADD CONSTRAINT "experiment_runs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_data"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."api_key_to_id"
    ADD CONSTRAINT "fk_api_key_user" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dataset_traces"
    ADD CONSTRAINT "fk_dataset" FOREIGN KEY ("dataset_id") REFERENCES "public"."datasets"("dataset_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dataset_traces"
    ADD CONSTRAINT "fk_trace" FOREIGN KEY ("trace_id") REFERENCES "public"."traces"("trace_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_data"
    ADD CONSTRAINT "new_user_data_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_datasets"
    ADD CONSTRAINT "project_datasets_dataset_id_fkey1" FOREIGN KEY ("dataset_id") REFERENCES "public"."datasets"("dataset_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_datasets"
    ADD CONSTRAINT "project_datasets_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "public"."user_data"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."scorer_data"
    ADD CONSTRAINT "scorer_data_example_id_fkey" FOREIGN KEY ("example_id") REFERENCES "public"."examples"("example_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scorer_data"
    ADD CONSTRAINT "scorer_data_trace_span_id_fkey" FOREIGN KEY ("trace_span_id") REFERENCES "public"."trace_spans"("span_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trace_span_token_usage"
    ADD CONSTRAINT "trace_span_token_usage_trace_span_id_fkey" FOREIGN KEY ("trace_span_id") REFERENCES "public"."trace_spans"("span_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."trace_spans"
    ADD CONSTRAINT "trace_spans_trace_id_fkey" FOREIGN KEY ("trace_id") REFERENCES "public"."traces"("trace_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_cluster_id_fkey" FOREIGN KEY ("cluster_id") REFERENCES "public"."clusters"("cluster_id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_dataset_id_fkey" FOREIGN KEY ("dataset_id") REFERENCES "public"."datasets"("dataset_id");



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_experiment_run_id_fkey" FOREIGN KEY ("experiment_run_id") REFERENCES "public"."experiment_runs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("project_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."traces"
    ADD CONSTRAINT "traces_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_data"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_org_resources"
    ADD CONSTRAINT "user_org_resources_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_org_resources"
    ADD CONSTRAINT "user_org_resources_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_organizations"
    ADD CONSTRAINT "user_organizations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON UPDATE CASCADE ON DELETE CASCADE;



CREATE POLICY "Users can delete custom_scorers in their orgs" ON "public"."custom_scorers" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_organizations"
  WHERE (("user_organizations"."user_id" = "auth"."uid"()) AND ("user_organizations"."organization_id" = "custom_scorers"."organization_id")))));



CREATE POLICY "Users can insert custom_scorers into their orgs" ON "public"."custom_scorers" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_organizations"
  WHERE (("user_organizations"."user_id" = "auth"."uid"()) AND ("user_organizations"."organization_id" = "custom_scorers"."organization_id")))));



CREATE POLICY "Users can select custom_scorers in their orgs" ON "public"."custom_scorers" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_organizations"
  WHERE (("user_organizations"."user_id" = "auth"."uid"()) AND ("user_organizations"."organization_id" = "custom_scorers"."organization_id")))));



CREATE POLICY "Users can update custom_scorers in their orgs" ON "public"."custom_scorers" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_organizations"
  WHERE (("user_organizations"."user_id" = "auth"."uid"()) AND ("user_organizations"."organization_id" = "custom_scorers"."organization_id")))));



ALTER TABLE "public"."custom_scorers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "slack_configs_delete_policy" ON "public"."slack_configs" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "slack_configs_insert_policy" ON "public"."slack_configs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "slack_configs_select_policy" ON "public"."slack_configs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "slack_configs_update_policy" ON "public"."slack_configs" FOR UPDATE USING (("auth"."uid"() = "user_id"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."traces";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";







































































































































































































































































































































































































































GRANT ALL ON FUNCTION "public"."add_on_demand_judgees"("org_id" "uuid", "count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."add_on_demand_judgees"("org_id" "uuid", "count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_on_demand_judgees"("org_id" "uuid", "count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."add_on_demand_traces"("org_id" "uuid", "count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."add_on_demand_traces"("org_id" "uuid", "count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_on_demand_traces"("org_id" "uuid", "count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."backfill_token_usage_from_traces"("days_back" integer, "batch_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."backfill_token_usage_from_traces"("days_back" integer, "batch_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."backfill_token_usage_from_traces"("days_back" integer, "batch_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."batch_update_trace_metadata"("trace_ids_array" "uuid"[], "metadata_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."batch_update_trace_metadata"("trace_ids_array" "uuid"[], "metadata_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."batch_update_trace_metadata"("trace_ids_array" "uuid"[], "metadata_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_percentiles"("p_values" numeric[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_percentiles"("p_values" numeric[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_percentiles"("p_values" numeric[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_percentiles"("p_values" "anyarray") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_percentiles"("p_values" "anyarray") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_percentiles"("p_values" "anyarray") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_and_reset_organizations"("days_between_resets" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."check_and_reset_organizations"("days_between_resets" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_and_reset_organizations"("days_between_resets" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_organization_exists"("input_organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_organization_exists"("input_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_organization_exists"("input_organization_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_user_exists"("email_input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_user_exists"("email_input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_user_exists"("email_input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_default_organization"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_default_organization"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_default_organization"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_on_demand_judgees"("organization_id" "uuid", "decrement_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_on_demand_judgees"("organization_id" "uuid", "decrement_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_on_demand_judgees"("organization_id" "uuid", "decrement_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_on_demand_traces"("organization_id" "uuid", "decrement_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_on_demand_traces"("organization_id" "uuid", "decrement_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_on_demand_traces"("organization_id" "uuid", "decrement_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_organization_judgees_ran"("organization_id" "uuid", "decrement_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_organization_judgees_ran"("organization_id" "uuid", "decrement_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_organization_judgees_ran"("organization_id" "uuid", "decrement_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_organization_traces_ran"("organization_id" "uuid", "decrement_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_organization_traces_ran"("organization_id" "uuid", "decrement_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_organization_traces_ran"("organization_id" "uuid", "decrement_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_user_org_judgees_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_user_org_judgees_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_user_org_judgees_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_user_org_traces_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_user_org_traces_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_user_org_traces_ran"("user_id" "uuid", "organization_id" "uuid", "decrement_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."fetch_detailed_trace_errors_by_projects"("project_ids_array" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone, "limit_results" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."fetch_detailed_trace_errors_by_projects"("project_ids_array" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone, "limit_results" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fetch_detailed_trace_errors_by_projects"("project_ids_array" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone, "limit_results" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_auth_users"("user_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_auth_users"("user_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_auth_users"("user_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_usage_metrics"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_usage_metrics"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_usage_metrics"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_summary"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dashboard_summary"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_summary"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid", "input_is_sequence" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid", "input_is_sequence" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_sequence"("input_project_id" "uuid", "input_is_sequence" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_trace"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_trace"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_aliases_by_project_and_trace"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_sequence"("input_project_id" "uuid", "input_dataset_alias" "text", "input_root_sequence_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_sequence"("input_project_id" "uuid", "input_dataset_alias" "text", "input_root_sequence_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_sequence"("input_project_id" "uuid", "input_dataset_alias" "text", "input_root_sequence_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_stats"("input_dataset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_stats"("input_dataset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_stats"("input_dataset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_stats_by_project"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_stats_by_project"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_stats_by_project"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dataset_stats_by_project_v2"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dataset_stats_by_project_v2"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dataset_stats_by_project_v2"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_examples_for_experiment_run"("project_id_input" "uuid", "experiment_name_input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_examples_for_experiment_run"("project_id_input" "uuid", "experiment_name_input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_examples_for_experiment_run"("project_id_input" "uuid", "experiment_name_input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_experiment_runs_by_ids"("experiment_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_experiment_runs_by_ids"("experiment_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_experiment_runs_by_ids"("experiment_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v2"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v2"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v2"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v3"("project_id_input" "uuid", "start_timestamp_input" timestamp without time zone, "end_timestamp_input" timestamp without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v3"("project_id_input" "uuid", "start_timestamp_input" timestamp without time zone, "end_timestamp_input" timestamp without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v3"("project_id_input" "uuid", "start_timestamp_input" timestamp without time zone, "end_timestamp_input" timestamp without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v4"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v4"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_experiment_summaries_by_project_v4"("project_id_input" "uuid", "start_timestamp_input" timestamp with time zone, "end_timestamp_input" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_experiments_by_project"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_experiments_by_project"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_experiments_by_project"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_latency_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_latency_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_latency_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid", "run_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid", "run_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_latest_eval_result_runs"("project" "uuid", "run_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_llm_span_details"("trace_ids_array" "uuid"[], "start_date_iso" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_llm_span_details"("trace_ids_array" "uuid"[], "start_date_iso" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_llm_span_details"("trace_ids_array" "uuid"[], "start_date_iso" "text") TO "service_role";



GRANT ALL ON TABLE "public"."trace_spans" TO "anon";
GRANT ALL ON TABLE "public"."trace_spans" TO "authenticated";
GRANT ALL ON TABLE "public"."trace_spans" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_llm_spans_by_trace_ids"("trace_ids_array" "uuid"[], "start_date_iso" "text", "span_type_filter" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_llm_spans_by_trace_ids"("trace_ids_array" "uuid"[], "start_date_iso" "text", "span_type_filter" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_llm_spans_by_trace_ids"("trace_ids_array" "uuid"[], "start_date_iso" "text", "span_type_filter" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_llm_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_llm_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_llm_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_organization_members"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_organization_members"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_members"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_organization_token_usage"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_organization_token_usage"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_organization_token_usage"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_id"("input_project_name" "text", "input_organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_id"("input_project_name" "text", "input_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_id"("input_project_name" "text", "input_organization_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_ids_for_org"("p_organization_id" "uuid", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_ids_for_org"("p_organization_id" "uuid", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_ids_for_org"("p_organization_id" "uuid", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_stats"("org_id" "uuid", "u_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_stats"("org_id" "uuid", "u_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_stats"("org_id" "uuid", "u_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_summaries"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_summaries"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_summaries"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_summaries_v2"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_summaries_v2"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_summaries_v2"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_summaries_v3"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_summaries_v3"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_summaries_v3"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_root_sequences_summary"("input_dataset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_root_sequences_summary"("input_dataset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_root_sequences_summary"("input_dataset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_slack_team_ids_for_user"("user_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_slack_team_ids_for_user"("user_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_slack_team_ids_for_user"("user_uuid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_spans_by_trace_ids"("trace_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_spans_by_trace_ids"("trace_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_spans_by_trace_ids"("trace_ids" "uuid"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_start_date_from_time_range"("p_time_range" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_start_date_from_time_range"("p_time_range" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_start_date_from_time_range"("p_time_range" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_token_breakdown_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_token_breakdown_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_token_breakdown_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_token_usage_by_span_ids"("span_ids" "uuid"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_token_usage_by_span_ids"("span_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_token_usage_by_span_ids"("span_ids" "uuid"[]) TO "service_role";



GRANT ALL ON TABLE "public"."trace_span_token_usage" TO "anon";
GRANT ALL ON TABLE "public"."trace_span_token_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."trace_span_token_usage" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_token_usage_for_spans"("span_ids_array" "uuid"[], "start_date_iso" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_token_usage_for_spans"("span_ids_array" "uuid"[], "start_date_iso" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_token_usage_for_spans"("span_ids_array" "uuid"[], "start_date_iso" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tokens_for_user"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_tokens_for_user"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tokens_for_user"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tool_spans_by_trace_ids"("trace_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_tool_spans_by_trace_ids"("trace_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tool_spans_by_trace_ids"("trace_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tool_usage_for_traces"("trace_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_tool_usage_for_traces"("trace_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tool_usage_for_traces"("trace_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tool_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_tool_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tool_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_aggregates"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_aggregates"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_aggregates"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_spans_paginated"("trace_ids_array" "uuid"[], "span_type_filter" "text", "start_date_iso" "text", "limit_val" integer, "offset_val" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_spans_paginated"("trace_ids_array" "uuid"[], "span_type_filter" "text", "start_date_iso" "text", "limit_val" integer, "offset_val" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_spans_paginated"("trace_ids_array" "uuid"[], "span_type_filter" "text", "start_date_iso" "text", "limit_val" integer, "offset_val" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project_v2"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project_v2"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project_v2"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project_v3"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project_v3"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_by_project_v3"("input_project_id" "uuid", "start_time" timestamp with time zone, "end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_summaries_for_experiment_v2"("experiment_run_names_input" "text"[], "project_id_input" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_for_experiment_v2"("experiment_run_names_input" "text"[], "project_id_input" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_for_experiment_v2"("experiment_run_names_input" "text"[], "project_id_input" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trace_summaries_for_experiment_v3"("experiment_run_names_input" "text"[], "project_id_input" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_for_experiment_v3"("experiment_run_names_input" "text"[], "project_id_input" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trace_summaries_for_experiment_v3"("experiment_run_names_input" "text"[], "project_id_input" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_traces_by_filters"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text", "search_term" "text", "limit_val" integer, "offset_val" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_traces_by_filters"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text", "search_term" "text", "limit_val" integer, "offset_val" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_traces_by_filters"("project_ids_array" "uuid"[], "start_date_iso" "text", "end_date_iso" "text", "search_term" "text", "limit_val" integer, "offset_val" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_traces_by_projects_and_date"("project_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_traces_by_projects_and_date"("project_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_traces_by_projects_and_date"("project_ids" "uuid"[], "start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_usage_metrics"("p_organization_id" "uuid", "p_time_range" "text", "p_project_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_judgees_ran"("organization_id" "uuid", "increment_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_judgees_ran"("organization_id" "uuid", "increment_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_judgees_ran"("organization_id" "uuid", "increment_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_on_demand_judgees"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_on_demand_judgees"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_on_demand_judgees"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_on_demand_traces"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_on_demand_traces"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_on_demand_traces"("p_org_id" "uuid", "p_user_id" "uuid", "p_increment_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_traces_ran"("organization_id" "uuid", "increment_by" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_traces_ran"("organization_id" "uuid", "increment_by" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_traces_ran"("organization_id" "uuid", "increment_by" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_user_org_judgees_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_user_org_judgees_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_user_org_judgees_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_user_org_traces_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_user_org_traces_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_user_org_traces_ran"("p_user_id" "uuid", "p_org_id" "uuid", "p_increment" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."insert_example_with_scorer_data"("example_row" "jsonb", "scorer_data_rows" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."insert_example_with_scorer_data"("example_row" "jsonb", "scorer_data_rows" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insert_example_with_scorer_data"("example_row" "jsonb", "scorer_data_rows" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_usage_based_enabled"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_usage_based_enabled"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_usage_based_enabled"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_debug"("message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."log_debug"("message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_debug"("message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."new_get_latest_eval_results"("project_id" "uuid", "max_experiments" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."new_get_latest_eval_results"("project_id" "uuid", "max_experiments" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."new_get_latest_eval_results"("project_id" "uuid", "max_experiments" integer) TO "service_role";



GRANT ALL ON TABLE "public"."datasets" TO "anon";
GRANT ALL ON TABLE "public"."datasets" TO "authenticated";
GRANT ALL ON TABLE "public"."datasets" TO "service_role";



GRANT ALL ON FUNCTION "public"."pull_dataset"("input_dataset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pull_dataset"("input_dataset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pull_dataset"("input_dataset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."pull_dataset_by_alias"("input_dataset_alias" "text", "input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pull_dataset_by_alias"("input_dataset_alias" "text", "input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pull_dataset_by_alias"("input_dataset_alias" "text", "input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."pull_datasets_by_project"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pull_datasets_by_project"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pull_datasets_by_project"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."examples" TO "anon";
GRANT ALL ON TABLE "public"."examples" TO "authenticated";
GRANT ALL ON TABLE "public"."examples" TO "service_role";



GRANT ALL ON FUNCTION "public"."pull_examples_by_dataset"("input_dataset_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pull_examples_by_dataset"("input_dataset_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pull_examples_by_dataset"("input_dataset_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."pull_examples_by_project"("input_project_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pull_examples_by_project"("input_project_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pull_examples_by_project"("input_project_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_judgee_count"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."reset_judgee_count"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_judgee_count"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_organization_usage"("org_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."reset_organization_usage"("org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_organization_usage"("org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_trace_count"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."reset_trace_count"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_trace_count"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_user_org_judgees_ran"("p_user_id" "uuid", "p_organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."reset_user_org_judgees_ran"("p_user_id" "uuid", "p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_user_org_judgees_ran"("p_user_id" "uuid", "p_organization_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_user_org_traces_ran"("p_user_id" "uuid", "p_organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."reset_user_org_traces_ran"("p_user_id" "uuid", "p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_user_org_traces_ran"("p_user_id" "uuid", "p_organization_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."rotate_api_key"() TO "anon";
GRANT ALL ON FUNCTION "public"."rotate_api_key"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rotate_api_key"() TO "service_role";



GRANT ALL ON FUNCTION "public"."run_backfill_in_batches"("days_back" integer, "batch_size" integer, "num_batches" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."run_backfill_in_batches"("days_back" integer, "batch_size" integer, "num_batches" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."run_backfill_in_batches"("days_back" integer, "batch_size" integer, "num_batches" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_custom_judgee_limit"("org_id" "uuid", "new_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."set_custom_judgee_limit"("org_id" "uuid", "new_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_custom_judgee_limit"("org_id" "uuid", "new_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_custom_trace_limit"("org_id" "uuid", "new_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."set_custom_trace_limit"("org_id" "uuid", "new_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_custom_trace_limit"("org_id" "uuid", "new_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_workspace_name"("p_workspace_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_workspace_name"("p_workspace_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_workspace_name"("p_workspace_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_update_token_usage_from_trace"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_update_token_usage_from_trace"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_update_token_usage_from_trace"() TO "service_role";



GRANT ALL ON FUNCTION "public"."truncate_trace_spans"() TO "anon";
GRANT ALL ON FUNCTION "public"."truncate_trace_spans"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."truncate_trace_spans"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_modified_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_modified_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_modified_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_token_usage_from_trace"("p_trace_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_token_usage_from_trace"("p_trace_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_token_usage_from_trace"("p_trace_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_trace_aggregate_token_usage_json"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_trace_aggregate_token_usage_json"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_trace_aggregate_token_usage_json"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_user_org_resources_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_user_org_resources_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_user_org_resources_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_slack_token_ownership"("token_team_id" "text", "token_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_slack_token_ownership"("token_team_id" "text", "token_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_slack_token_ownership"("token_team_id" "text", "token_user_id" "uuid") TO "service_role";



























GRANT ALL ON TABLE "public"."alerts" TO "anon";
GRANT ALL ON TABLE "public"."alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."alerts" TO "service_role";



GRANT ALL ON TABLE "public"."annotation_queue" TO "anon";
GRANT ALL ON TABLE "public"."annotation_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."annotation_queue" TO "service_role";



GRANT ALL ON TABLE "public"."api_key_to_id" TO "anon";
GRANT ALL ON TABLE "public"."api_key_to_id" TO "authenticated";
GRANT ALL ON TABLE "public"."api_key_to_id" TO "service_role";



GRANT ALL ON TABLE "public"."clusters" TO "anon";
GRANT ALL ON TABLE "public"."clusters" TO "authenticated";
GRANT ALL ON TABLE "public"."clusters" TO "service_role";



GRANT ALL ON TABLE "public"."custom_scorers" TO "anon";
GRANT ALL ON TABLE "public"."custom_scorers" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_scorers" TO "service_role";



GRANT ALL ON TABLE "public"."dataset_traces" TO "anon";
GRANT ALL ON TABLE "public"."dataset_traces" TO "authenticated";
GRANT ALL ON TABLE "public"."dataset_traces" TO "service_role";



GRANT ALL ON TABLE "public"."experiment_runs" TO "anon";
GRANT ALL ON TABLE "public"."experiment_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."experiment_runs" TO "service_role";



GRANT ALL ON TABLE "public"."invitations" TO "anon";
GRANT ALL ON TABLE "public"."invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."invitations" TO "service_role";



GRANT ALL ON TABLE "public"."notification_preferences" TO "anon";
GRANT ALL ON TABLE "public"."notification_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."org_to_stripe_id" TO "anon";
GRANT ALL ON TABLE "public"."org_to_stripe_id" TO "authenticated";
GRANT ALL ON TABLE "public"."org_to_stripe_id" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."project_datasets" TO "anon";
GRANT ALL ON TABLE "public"."project_datasets" TO "authenticated";
GRANT ALL ON TABLE "public"."project_datasets" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."scheduled_reports" TO "anon";
GRANT ALL ON TABLE "public"."scheduled_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."scheduled_reports" TO "service_role";



GRANT ALL ON TABLE "public"."scorer_data" TO "anon";
GRANT ALL ON TABLE "public"."scorer_data" TO "authenticated";
GRANT ALL ON TABLE "public"."scorer_data" TO "service_role";



GRANT ALL ON TABLE "public"."self_hosted_endpoints" TO "anon";
GRANT ALL ON TABLE "public"."self_hosted_endpoints" TO "authenticated";
GRANT ALL ON TABLE "public"."self_hosted_endpoints" TO "service_role";



GRANT ALL ON TABLE "public"."slack_configs" TO "anon";
GRANT ALL ON TABLE "public"."slack_configs" TO "authenticated";
GRANT ALL ON TABLE "public"."slack_configs" TO "service_role";



GRANT ALL ON TABLE "public"."traces" TO "anon";
GRANT ALL ON TABLE "public"."traces" TO "authenticated";
GRANT ALL ON TABLE "public"."traces" TO "service_role";



GRANT ALL ON TABLE "public"."user_data" TO "anon";
GRANT ALL ON TABLE "public"."user_data" TO "authenticated";
GRANT ALL ON TABLE "public"."user_data" TO "service_role";



GRANT ALL ON TABLE "public"."user_feedback" TO "anon";
GRANT ALL ON TABLE "public"."user_feedback" TO "authenticated";
GRANT ALL ON TABLE "public"."user_feedback" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_feedback_feedback_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_feedback_feedback_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_feedback_feedback_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_org_resources" TO "anon";
GRANT ALL ON TABLE "public"."user_org_resources" TO "authenticated";
GRANT ALL ON TABLE "public"."user_org_resources" TO "service_role";



GRANT ALL ON TABLE "public"."user_organizations" TO "anon";
GRANT ALL ON TABLE "public"."user_organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."user_organizations" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
