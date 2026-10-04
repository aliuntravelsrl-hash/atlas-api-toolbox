-- CANDIDATE — D-11 OVR lifecycle / claim binding
-- 2026-10-05
-- STATUS: STATIC REVIEW ONLY. NOT APPLIED TO PRODUCTION.
-- Contract: IMPLEMENTATION-CONTRACT-OVR-D11-v1-20261005
--
-- Required runtime route:
-- ACTIVE CLAIM -> GENERATE OVR -> COMPILED -> VALIDATE -> VALIDATED -> READY
-- -> DISPATCHED -> STARTED
--
-- IMPORTANT:
-- 1) claim_token is never persisted in ovr_instances.
-- 2) task_claim_leases remains the lease source of truth.
-- 3) fn_start_ovr is intentionally untouched.
-- 4) Existing OVR rows are NOT backfilled.
-- 5) The legacy generate_ovr(text) overload is explicitly retired.
--
-- This file is a candidate migration only. Do not apply until static review
-- and execution authorization are complete.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Retire the legacy generation interface before exposing the new contract.
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.generate_ovr(text);

-- ---------------------------------------------------------------------------
-- 1. GENERATE — claim-bound OVR generation.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_ovr(
  p_task_codigo text,
  p_claim_owner text,
  p_claim_token uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_task record;
  v_claim record;
  v_existing record;
  v_ovr_id text;
  v_ovr_seq int;
  v_kbp record;
  v_cap record;
  v_ovr_uuid uuid;
  v_kbp_integrity numeric;
  v_blocked_by text[];
  v_status text;
  v_manifest jsonb;
  v_spec_ref text;
BEGIN
  SELECT * INTO v_task
  FROM public.atlas_tasks
  WHERE codigo = p_task_codigo
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error','TASK_NOT_FOUND',
      'task_codigo',p_task_codigo
    );
  END IF;

  IF COALESCE(v_task.ovr_applicability,'') <> 'REQUIRED' THEN
    RETURN jsonb_build_object(
      'error','OVR_NOT_REQUIRED',
      'task_codigo',p_task_codigo,
      'ovr_applicability',v_task.ovr_applicability
    );
  END IF;

  IF v_task.estado NOT IN ('pendiente','ready','backlog') THEN
    RETURN jsonb_build_object(
      'error','TASK_NOT_ELIGIBLE',
      'task_codigo',p_task_codigo,
      'estado_actual',v_task.estado
    );
  END IF;

  SELECT *
  INTO v_claim
  FROM public.task_claim_leases
  WHERE task_id = v_task.id
    AND status = 'active'
    AND released_at IS NULL
  ORDER BY claimed_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error','CLAIM_REQUIRED',
      'task_codigo',p_task_codigo
    );
  END IF;

  IF v_claim.expires_at <= now() THEN
    RETURN jsonb_build_object(
      'error','CLAIM_EXPIRED',
      'task_codigo',p_task_codigo,
      'claim_id',v_claim.id
    );
  END IF;

  IF v_claim.claim_owner <> p_claim_owner THEN
    RETURN jsonb_build_object(
      'error','CLAIM_OWNER_MISMATCH',
      'task_codigo',p_task_codigo,
      'claim_id',v_claim.id
    );
  END IF;

  IF v_claim.claim_token <> p_claim_token THEN
    RETURN jsonb_build_object(
      'error','CLAIM_TOKEN_INVALID',
      'task_codigo',p_task_codigo,
      'claim_id',v_claim.id
    );
  END IF;

  -- Reuse only an OVR already bound to this active claim.
  SELECT *
  INTO v_existing
  FROM public.ovr_instances
  WHERE task_codigo = p_task_codigo
    AND ownership->>'claim_id' = v_claim.id::text
    AND status IN ('created','compiled','validated','ready','dispatched','started')
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'generated',false,
      'reused',true,
      'ovr_id',v_existing.ovr_id,
      'ovr_uuid',v_existing.id,
      'task_codigo',p_task_codigo,
      'status',v_existing.status,
      'claim_id',v_claim.id,
      'claim_owner',v_claim.claim_owner,
      'claim_expires_at',v_claim.expires_at
    );
  END IF;

  SELECT count(*) + 1
  INTO v_ovr_seq
  FROM public.ovr_instances
  WHERE date(created_at) = current_date;

  v_ovr_id :=
    'OVR-' || to_char(now(),'YYYYMMDD') || '-' ||
    lpad(v_ovr_seq::text,6,'0');

  SELECT *
  INTO v_cap
  FROM public.capability_catalog
  WHERE lower(owner) = lower(v_task.asignado_a)
    AND lower(lifecycle) = 'canonical'
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT *
  INTO v_kbp
  FROM public.kbp_events
  WHERE lower(agent) = lower(v_task.asignado_a)
    AND status = 'ready'
  ORDER BY generated_at DESC
  LIMIT 1;

  v_kbp_integrity := coalesce(v_kbp.integrity,0);
  v_blocked_by := coalesce(v_task.depende_de,array[]::text[]);
  v_spec_ref := null;

  IF v_cap.id IS NOT NULL THEN
    SELECT crm.cap_codigo
    INTO v_spec_ref
    FROM public.capability_resolver_map crm
    WHERE crm.cap_codigo = 'SPEC-' || substring(v_cap.codigo from 5)
      AND crm.repo = 'atlas-cos-v1'
      AND crm.ruta IS NOT NULL
    ORDER BY crm.created_at DESC
    LIMIT 1;
  END IF;

  v_manifest :=
    CASE
      WHEN v_kbp.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'kbp_event_id',v_kbp.id,
        'event',v_kbp.event,
        'agent',v_kbp.agent,
        'manifest_hash',v_kbp.manifest_hash,
        'knowledge_version',v_kbp.knowledge_version,
        'cos_version',v_kbp.cos_version,
        'integrity',v_kbp.integrity,
        'required_loaded',v_kbp.required_loaded,
        'required_total',v_kbp.required_total,
        'recommended_loaded',v_kbp.recommended_loaded,
        'optional_loaded',v_kbp.optional_loaded,
        'missing_required',v_kbp.missing_required,
        'status',v_kbp.status,
        'generated_at',v_kbp.generated_at
      )
    END;

  v_status :=
    CASE WHEN v_kbp_integrity >= 95 THEN 'compiled' ELSE 'created' END;

  INSERT INTO public.ovr_instances(
    ovr_id,
    task_id,
    task_codigo,
    status,
    schema_version,
    identity,
    ownership,
    capability,
    knowledge,
    execution,
    dependencies,
    evidence,
    governance,
    decision,
    compiled_at
  )
  VALUES (
    v_ovr_id,
    v_task.id,
    v_task.codigo,
    v_status,
    '1.0',
    jsonb_build_object(
      'ovr_id',v_ovr_id,
      'task_codigo',v_task.codigo,
      'task_titulo',v_task.titulo,
      'created_at',now()
    ),
    jsonb_build_object(
      'dispatcher','ATLAS-TECH',
      'authorized_by','ATLAS-TECH',
      'policy','dispatcher-policy-v1',
      'claim_id',v_claim.id,
      'claim_owner',v_claim.claim_owner,
      'claim_expires_at',v_claim.expires_at,
      'rationale',coalesce(v_task.notas,'Prioridad: '||v_task.prioridad)
    ),
    jsonb_build_object(
      'codigo',CASE WHEN v_cap.id IS NOT NULL THEN v_cap.codigo ELSE NULL END,
      'nombre',CASE WHEN v_cap.id IS NOT NULL THEN v_cap.nombre ELSE NULL END,
      'spec',CASE WHEN v_spec_ref IS NOT NULL THEN to_jsonb(v_spec_ref) ELSE NULL END,
      'adr',CASE WHEN v_cap.id IS NOT NULL THEN v_cap.adr_codigo ELSE NULL END,
      'agente',v_task.asignado_a,
      'dominio',coalesce(v_task.frente,'F2-BACKEND-CORE'),
      'resuelto',v_cap.id IS NOT NULL,
      'cap_codigo',CASE WHEN v_cap.id IS NOT NULL THEN v_cap.codigo ELSE NULL END
    ),
    jsonb_build_object(
      'manifest',v_manifest,
      'agent',v_task.asignado_a,
      'kbp_event_id',CASE WHEN v_kbp.id IS NOT NULL THEN v_kbp.id ELSE NULL END,
      'bundle_hash',CASE WHEN v_kbp.id IS NOT NULL THEN v_kbp.manifest_hash ELSE NULL END,
      'integrity_required',95,
      'integrity_actual',v_kbp_integrity,
      'status',CASE WHEN v_kbp_integrity >= 95 THEN 'ready' ELSE 'blocked' END
    ),
    jsonb_build_object(
      'agent',v_task.asignado_a,
      'role','executor',
      'db_connection','SUPABASE_URL+SERVICE_KEY',
      'exact_tables',jsonb_build_array(
        'public.atlas_tasks',
        'public.logs_operativos'
      ),
      'success_criteria',jsonb_build_array(
        'UPDATE atlas_tasks SET estado=completado',
        'INSERT logs_operativos TAREA_COMPLETADA'
      ),
      'forbidden',jsonb_build_array(
        'tabla tasks',
        'archivos locales',
        'ejecutar si KBP<95'
      )
    ),
    jsonb_build_object(
      'blocked_by',to_jsonb(v_blocked_by),
      'requires_ready',true,
      'kbp_ready',v_kbp_integrity>=95,
      'dispatcher_authorized',true
    ),
    jsonb_build_object(
      'required',jsonb_build_array(
        jsonb_build_object(
          'table','public.logs_operativos',
          'event','TAREA_COMPLETADA'
        ),
        jsonb_build_object(
          'table','public.task_pipeline_events',
          'event','TASK_COMPLETED'
        )
      ),
      'append_only',true
    ),
    jsonb_build_object(
      'protocols',jsonb_build_array('TPP-v1','KBP-v1','AGF-v1'),
      'cos_version','3.5'
    ),
    jsonb_build_object(
      'dispatcher','ATLAS-TECH',
      'policy','dispatcher-policy-v1',
      'rationale',coalesce(v_task.notas,'Prioridad: '||v_task.prioridad),
      'timestamp',now()
    ),
    now()
  )
  RETURNING id INTO v_ovr_uuid;

  RETURN jsonb_build_object(
    'generated',true,
    'reused',false,
    'ovr_id',v_ovr_id,
    'ovr_uuid',v_ovr_uuid,
    'task_codigo',p_task_codigo,
    'status',v_status,
    'kbp_ready',v_kbp_integrity>=95,
    'kbp_integrity',v_kbp_integrity,
    'blocked_by',to_jsonb(v_blocked_by),
    'claim_id',v_claim.id,
    'claim_owner',v_claim.claim_owner,
    'claim_expires_at',v_claim.expires_at
  );
