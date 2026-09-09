-- ═══════════════════════════════════════════════════════════════════
-- ATLAS COS — MÓDULO SRM (SUPPLIER RELATIONSHIP MANAGEMENT) v1.0
-- Matrices de Kraljic, Preferencing, Integración Legal (aliun-legal-v1),
-- SLAs y Alineación Canónica con supplier_requests y raw_supplier_evidence
-- Autor: Antigravity / ATLAS-TECH
-- Proyecto Supabase: oyihiyivdhfxpyiwnmqk
-- Fecha: 2026-09-09
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. TABLA CANÓNICA MAESTRA: public.srm_suppliers ───────────────
-- Entidad estructurada única para el flujo administrativo y operativo
CREATE TABLE IF NOT EXISTS public.srm_suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,                       -- ej. 'TRAVELLANDA', 'RATEHAWK', 'VDT', 'HARD_ROCK_PUNTA_CANA'
    name TEXT NOT NULL,
    business_type TEXT NOT NULL DEFAULT 'wholesaler',-- 'wholesaler', 'hotel_chain', 'dmc', 'transport', 'excursions'
    
    -- Segmentación Estratégica (Carla de Kibo / James Kennedy)
    kraljic_quadrant TEXT NOT NULL DEFAULT 'non_critical', -- 'strategic', 'leverage', 'bottleneck', 'non_critical'
    preferencing_quadrant TEXT NOT NULL DEFAULT 'development', -- 'core', 'development', 'exploitative', 'nuisance'
    spend_annual_usd NUMERIC(12,2) DEFAULT 0.00,
    supply_risk_score NUMERIC(5,2) DEFAULT 50.00,    -- 0 a 100
    business_value_score NUMERIC(5,2) DEFAULT 50.00, -- 0 a 100
    customer_attractiveness_score NUMERIC(5,2) DEFAULT 75.00, -- ALIUN como Customer of Choice
    
    -- Gobernanza y Performance (Doctrina SPI-v1)
    spi_score NUMERIC(5,2) DEFAULT 80.00,            -- 0 a 100
    spi_tier TEXT DEFAULT 'silver',                  -- 'gold', 'silver', 'bronze', 'training'
    
    -- Interlocutor Clave (Contract Manager)
    contract_manager_name TEXT,
    contract_manager_email TEXT,
    contract_manager_phone TEXT,
    contract_manager_role TEXT DEFAULT 'Key Account Manager',
    
    -- Marco Jurídico Vinculante (aliun-legal-v1 / CONTRATO-MARCO-PROVEEDOR-v1.0)
    contract_ref TEXT DEFAULT 'CONTRATO-MARCO-PROVEEDOR-v1.0',
    contract_status TEXT DEFAULT 'active',           -- 'active', 'in_renewal', 'under_audit', 'expired'
    contract_start_date DATE DEFAULT CURRENT_DATE,
    contract_end_date DATE DEFAULT (CURRENT_DATE + INTERVAL '1 year'),
    payment_terms TEXT DEFAULT 'deposit_30_cutoff',  -- 'deposit_30_cutoff', 'prepayment_100', 'credit_15d', 'credit_30d'
    cutoff_days INT DEFAULT 15,                      -- Cláusula 4: Fecha de corte
    overbooking_guarantee BOOLEAN DEFAULT true,      -- Cláusula 5: Reubicación o reembolso <= 5d
    sla_dispute_hours INT DEFAULT 72,                -- Cláusula 7: SLA resolución disputas Hermes-QA
    mitur_license_number TEXT,                       -- Cláusula 6: Licencia MITUR
    insurance_policy_number TEXT,                    -- Cláusula 6: Póliza Responsabilidad Civil
    
    -- Portal y Credenciales B2B
    portal_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_srm_suppliers_kraljic ON public.srm_suppliers(kraljic_quadrant);
CREATE INDEX IF NOT EXISTS idx_srm_suppliers_spi_tier ON public.srm_suppliers(spi_tier);
CREATE INDEX IF NOT EXISTS idx_srm_suppliers_code ON public.srm_suppliers(code);


-- ─── 2. TABLA: public.srm_invoices (INVOICE TRACKER / TRANSPARENCIA) ───
CREATE TABLE IF NOT EXISTS public.srm_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID REFERENCES public.srm_suppliers(id) ON DELETE CASCADE,
    supplier_code TEXT NOT NULL,
    invoice_number TEXT NOT NULL,
    booking_ref TEXT,
    amount_usd NUMERIC(10,2) NOT NULL,
    currency TEXT DEFAULT 'USD',
    issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'received',         -- 'received', 'under_review', 'approved', 'scheduled', 'paid', 'disputed'
    payment_date TIMESTAMPTZ,
    payment_method TEXT,
    payment_reference TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_srm_invoices_supplier_id ON public.srm_invoices(supplier_id);
CREATE INDEX IF NOT EXISTS idx_srm_invoices_status ON public.srm_invoices(status);


