-- ═══════════════════════════════════════════════════════════════════
-- CANONICAL MIGRATION: CORE2-003 — Validation Gate & QA Queue
-- Archivo: core2-003-validation-gate-and-qa-queue.sql
-- Propósito: Implementar compuerta de validación determinista antes
--            de persistir en atlas_block_inventory. Cargas inválidas
--            (fechas pasadas, tarifas <= 0, slugs no registrados o
--            monedas ilegales) se desvían a block_qa_queue para auditoría.
-- Autoridad: Director Soberano Aldo Hilario / Antigravity (ATLAS-TECH)
-- Fecha: 2026-09-26
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── TABLA 1: block_qa_queue ───────────────────────────────────
-- Almacena los bloques rechazados por el gate de validación.
-- Permite triage humano o corrección guiada sin contaminar
-- el inventario comercializable de Core 2.
CREATE TABLE IF NOT EXISTS public.block_qa_queue (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    raw_evidence_id     uuid REFERENCES public.raw_supplier_evidence(id),
    provider_code       text REFERENCES public.local_providers(provider_code),
    hotel_slug          text,
    payload             jsonb NOT NULL,
    rejection_reasons   text[] NOT NULL,
    status              text NOT NULL DEFAULT 'pending_review'
                        CHECK (status IN ('pending_review', 'resolved', 'discarded')),
    reviewed_by         text,
    reviewed_at         timestamptz,
    resolution_notes    text,
    created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.block_qa_queue IS
    'Cola de cuarentena y auditoría para bloqueos de proveedores que fallaron el gate de validación de Core 2.';

CREATE INDEX IF NOT EXISTS idx_block_qa_queue_raw_evidence ON public.block_qa_queue(raw_evidence_id);
CREATE INDEX IF NOT EXISTS idx_block_qa_queue_status       ON public.block_qa_queue(status);
CREATE INDEX IF NOT EXISTS idx_block_qa_queue_created      ON public.block_qa_queue(created_at DESC);

-- RLS
ALTER TABLE public.block_qa_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_block_qa_queue_all" ON public.block_qa_queue;
CREATE POLICY "service_role_block_qa_queue_all"
    ON public.block_qa_queue FOR ALL TO service_role
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated_block_qa_queue_read" ON public.block_qa_queue;
CREATE POLICY "authenticated_block_qa_queue_read"
    ON public.block_qa_queue FOR SELECT TO authenticated
    USING (true);


-- ─── FUNCION 2: validate_and_ingest_block_inventory ─────────────
-- Puerta de enlace obligatoria para la inserción en atlas_block_inventory.
-- Valida reglas canónicas:
--   1. check_in >= CURRENT_DATE
--   2. check_out > check_in
--   3. rate_dbl > 0 OR rate_sgl > 0
--   4. hotel_slug existe en hotels_master
--   5. currency IN ('USD', 'DOP')
CREATE OR REPLACE FUNCTION public.validate_and_ingest_block_inventory(
    p_raw_evidence_id   uuid,
    p_provider_code     text,
    p_hotel_slug        text,
    p_hotel_name        text,
    p_check_in          date,
    p_check_out         date,
    p_room_category     text,
    p_rate_dbl          numeric DEFAULT NULL,
    p_rate_tpl          numeric DEFAULT NULL,
    p_rate_sgl          numeric DEFAULT NULL,
    p_rate_chd          numeric DEFAULT NULL,
    p_currency          text DEFAULT 'USD',
    p_rooms_available   integer DEFAULT 1,
    p_source            text DEFAULT 'manual',
    p_confirmation_code text DEFAULT NULL,
    p_gratuity_policy   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_errors text[] := ARRAY[]::text[];
    v_hotel_exists boolean;
    v_new_id uuid;
    v_queue_id uuid;
    v_payload jsonb;
BEGIN
    -- 1. Validar fechas futuras
    IF p_check_in IS NULL THEN
        v_errors := array_append(v_errors, 'CHECK_IN_NULL: La fecha de check-in es obligatoria');
    ELSIF p_check_in < CURRENT_DATE THEN
        v_errors := array_append(v_errors, 'CHECK_IN_PAST: La fecha de check-in no puede estar en el pasado');
    END IF;

    IF p_check_out IS NULL THEN
        v_errors := array_append(v_errors, 'CHECK_OUT_NULL: La fecha de check-out es obligatoria');
    ELSIF p_check_in IS NOT NULL AND p_check_out <= p_check_in THEN
        v_errors := array_append(v_errors, 'INVALID_DATE_RANGE: El check-out debe ser posterior al check-in');
    END IF;

    -- 2. Validar precios > 0
    IF COALESCE(p_rate_dbl, 0) <= 0 AND COALESCE(p_rate_sgl, 0) <= 0 THEN
        v_errors := array_append(v_errors, 'INVALID_RATES: Se requiere al menos una tarifa (rate_dbl o rate_sgl) mayor a 0');
    END IF;

    -- 3. Validar existencia de hotel_slug en hotels_master
    IF p_hotel_slug IS NULL OR trim(p_hotel_slug) = '' THEN
        v_errors := array_append(v_errors, 'HOTEL_SLUG_NULL: El slug del hotel es obligatorio');
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM public.hotels_master WHERE slug = p_hotel_slug
        ) INTO v_hotel_exists;

        IF NOT v_hotel_exists THEN
            v_errors := array_append(v_errors, 'HOTEL_NOT_FOUND: El hotel_slug "' || p_hotel_slug || '" no existe en hotels_master');
        END IF;
    END IF;

    -- 4. Validar moneda
    IF p_currency IS NULL OR UPPER(trim(p_currency)) NOT IN ('USD', 'DOP') THEN
        v_errors := array_append(v_errors, 'INVALID_CURRENCY: Moneda no autorizada. Solo se permite USD o DOP');
    END IF;

    -- Construir payload completo para trazabilidad
    v_payload := jsonb_build_object(
        'raw_evidence_id', p_raw_evidence_id,
        'provider_code', p_provider_code,
        'hotel_slug', p_hotel_slug,
        'hotel_name', p_hotel_name,
        'check_in', p_check_in,
        'check_out', p_check_out,
        'room_category', p_room_category,
        'rate_dbl', p_rate_dbl,
        'rate_tpl', p_rate_tpl,
        'rate_sgl', p_rate_sgl,
        'rate_chd', p_rate_chd,
        'currency', UPPER(p_currency),
        'rooms_available', p_rooms_available,
        'source', p_source,
        'confirmation_code', p_confirmation_code,
        'gratuity_policy', p_gratuity_policy
    );

    -- Evaluar resultado de validación
    IF array_length(v_errors, 1) > 0 THEN
        -- RECHAZADO: Persistir en block_qa_queue
        INSERT INTO public.block_qa_queue (
            raw_evidence_id,
            provider_code,
            hotel_slug,
            payload,
            rejection_reasons,
            status
        ) VALUES (
            p_raw_evidence_id,
            p_provider_code,
            p_hotel_slug,
            v_payload,
            v_errors,
            'pending_review'
        )
        RETURNING id INTO v_queue_id;

        RETURN jsonb_build_object(
            'success', false,
            'gate_action', 'REJECTED_TO_QA_QUEUE',
            'queue_id', v_queue_id,
            'rejection_reasons', v_errors,
            'payload', v_payload
        );
    ELSE
        -- APROBADO: Insertar en atlas_block_inventory
        INSERT INTO public.atlas_block_inventory (
            raw_evidence_id,
            provider_code,
            hotel_slug,
            hotel_name,
            check_in,
            check_out,
            room_category,
            rate_dbl,
            rate_tpl,
            rate_sgl,
            rate_chd,
            currency,
            rooms_available,
            source,
            confirmation_code,
            gratuity_policy,
            is_active
        ) VALUES (
            p_raw_evidence_id,
            p_provider_code,
            p_hotel_slug,
            p_hotel_name,
            p_check_in,
            p_check_out,
            p_room_category,
            p_rate_dbl,
            p_rate_tpl,
            p_rate_sgl,
            p_rate_chd,
            UPPER(p_currency),
            COALESCE(p_rooms_available, 1),
            COALESCE(p_source, 'manual'),
            p_confirmation_code,
            p_gratuity_policy,
            true
        )
        RETURNING id INTO v_new_id;

        RETURN jsonb_build_object(
            'success', true,
            'gate_action', 'INSERTED_TO_BLOCK_INVENTORY',
            'block_id', v_new_id,
            'hotel_slug', p_hotel_slug,
            'check_in', p_check_in,
            'check_out', p_check_out
        );
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_and_ingest_block_inventory TO service_role, authenticated;

COMMIT;
