-- ==============================================================================
-- CANONICAL MIGRATION: Unificación Core 2 (atlas_block_inventory) & Marketing Offers
-- Archivo: core2-consultar-ofertas-agrupadas-unification.sql
-- Propósito: Conectar atlas_block_inventory directamente con la RPC pública
--            consultar_ofertas_agrupadas() para que los bloqueos de Logitur,
--            Gniall y proveedores Core 2 aparezcan como B2C Selectable Units
--            en la web /destinos/ofertas sin requerir cambios en el frontend.
-- Autoridad: Director Soberano Aldo Hilario / Antigravity (ATLAS-TECH)
-- Fecha: 2026-09-09
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.consultar_ofertas_agrupadas(
    p_offer_type text DEFAULT NULL
)
RETURNS TABLE (
    hotel_name text,
    hotel_slug text,
    zone text,
    stars integer,
    about_image text,
    min_precio numeric,
    total_fechas integer,
    offer_type text,
    fechas_disponibles jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH all_dates AS (
        -- 1. Fechas desde marketing_offers + offer_date_ranges
        SELECT 
            COALESCE(h.name, mo.title, 'Hotel Exclusivo')::text AS hotel_name,
            COALESCE(h.slug, mo.hotel_slug)::text AS hotel_slug,
            COALESCE(h.zone, h.location, 'República Dominicana')::text AS zone,
            COALESCE(h.stars, 4)::integer AS stars,
            COALESCE(h.about_image, mo.provider_image_url, 'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=800&q=80')::text AS about_image,
            COALESCE(mo.offer_type, 'last_minute')::text AS offer_type,
            mo.id::text AS offer_id,
            odr.id::text AS date_range_id,
            odr.check_in::text AS check_in,
            odr.check_out::text AS check_out,
            GREATEST(1, COALESCE(odr.nights, (odr.check_out - odr.check_in)))::integer AS nights,
            ROUND(COALESCE(odr.price_override, mo.final_price, mo.original_price, 0)::numeric, 2) AS precio,
            ('/destinos/ofertas/' || mo.id::text || '?date_range_id=' || odr.id::text)::text AS url,
            COALESCE(mo.currency_original, 'USD')::text AS moneda,
            CASE WHEN mo.currency_original = 'DOP' THEN 'RD$' ELSE '$' END::text AS simbolo_moneda
        FROM public.marketing_offers mo
        JOIN public.offer_date_ranges odr ON odr.offer_id = mo.id
        LEFT JOIN public.hotels h ON (h.id = mo.hotel_id OR h.slug = mo.hotel_slug)
        WHERE mo.is_published = true
          AND odr.is_active = true
          AND odr.check_in >= CURRENT_DATE
          AND (p_offer_type IS NULL OR p_offer_type = 'all' OR mo.offer_type = p_offer_type)

        UNION ALL

        -- 2. Fechas desde atlas_block_inventory (Core 2: Bloqueos Logitur, Gniall, VDT, etc.)
        SELECT 
            COALESCE(h.name, abi.hotel_name, 'Hotel Destacado')::text AS hotel_name,
            COALESCE(h.slug, abi.hotel_slug)::text AS hotel_slug,
            COALESCE(h.zone, h.location, 'Caribe Dominicano')::text AS zone,
            COALESCE(h.stars, 4)::integer AS stars,
            COALESCE(h.about_image, 'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=800&q=80')::text AS about_image,
            'flash_sale'::text AS offer_type,
            abi.id::text AS offer_id,
            abi.id::text AS date_range_id,
            abi.check_in::text AS check_in,
            abi.check_out::text AS check_out,
            GREATEST(1, (abi.check_out - abi.check_in))::integer AS nights,
            ROUND((CASE 
                WHEN abi.rate_dbl > 0 THEN abi.rate_dbl 
                WHEN abi.rate_sgl > 0 THEN abi.rate_sgl 
                ELSE 100 
            END)::numeric, 2) AS precio,
            ('/destinos/ofertas/' || abi.id::text || '?date_range_id=' || abi.id::text || '&source=block')::text AS url,
            COALESCE(abi.currency, 'USD')::text AS moneda,
            CASE WHEN abi.currency = 'DOP' THEN 'RD$' ELSE '$' END::text AS simbolo_moneda
        FROM public.atlas_block_inventory abi
        LEFT JOIN public.hotels h ON h.slug = abi.hotel_slug
        WHERE abi.is_active = true
          AND abi.check_in >= CURRENT_DATE
          AND (abi.rooms_available IS NULL OR abi.rooms_available > 0)
          AND (abi.rate_dbl > 0 OR abi.rate_sgl > 0)
          AND (p_offer_type IS NULL OR p_offer_type = 'all' OR p_offer_type = 'flash_sale')
    ),
    grouped_hotels AS (
        SELECT 
            ad.hotel_name,
            ad.hotel_slug,
            ad.zone,
            ad.stars,
            ad.about_image,
            MIN(ad.precio) AS min_precio,
            COUNT(ad.date_range_id)::integer AS total_fechas,
            ad.offer_type,
            jsonb_agg(
                jsonb_build_object(
                    'offer_id', ad.offer_id,
                    'date_range_id', ad.date_range_id,
                    'check_in', ad.check_in,
                    'check_out', ad.check_out,
                    'nights', ad.nights,
                    'precio', ad.precio,
                    'url', ad.url,
                    'moneda', ad.moneda,
                    'simbolo_moneda', ad.simbolo_moneda
                ) ORDER BY ad.check_in ASC
            ) AS fechas_disponibles
        FROM all_dates ad
        WHERE ad.hotel_slug IS NOT NULL
        GROUP BY 
            ad.hotel_name,
            ad.hotel_slug,
            ad.zone,
            ad.stars,
            ad.about_image,
            ad.offer_type
    )
    SELECT 
        gh.hotel_name,
        gh.hotel_slug,
        gh.zone,
        gh.stars,
        gh.about_image,
        gh.min_precio,
        gh.total_fechas,
        gh.offer_type,
        gh.fechas_disponibles
    FROM grouped_hotels gh
    ORDER BY gh.min_precio ASC;
END;
$$;

-- Permisos canónicos
GRANT EXECUTE ON FUNCTION public.consultar_ofertas_agrupadas(text) TO anon, authenticated, service_role;