-- ─── 3. TABLA: public.srm_risk_alerts (CENTRO DE MONITOREO DE RIESGOS) ───
CREATE TABLE IF NOT EXISTS public.srm_risk_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID REFERENCES public.srm_suppliers(id) ON DELETE CASCADE,
    supplier_code TEXT NOT NULL,
    risk_type TEXT NOT NULL,                         -- 'supply_disruption', 'financial', 'overbooking_surge', 'compliance_sla', 'price_discrepancy'
    severity TEXT NOT NULL DEFAULT 'medium',         -- 'low', 'medium', 'high', 'critical'
    title TEXT NOT NULL,
    description TEXT,
    contingency_plan TEXT,
    is_mitigated BOOLEAN DEFAULT false,
    mitigated_at TIMESTAMPTZ,
    mitigated_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_srm_risk_supplier_id ON public.srm_risk_alerts(supplier_id);
CREATE INDEX IF NOT EXISTS idx_srm_risk_severity ON public.srm_risk_alerts(severity);


-- ─── 4. TABLA: public.srm_qbr_reviews (REVISIONES TRIMESTRALES & ESI) ───
CREATE TABLE IF NOT EXISTS public.srm_qbr_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID REFERENCES public.srm_suppliers(id) ON DELETE CASCADE,
    supplier_code TEXT NOT NULL,
    quarter TEXT NOT NULL,                           -- 'Q1-2026', 'Q2-2026', 'Q3-2026', 'Q4-2026'
    meeting_date DATE NOT NULL,
    lead_aliun TEXT DEFAULT 'Aldo Hilario',
    lead_supplier TEXT,
    performance_score NUMERIC(3,1) DEFAULT 4.5,
    innovation_proposals TEXT,
    gain_sharing_agreement TEXT,
    action_items JSONB DEFAULT '[]'::jsonb,
    status TEXT DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT now()
);


-- ─── 5. CORRECCIÓN DE ALINEACIÓN 1: supplier_requests.supplier_id ───
-- Agrega FK estructurada preservando el campo textual 'proveedor' para retrocompatibilidad
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'supplier_requests' 
          AND column_name = 'supplier_id'
    ) THEN
        ALTER TABLE public.supplier_requests 
        ADD COLUMN supplier_id UUID REFERENCES public.srm_suppliers(id);
    END IF;
END $$;


-- ─── 6. CORRECCIÓN DE ALINEACIÓN 2: Ingesta Operativa (raw_supplier_evidence) ───
-- Vincula el flujo de ingesta no estructurada a la entidad maestra srm_suppliers
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'raw_supplier_evidence'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = 'raw_supplier_evidence' 
              AND column_name = 'supplier_id'
        ) THEN
            ALTER TABLE public.raw_supplier_evidence 
            ADD COLUMN supplier_id UUID REFERENCES public.srm_suppliers(id);
        END IF;
    END IF;
END $$;

-- En ingestion_attempts (para trazabilidad de resolución de proveedor)
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'ingestion_attempts'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = 'ingestion_attempts' 
              AND column_name = 'resolved_supplier_id'
        ) THEN
            ALTER TABLE public.ingestion_attempts 
            ADD COLUMN resolved_supplier_id UUID REFERENCES public.srm_suppliers(id);
        END IF;
    END IF;
END $$;