END;
$function$;

-- New generator is internal/runtime-only.
REVOKE ALL ON FUNCTION public.generate_ovr(text,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_ovr(text,text,uuid) FROM anon;
REVOKE ALL ON FUNCTION public.generate_ovr(text,text,uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.generate_ovr(text,text,uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. READINESS CLASSIFIER
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_execution_readiness(
  p_task_codigo text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_task record;
  v_claim record;
  v_ovr record;
  v_kbp record;
  v_dep_ok boolean := true;
  v_missing_deps text[] := ARRAY[]::text[];
  v_applicability text;
  v_classification text;
  v_execution_ready boolean := false;
  v_blocking_stage text := null;
  v_blocking_reason text := null;
  v_recommended_action text := null;
  v_all_checks jsonb;
BEGIN
  SELECT *
  INTO v_task
  FROM public.atlas_tasks
  WHERE codigo = p_task_codigo;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'execution_ready',false,
      'classification','BLOCKED',
      'blocking_stage','TASK',
      'blocking_reason','Task not found: '||p_task_codigo,
      'recommended_action',null,
      'all_checks',jsonb_build_object(
        'TASK',jsonb_build_object('status','FAIL')
      ),
      'generated_at',now()
    );
  END IF;

  v_applicability := v_task.ovr_applicability;

  IF v_applicability = 'NOT_REQUIRED' THEN
    RETURN jsonb_build_object(
      'execution_ready',true,
      'classification','NOT_APPLICABLE',
      'blocking_stage',null,
      'blocking_reason',null,
      'recommended_action','Continue normal non-OVR start route',
      'all_checks',jsonb_build_object(
        'TASK',jsonb_build_object('status','PASS'),
        'OVR_APPLICABILITY',jsonb_build_object(
          'status','PASS',
          'value',v_applicability
        )
      ),
      'execution_context',jsonb_build_object(
        'task',jsonb_build_object(
          'codigo',v_task.codigo,
          'titulo',v_task.titulo,
          'prioridad',v_task.prioridad
        ),
        'agent',v_task.asignado_a
      ),
      'generated_at',now()
    );
  END IF;

  IF v_applicability IS NULL OR v_applicability = '' THEN
    RETURN jsonb_build_object(
      'execution_ready',false,
      'classification','APPLICABILITY_UNRESOLVED',
      'blocking_stage','OVR_APPLICABILITY',
      'blocking_reason','ovr_applicability is unresolved',
      'recommended_action','Resolve ovr_applicability before START',
      'all_checks',jsonb_build_object(
        'TASK',jsonb_build_object('status','PASS'),
        'OVR_APPLICABILITY',jsonb_build_object('status','FAIL','value',null)
      ),
      'execution_context',jsonb_build_object(
        'task',jsonb_build_object('codigo',v_task.codigo)
      ),
      'generated_at',now()
    );
  END IF;

  IF v_applicability <> 'REQUIRED' THEN
    RETURN jsonb_build_object(
      'execution_ready',false,
      'classification','BLOCKED',
      'blocking_stage','OVR_APPLICABILITY',
      'blocking_reason','Unsupported ovr_applicability value: '||v_applicability,
      'recommended_action','Normalize ovr_applicability',
      'all_checks',jsonb_build_object(
        'OVR_APPLICABILITY',jsonb_build_object(
          'status','FAIL',
          'value',v_applicability
        )
      ),
      'generated_at',now()
    );
  END IF;

  SELECT *
  INTO v_claim
  FROM public.task_claim_leases
  WHERE task_id = v_task.id
    AND status = 'active'
    AND released_at IS NULL
  ORDER BY claimed_at DESC
  LIMIT 1;

  IF NOT FOUND OR v_claim.expires_at <= now() THEN
    RETURN jsonb_build_object(
      'execution_ready',false,
      'classification','CLAIM_REQUIRED',
      'blocking_stage','CLAIM',
      'blocking_reason',CASE
        WHEN NOT FOUND THEN 'No active claim lease'
        ELSE 'Active claim lease expired'
      END,
      'recommended_action','Claim task lease before OVR generation',
      'all_checks',jsonb_build_object(
        'OVR_APPLICABILITY',jsonb_build_object('status','PASS','value','REQUIRED'),
        'CLAIM',jsonb_build_object(
          'status','FAIL',
          'claim_id',CASE WHEN FOUND THEN v_claim.id ELSE NULL END
        )
      ),
      'generated_at',now()
    );
  END IF;

  SELECT *
  INTO v_ovr
  FROM public.ovr_instances
  WHERE task_codigo = p_task_codigo
    AND status IN ('created','compiled','validated','ready')
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'execution_ready',false,
      'classification','GENERABLE',
      'blocking_stage','OVR',
      'blocking_reason','No current OVR exists for the active claim',
      'recommended_action','Generate OVR using active claim',
      'all_checks',jsonb_build_object(
        'OVR_APPLICABILITY',jsonb_build_object('status','PASS','value','REQUIRED'),
        'CLAIM',jsonb_build_object(
          'status','PASS',
          'claim_id',v_claim.id,
          'claim_owner',v_claim.claim_owner,
          'expires_at',v_claim.expires_at
        ),
        'OVR',jsonb_build_object('status','GENERABLE')
      ),
      'generated_at',now()
    );
  END IF;

  IF (v_ovr.ownership->>'claim_id') IS DISTINCT FROM v_claim.id::text
     OR (v_ovr.ownership->>'claim_owner') IS DISTINCT FROM v_claim.claim_owner
  THEN
    RETURN jsonb_build_object(
      'execution_ready',false,
      'classification','BLOCKED',
      'blocking_stage','CLAIM_BINDING',
      'blocking_reason','OVR ownership is not bound to the active claim',
      'recommended_action','Regenerate OVR under the active claim',
      'all_checks',jsonb_build_object(
        'CLAIM',jsonb_build_object('status','PASS','claim_id',v_claim.id),
        'OVR',jsonb_build_object('status','FAIL','reason','CLAIM_BINDING_MISMATCH')
      ),
      'generated_at',now()
    );
  END IF;

  SELECT integrity,status,generated_at
  INTO v_kbp
  FROM public.kbp_events
  WHERE agent = v_task.asignado_a
  ORDER BY generated_at DESC
  LIMIT 1;

  IF v_task.depende_de IS NOT NULL
     AND array_length(v_task.depende_de,1) IS NOT NULL
  THEN
    SELECT array_agg(codigo)
    INTO v_missing_deps
    FROM public.atlas_tasks
    WHERE codigo = ANY(v_task.depende_de)
      AND estado NOT IN ('completado','resuelto','archivado');

    v_dep_ok := v_missing_deps IS NULL;
  END IF;

  IF v_ovr.status = 'ready'
     AND v_ovr.validated_at IS NOT NULL
     AND v_ovr.validated_at >= now() - interval '60 minutes'
     AND v_task.estado IN ('pendiente','ready','backlog')
     AND COALESCE(v_kbp.integrity,0) >= 95
     AND COALESCE(v_kbp.status,'') = 'ready'
     AND v_dep_ok
  THEN
    v_classification := 'CURRENT';
    v_execution_ready := true;
  ELSE
    v_classification := 'BLOCKED';

    IF v_ovr.status <> 'ready' THEN
      v_blocking_stage := 'OVR';
      v_blocking_reason := 'OVR is not READY; current status='||v_ovr.status;
      v_recommended_action := 'Validate OVR and satisfy READY conditions';
    ELSIF v_ovr.validated_at < now() - interval '60 minutes' THEN
      v_blocking_stage := 'OVR_FRESHNESS';
      v_blocking_reason := 'OVR READY freshness window exceeded';
      v_recommended_action := 'Revalidate OVR under active claim';
    ELSIF v_task.estado NOT IN ('pendiente','ready','backlog') THEN
      v_blocking_stage := 'TASK';
      v_blocking_reason := 'Task is no longer eligible: '||v_task.estado;
      v_recommended_action := 'Do not dispatch';
    ELSIF COALESCE(v_kbp.integrity,0) < 95 OR COALESCE(v_kbp.status,'') <> 'ready' THEN
      v_blocking_stage := 'KBP';
      v_blocking_reason := 'KBP is not current/ready at required integrity';
      v_recommended_action := 'Run KBP certification';
    ELSIF NOT v_dep_ok THEN
      v_blocking_stage := 'DEPENDENCY';
      v_blocking_reason := 'Dependencies unresolved: '||array_to_string(v_missing_deps,', ');
      v_recommended_action := 'Wait for dependencies';
    ELSE
      v_blocking_stage := 'OVR';
      v_blocking_reason := 'READY conditions not satisfied';
      v_recommended_action := 'Revalidate readiness';
    END IF;
  END IF;

  v_all_checks := jsonb_build_object(
    'OVR_APPLICABILITY',jsonb_build_object('status','PASS','value','REQUIRED'),
    'CLAIM',jsonb_build_object(
      'status','PASS',
      'claim_id',v_claim.id,
      'claim_owner',v_claim.claim_owner,
      'expires_at',v_claim.expires_at
    ),
    'OVR',jsonb_build_object(
      'status',v_ovr.status,
      'validated_at',v_ovr.validated_at,
      'ready_at',v_ovr.ready_at
    ),
    'KBP',jsonb_build_object(
      'status',COALESCE(v_kbp.status,'MISSING'),
      'integrity',COALESCE(v_kbp.integrity,0),
      'generated_at',v_kbp.generated_at
    ),
    'DEPENDENCY',jsonb_build_object(
      'status',CASE WHEN v_dep_ok THEN 'PASS' ELSE 'FAIL' END,
      'missing',to_jsonb(COALESCE(v_missing_deps,ARRAY[]::text[]))
    )
  );

  RETURN jsonb_build_object(
    'execution_ready',v_execution_ready,
    'classification',v_classification,
    'blocking_stage',v_blocking_stage,
    'blocking_reason',v_blocking_reason,
    'recommended_action',v_recommended_action,
    'all_checks',v_all_checks,
    'execution_context',jsonb_build_object(
      'task',jsonb_build_object(
        'codigo',v_task.codigo,
        'titulo',v_task.titulo,
        'prioridad',v_task.prioridad
      ),
      'agent',v_task.asignado_a,
      'claim_id',v_claim.id,
      'ovr_id',v_ovr.ovr_id
    ),
    'generated_at',now()
  );
END;
$function$;

-- Readiness is not a public RPC surface.
REVOKE ALL ON FUNCTION public.get_execution_readiness(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_execution_readiness(text) FROM anon;
REVOKE ALL ON FUNCTION public.get_execution_readiness(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_execution_readiness(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. VALIDATE — structural validation followed by READY evaluation.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_ovr(p_ovr_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ovr record;
  v_task record;
  v_claim record;
  v_checks jsonb := '[]'::jsonb;
  v_failures text[] := ARRAY[]::text[];
  v_check jsonb;
  v_kbp_integrity numeric;
  v_blocked_by text[];
  v_blocked_count int;
  v_verdict text;
  v_manifest jsonb;
  v_ready boolean := false;
  v_ready_failures text[] := ARRAY[]::text[];
BEGIN
  SELECT * INTO v_ovr
  FROM public.ovr_instances
  WHERE ovr_id=p_ovr_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error','OVR_NOT_FOUND','ovr_id',p_ovr_id);
  END IF;

  IF v_ovr.status NOT IN ('created','compiled','blocked') THEN
    RETURN jsonb_build_object(
      'error','OVR_NOT_VALIDATABLE',
      'ovr_id',p_ovr_id,
      'status',v_ovr.status
    );
  END IF;

  SELECT * INTO v_task
  FROM public.atlas_tasks
  WHERE codigo=v_ovr.task_codigo;

  SELECT *
  INTO v_claim
  FROM public.task_claim_leases
  WHERE task_id=v_task.id
    AND status='active'
    AND released_at IS NULL
  ORDER BY claimed_at DESC
  LIMIT 1;

  v_check:=jsonb_build_object(
    'check','REQUIRED_BLOCKS',
    'pass',
    v_ovr.identity IS NOT NULL
    AND v_ovr.ownership IS NOT NULL
    AND v_ovr.capability IS NOT NULL
    AND v_ovr.knowledge IS NOT NULL
    AND v_ovr.execution IS NOT NULL
    AND v_ovr.dependencies IS NOT NULL
    AND v_ovr.evidence IS NOT NULL
    AND v_ovr.governance IS NOT NULL
    AND v_ovr.decision IS NOT NULL
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||'REQUIRED_BLOCKS: one or more required blocks absent';
  END IF;

  v_check:=jsonb_build_object(
    'check','CAPABILITY_CONTRACT',
    'pass',
    v_ovr.capability ? 'codigo'
    AND v_ovr.capability ? 'nombre'
    AND v_ovr.capability ? 'spec'
    AND v_ovr.capability ? 'adr',
    'required',jsonb_build_array('codigo','nombre','spec','adr')
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||'CAPABILITY_CONTRACT: codigo/nombre/spec/adr missing';
  END IF;

  v_manifest:=v_ovr.knowledge->'manifest';
  v_check:=jsonb_build_object(
    'check','KNOWLEDGE_MANIFEST',
    'pass',v_manifest IS NOT NULL AND v_manifest <> 'null'::jsonb
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||'KNOWLEDGE_MANIFEST: missing';
  END IF;

  v_kbp_integrity:=coalesce((v_ovr.knowledge->>'integrity_actual')::numeric,0);
  v_check:=jsonb_build_object(
    'check','KBP_INTEGRITY',
    'pass',v_kbp_integrity>=95,
    'required',95,
    'actual',v_kbp_integrity
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||('KBP_INTEGRITY: '||v_kbp_integrity||'% < 95%');
  END IF;

  v_blocked_by:=coalesce(v_task.depende_de,ARRAY[]::text[]);
  SELECT count(*)
  INTO v_blocked_count
  FROM public.atlas_tasks t
  WHERE t.codigo=ANY(v_blocked_by)
    AND t.estado NOT IN ('completado','resuelto','archivado');

  v_check:=jsonb_build_object(
    'check','DEPENDENCIES_CLEAR',
    'pass',v_blocked_count=0,
    'blocked_count',v_blocked_count,
    'blocked_by',to_jsonb(v_blocked_by)
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||('DEPENDENCIES_CLEAR: '||v_blocked_count||' dep(s) sin completar');
  END IF;

  v_check:=jsonb_build_object(
    'check','DECISION_RATIONALE',
    'pass',coalesce(v_ovr.decision->>'rationale','')<>''
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||'DECISION_RATIONALE: vacio';
  END IF;

  v_check:=jsonb_build_object(
    'check','TASK_STATE_ELIGIBLE',
    'pass',v_task.estado IN ('pendiente','ready','backlog'),
    'estado_actual',v_task.estado
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||('TASK_STATE_ELIGIBLE: estado='||v_task.estado);
  END IF;

  v_check:=jsonb_build_object(
    'check','OVR_APPLICABILITY',
    'pass',v_task.ovr_applicability='REQUIRED',
    'actual',v_task.ovr_applicability
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||'OVR_APPLICABILITY: task is not REQUIRED';
  END IF;

  v_check:=jsonb_build_object(
    'check','CLAIM_BINDING',
    'pass',
    v_claim.id IS NOT NULL
    AND v_claim.expires_at > now()
    AND (v_ovr.ownership->>'claim_id') = v_claim.id::text
    AND (v_ovr.ownership->>'claim_owner') = v_claim.claim_owner
  );
  v_checks:=v_checks||v_check;
  IF NOT (v_check->>'pass')::boolean THEN
    v_failures:=v_failures||'CLAIM_BINDING: active claim absent/expired/mismatched';
  END IF;

  v_verdict:=CASE
    WHEN array_length(v_failures,1) IS NULL THEN 'PASS'
    ELSE 'FAIL'
  END;

  IF v_verdict='PASS' THEN
    -- VALIDATED means structural correctness. READY is the operational
    -- eligibility state and is granted only when the lease/KBP/dependency/
    -- freshness conditions below are simultaneously true.
    IF v_task.ovr_applicability='REQUIRED'
       AND v_task.estado IN ('pendiente','ready','backlog')
       AND v_claim.id IS NOT NULL
       AND v_claim.expires_at > now()
       AND (v_ovr.ownership->>'claim_id') = v_claim.id::text
       AND (v_ovr.ownership->>'claim_owner') = v_claim.claim_owner
       AND v_kbp_integrity >= 95
       AND v_blocked_count = 0
       THEN
      v_ready := true;
    END IF;

    UPDATE public.ovr_instances
    SET
      status=CASE WHEN v_ready THEN 'ready' ELSE 'validated' END,
      validated_at=NOW(),
      ready_at=CASE WHEN v_ready THEN NOW() ELSE NULL END,
      blocked_reason=NULL
    WHERE ovr_id=p_ovr_id;
  ELSE
    UPDATE public.ovr_instances
    SET
      status='blocked',
      blocked_reason=array_to_string(v_failures,' | ')
    WHERE ovr_id=p_ovr_id;
  END IF;

  RETURN jsonb_build_object(
    'ovr_id',p_ovr_id,
    'verdict',v_verdict,
    'checks',v_checks,
    'failures',to_jsonb(v_failures),
    'status',
      CASE
        WHEN v_verdict='FAIL' THEN 'blocked'
        WHEN v_ready THEN 'ready'
        ELSE 'validated'
      END,
    'ready',v_ready,
    'ready_semantics','OVR validated and currently eligible for dispatch'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_ovr(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_ovr(text) FROM anon;
REVOKE ALL ON FUNCTION public.validate_ovr(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.validate_ovr(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. DISPATCH — VALIDATED -> READY -> DISPATCHED only.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.dispatch_ovr(p_ovr_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ovr record;
  v_task record;
  v_claim record;
  v_gate jsonb;
  v_trace_id text;
  v_trace_seq int;
  v_trace_uuid uuid;
  v_log_id uuid;
  v_kbp record;
  v_agent text;
  v_capability_codigo text;
BEGIN
  SELECT * INTO v_ovr
  FROM public.ovr_instances
  WHERE ovr_id=p_ovr_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error','OVR_NOT_FOUND',
      'ovr_id',p_ovr_id
    );
  END IF;

  IF v_ovr.status <> 'ready' THEN
    RETURN jsonb_build_object(
      'error','OVR_NOT_READY',
      'ovr_id',p_ovr_id,
      'status_actual',v_ovr.status,
      'hint','READY is required before DISPATCHED'
    );
  END IF;

  SELECT * INTO v_task
  FROM public.atlas_tasks
  WHERE codigo=v_ovr.task_codigo;

  IF v_task.ovr_applicability <> 'REQUIRED' THEN
    RETURN jsonb_build_object(
      'error','OVR_NOT_REQUIRED',
      'ovr_id',p_ovr_id,
      'task_codigo',v_ovr.task_codigo
    );
  END IF;

  SELECT *
  INTO v_claim
  FROM public.task_claim_leases
  WHERE id::text=(v_ovr.ownership->>'claim_id')
    AND task_id=v_task.id
    AND status='active'
    AND released_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error','CLAIM_REQUIRED',
      'ovr_id',p_ovr_id,
      'task_codigo',v_ovr.task_codigo
    );
  END IF;

  IF v_claim.expires_at <= now() THEN
    RETURN jsonb_build_object(
      'error','CLAIM_EXPIRED',
      'ovr_id',p_ovr_id,
      'claim_id',v_claim.id
    );
  END IF;

  IF (v_ovr.ownership->>'claim_owner') IS DISTINCT FROM v_claim.claim_owner THEN
    RETURN jsonb_build_object(
      'error','CLAIM_OWNER_MISMATCH',
      'ovr_id',p_ovr_id,
      'claim_id',v_claim.id
    );
  END IF;

  IF v_ovr.validated_at IS NULL
     OR v_ovr.validated_at < now() - interval '60 minutes'
  THEN
    RETURN jsonb_build_object(
      'error','OVR_STALE',
      'ovr_id',p_ovr_id,
      'validated_at',v_ovr.validated_at,
      'freshness_window_minutes',60
    );
  END IF;

  v_gate := public.get_execution_readiness(v_ovr.task_codigo);

  IF NOT coalesce((v_gate->>'execution_ready')::boolean,false)
     OR coalesce(v_gate->>'classification','') <> 'CURRENT'
  THEN
    RETURN jsonb_build_object(
      'dispatched',false,
      'ovr_id',p_ovr_id,
      'task_codigo',v_ovr.task_codigo,
      'gate_pass',false,
      'blocking_stage',v_gate->>'blocking_stage',
      'blocking_reason',v_gate->>'blocking_reason',
      'recommended_action',v_gate->>'recommended_action',
      'gate_snapshot',v_gate
    );
  END IF;

  v_agent:=coalesce(v_ovr.execution->>'agent',v_task.asignado_a);
  v_capability_codigo:=coalesce(
    v_ovr.capability->>'codigo',
    v_ovr.capability->>'cap_codigo'
  );

  SELECT count(*)+1
  INTO v_trace_seq
  FROM public.ovr_trace
  WHERE date(created_at)=current_date;

  v_trace_id:=
    'OVR-TRACE-'||to_char(now(),'YYYYMMDD')||'-'||
    lpad(v_trace_seq::text,6,'0');

  SELECT integrity,manifest_hash
  INTO v_kbp
  FROM public.kbp_events
  WHERE agent=v_agent
    AND status='ready'
  ORDER BY generated_at DESC
  LIMIT 1;

  INSERT INTO public.logs_operativos(
    nivel,origen,evento,mensaje,payload
  )
  VALUES (
    'INFO',
    'dispatcher/dispatch_ovr',
    'OVR_DISPATCHED',
    'OVR '||p_ovr_id||' despachado a '||v_agent||
      ' para tarea '||v_ovr.task_codigo,
    jsonb_build_object(
      'ovr_id',p_ovr_id,
      'trace_id',v_trace_id,
      'task_codigo',v_ovr.task_codigo,
      'agent',v_agent,
      'claim_id',v_claim.id,
      'gate_checks',v_gate->'all_checks'
    )
  )
  RETURNING id INTO v_log_id;

  INSERT INTO public.ovr_trace(
    trace_id,
    ovr_id,
    task_codigo,
    dispatcher,
    authorized_at,
    capability_codigo,
    knowledge_bundle_hash,
    kbp_integrity,
    agent,
    verification_status,
    notification_sent,
    gate_snapshot
  )
  VALUES (
    v_trace_id,
    p_ovr_id,
    v_ovr.task_codigo,
    'ATLAS-TECH',
    NOW(),
    v_capability_codigo,
    coalesce(v_kbp.manifest_hash,v_ovr.knowledge->>'bundle_hash'),
    coalesce(v_kbp.integrity,(v_ovr.knowledge->>'integrity_actual')::numeric),
    v_agent,
    'PENDING',
    false,
    v_gate
  )
  RETURNING id INTO v_trace_uuid;

  UPDATE public.ovr_instances
  SET status='dispatched',
      dispatched_at=NOW()
  WHERE ovr_id=p_ovr_id
    AND status='ready';

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'dispatched',false,
      'error','RACE_LOST',
      'ovr_id',p_ovr_id
    );
  END IF;

  UPDATE public.atlas_tasks
  SET ejecutor=v_agent,
      updated_at=NOW()
  WHERE codigo=v_ovr.task_codigo
    AND estado IN ('pendiente','ready','backlog');

  RETURN jsonb_build_object(
    'dispatched',true,
    'ovr_id',p_ovr_id,
    'trace_id',v_trace_id,
    'trace_uuid',v_trace_uuid,
    'task_codigo',v_ovr.task_codigo,
    'agent',v_agent,
    'claim_id',v_claim.id,
    'gate_pass',true,
    'dispatched_at',NOW()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.dispatch_ovr(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dispatch_ovr(text) FROM anon;
REVOKE ALL ON FUNCTION public.dispatch_ovr(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_ovr(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. START is intentionally unchanged by D-11.
-- Verify its privileged surface explicitly in review.
-- ---------------------------------------------------------------------------

-- fn_start_ovr(text,text,jsonb) is NOT replaced here.

COMMIT;

-- ---------------------------------------------------------------------------
-- STATIC VERIFICATION QUERIES — DO NOT RUN AS PART OF THIS MIGRATION.
-- ---------------------------------------------------------------------------
-- SELECT p.oid::regprocedure, p.prosecdef, pg_get_functiondef(p.oid)
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN (
--     'generate_ovr',
--     'validate_ovr',
--     'get_execution_readiness',
--     'dispatch_ovr',
--     'fn_start_ovr'
--   );
--
-- SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
--        array_to_string(p.proacl, ', ')
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN (
--     'generate_ovr',
--     'validate_ovr',
--     'get_execution_readiness',
--     'dispatch_ovr',
--     'fn_start_ovr'
--   );
--
-- SELECT status, count(*) FROM public.ovr_instances GROUP BY status ORDER BY status;
-- SELECT ovr_applicability, count(*) FROM public.atlas_tasks GROUP BY ovr_applicability ORDER BY 1;
