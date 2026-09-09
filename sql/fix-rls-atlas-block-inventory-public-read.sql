-- ==============================================================================
-- CANONICAL FIX: RLS Public Read en atlas_block_inventory
-- Archivo: fix-rls-atlas-block-inventory-public-read.sql
-- Propósito: Permitir que el rol 'anon' (visitantes públicos de la web)
--            pueda leer los bloques activos (is_active = true) al abrir
--            el detalle de la oferta /destinos/ofertas/:id y reservar.
-- Causa Raíz Resuelta: RLS bloqueaba la consulta SELECT al rol 'anon'
--                      provocando que la pantalla mostrara 'Oferta no disponible'.
-- ==============================================================================

-- 1. Asegurar que RLS esté activo
ALTER TABLE public.atlas_block_inventory ENABLE ROW LEVEL SECURITY;

-- 2. Crear o reemplazar política de lectura para anon y authenticated
DROP POLICY IF EXISTS "Allow public read active blocks" ON public.atlas_block_inventory;

CREATE POLICY "Allow public read active blocks"
ON public.atlas_block_inventory
FOR SELECT
TO anon, authenticated
USING (is_active = true);

-- 3. Otorgar permisos de SELECT a anon y authenticated
GRANT SELECT ON public.atlas_block_inventory TO anon, authenticated;