-- ─── 7. SEED CANÓNICO DE PROVEEDORES FUNDACIONALES ─────────────────
INSERT INTO public.srm_suppliers (
    code, name, business_type, kraljic_quadrant, preferencing_quadrant,
    spend_annual_usd, supply_risk_score, business_value_score, customer_attractiveness_score,
    spi_score, spi_tier, contract_manager_name, contract_manager_email, contract_manager_phone,
    contract_ref, contract_status, payment_terms, cutoff_days, overbooking_guarantee,
    sla_dispute_hours, mitur_license_number, insurance_policy_number, portal_url
) VALUES
(
    'TRAVELLANDA', 'Travellanda Ltd (UK/B2B)', 'wholesaler', 'strategic', 'core',
    485000.00, 75.00, 88.00, 92.00,
    94.50, 'gold', 'Elena Rostova', 'elena.r@travellanda.com', '+44 20 3384 5720',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'active', 'deposit_30_cutoff', 14, true,
    72, 'MITUR-OP-UK-8821', 'POL-ALLIANZ-TRV-2026', 'https://online.travellanda.com'
),
(
    'RATEHAWK', 'RateHawk (Emerging Travel Group)', 'wholesaler', 'strategic', 'core',
    390000.00, 68.00, 82.00, 90.00,
    91.00, 'gold', 'Carlos Mendez', 'carlos.m@ratehawk.com', '+34 91 123 4567',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'active', 'credit_15d', 10, true,
    72, 'MITUR-INTL-9904', 'POL-ZURICH-RH-4410', 'https://www.ratehawk.com'
),
(
    'VDT', 'VDT Mayorista Receptivo RD', 'dmc', 'leverage', 'core',
    240000.00, 35.00, 70.00, 85.00,
    88.00, 'silver', 'Juan Pablo Duarte M.', 'operaciones@vdtcaribe.com', '+1 809 552 1100',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'active', 'deposit_30_cutoff', 7, true,
    72, 'MITUR-RD-2024-0018', 'POL-BANRESERVAS-8812', 'https://vdtcaribe.com'
),
(
    'HARD_ROCK_PUNTA_CANA', 'Hard Rock Hotel & Casino Punta Cana', 'hotel_chain', 'strategic', 'core',
    520000.00, 80.00, 95.00, 94.00,
    96.00, 'gold', 'Marcos Santana', 'msantana@hardrockhotelpuntacana.com', '+1 809 687 0000',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'active', 'deposit_30_cutoff', 21, true,
    72, 'MITUR-HOTEL-PC-0045', 'POL-MAPFRE-HR-9988', 'https://www.hardrockhotelpuntacana.com'
),
(
    'MELIA_HOTELS_RD', 'Meliá Hotels International (Caribe)', 'hotel_chain', 'leverage', 'development',
    310000.00, 40.00, 78.00, 82.00,
    89.00, 'silver', 'Raquel Benitez', 'raquel.benitez@melia.com', '+1 809 221 1290',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'active', 'credit_30d', 15, true,
    72, 'MITUR-HOTEL-MEL-1029', 'POL-MAPFRE-MEL-2026', 'https://www.melia.com'
),
(
    'OCEAN_WORLD', 'Ocean World Adventure Park (Puerto Plata)', 'excursions', 'bottleneck', 'development',
    75000.00, 70.00, 45.00, 78.00,
    82.50, 'silver', 'Teresa Almonte', 'ventas@oceanworld.net', '+1 809 291 1000',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'active', 'prepayment_100', 3, true,
    72, 'MITUR-EXC-POP-0331', 'POL-UNIVERSAL-OW-5544', 'https://oceanworld.net'
),
(
    'GENIALL', 'Geniall Tours Receptivo Local', 'dmc', 'non_critical', 'nuisance',
    25000.00, 20.00, 25.00, 60.00,
    74.00, 'training', 'Ramon Gomez', 'rgomez@geniall.com', '+1 809 555 0199',
    'CONTRATO-MARCO-PROVEEDOR-v1.0', 'in_renewal', 'prepayment_100', 2, false,
    72, 'MITUR-OP-LOC-7721', 'POL-MONUMENTAL-1122', 'https://geniall.com'
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    kraljic_quadrant = EXCLUDED.kraljic_quadrant,
    preferencing_quadrant = EXCLUDED.preferencing_quadrant,
    spend_annual_usd = EXCLUDED.spend_annual_usd,
    spi_score = EXCLUDED.spi_score,
    spi_tier = EXCLUDED.spi_tier,
    contract_manager_name = EXCLUDED.contract_manager_name,
    contract_manager_email = EXCLUDED.contract_manager_email,
    contract_manager_phone = EXCLUDED.contract_manager_phone,
    payment_terms = EXCLUDED.payment_terms,
    cutoff_days = EXCLUDED.cutoff_days,
    overbooking_guarantee = EXCLUDED.overbooking_guarantee,
    mitur_license_number = EXCLUDED.mitur_license_number,
    insurance_policy_number = EXCLUDED.insurance_policy_number,
    portal_url = EXCLUDED.portal_url,
    updated_at = now();


-- ─── 8. BACKFILL AUTOMÁTICO EN supplier_requests ───────────────────
-- Actualiza los registros existentes para que supplier_id apunte a srm_suppliers
UPDATE public.supplier_requests sr
SET supplier_id = s.id
FROM public.srm_suppliers s
WHERE LOWER(sr.proveedor) = LOWER(s.code)
  AND sr.supplier_id IS NULL;


-- ─── 9. SEED INVOICES & RISK ALERTS INICIALES ───────────────────────
INSERT INTO public.srm_invoices (supplier_id, supplier_code, invoice_number, booking_ref, amount_usd, due_date, status, notes)
SELECT s.id, s.code, 'INV-TRV-2026-8812', 'BK-TEST-2026-X9', 1450.00, CURRENT_DATE + INTERVAL '5 days', 'approved', 'Cupo Serenade All Suites confirmado'
FROM public.srm_suppliers s WHERE s.code = 'TRAVELLANDA'
ON CONFLICT DO NOTHING;

INSERT INTO public.srm_invoices (supplier_id, supplier_code, invoice_number, booking_ref, amount_usd, due_date, status, notes)
SELECT s.id, s.code, 'INV-HR-2026-0941', 'BK-2026-HR-001', 3240.00, CURRENT_DATE + INTERVAL '12 days', 'scheduled', 'Bloqueo Caribe Suite Q4'
FROM public.srm_suppliers s WHERE s.code = 'HARD_ROCK_PUNTA_CANA'
ON CONFLICT DO NOTHING;

INSERT INTO public.srm_risk_alerts (supplier_id, supplier_code, risk_type, severity, title, description, contingency_plan)
SELECT s.id, s.code, 'supply_disruption', 'medium', 'Demora en acuse de recibo de modificaciones (>4h)', 'El proveedor ha excedido el SLA en 2 solicitudes recientes.', 'Derivar solicitudes urgentes a RateHawk o VDT mientras se regulariza.'
FROM public.srm_suppliers s WHERE s.code = 'TRAVELLANDA'
ON CONFLICT DO NOTHING;
