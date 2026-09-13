# ATLAS ECOSYSTEM — MAPA DE CABLEADO COMERCIAL
**Versión:** 1.0 | **Fecha:** 23 Jul 2026 | **Owner:** ATLAS-TECH
**Ruta:** `atlas-api-toolbox/CABLE-MAP-v1.md`

> Este documento es el mapa canónico de todas las conexiones entre plataformas
> del ecosistema ATLAS. Cada cable tiene un estado, owner, y próximo paso.

---

## INVENTARIO DE PLATAFORMAS

```
ATLAS ECOSYSTEM:
  aliuntravelsrl.com (atlas-booking-frontend-v2)
  atlas.aliuntravelsrl.com (admin -atlas-admin-v2)
  Supabase oyihiyivdhfxpyiwnmqk (SSOT)
  n8n n8n-n8n.xaruuo.easypanel.host
  Chatwoot (chatwoot)
  
META:
  Pixel ID: [PENDIENTE CONFIRMAR]
  Cuenta Ads: 328851958884001 (ALIUN TRAVEL) ✅
  Cuenta Ads: 1334831048751663 (ALIUN TRAVEL SRL) ✅
  Página: 1706567843003643 (ALIUN Travel SRL) ✅
  WhatsApp: +1 829-964-8443 (Scam Strike — NO tocar)
  MCP Meta: mcp.facebook.com/ads ✅ conectado
  
GOOGLE:
  GA4: ✅ instalado en navbar frontend
  GTM: ✅ instalado en navbar frontend
  Google Business Profile: ✅ VERIFICADO por Director
  Google Search Console: ⏳ pendiente vincular
  
TIKTOK:
  @aliuntravelsrl ✅ activo
  TikTok Marketing API: 03-tiktok/ (GTI disponible)

DESKTOP COMMANDER MCP:
  Repo: wonderwhy-er/desktopcommandermcp ✅
  Paquete: @wonderwhy-er/desktop-commander ✅
  Estado Local (DESKTOP-2HAFT48): ✅ CONECTADO / ONLINE
  Documentación: 06-desktop-commander/GTI-DESKTOP-COMMANDER-MCP.md ✅
```

---

## CHECKLIST DE CABLES

### 🔴 CABLE 1 — Meta CAPI + Pixel (Dual Tracking)
**Documentación:** `01-meta/conversions-api/GTI-META-CONVERSIONS-API.md`
**Por qué es crítico:** Sin CAPI, Meta no puede optimizar hacia ventas reales. El Pixel solo (client-side) pierde eventos por iOS 14+, ad blockers, privacy browsers.

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 1.1 | Confirmar Pixel ID instalado en GTM | Antigravity | ⏳ |
| 1.2 | Crear Access Token en Meta Business Manager | Director | ⏳ |
| 1.3 | Crear WF-META-CAPI en n8n (webhook → graph API) | ATLAS-TECH | ⏳ |
| 1.4 | Enviar evento `Lead` al CAPI cuando llega mensaje Chatwoot | ATLAS-TECH | ⏳ |
| 1.5 | Enviar evento `InitiateCheckout` al cotizar | Antigravity + ATLAS-TECH | ⏳ |
| 1.6 | Enviar evento `Purchase` al confirmar reserva (deposito_recibido) | ATLAS-TECH | ⏳ |
| 1.7 | Deduplicación: event_id compartido entre Pixel y CAPI | Antigravity | ⏳ |
| 1.8 | Verificar en Events Manager que llegan eventos server-side | Director | ⏳ |

**Payload CAPI por evento:**
```json
{
  "data": [{
    "event_name": "Lead",
    "event_time": 1234567890,
    "event_id": "CRM-{lead_id}-{timestamp}",
    "user_data": {
      "ph": "{phone_hashed_sha256}",
      "ct": "santo domingo",
      "country": "do"
    },
    "custom_data": {
      "lead_id": "{crm_lead_id}",
      "canal": "whatsapp",
      "hotel": "{hotel_name}"
    },
    "action_source": "website"
  }],
  "access_token": "{META_ACCESS_TOKEN}"
}
```

---

### 🔴 CABLE 2 — Meta Marketing API (MAPI) → n8n
**Documentación:** `01-meta/marketing-api/GTI-META-MARKETING-API.md`
**Por qué es crítico:** Hermes Marketing necesita crear/publicar anuncios via API en lugar de hacerlo manualmente.

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 2.1 | Generar System User Token en Meta Business Manager | Director | ⏳ |
| 2.2 | Configurar credencial Meta API en n8n | Antigravity | ⏳ |
| 2.3 | WF-META-PUBLISH-POST: publicar posts en página desde n8n | ATLAS-TECH | ⏳ |
| 2.4 | WF-META-CREATE-AD: crear campañas desde Hermes Marketing | ATLAS-TECH | ⏳ |
| 2.5 | WF-META-LEADS: webhook de leads de Facebook Lead Ads → CRM | ATLAS-TECH | ⏳ |
| 2.6 | Conectar MCP Meta en Claude.ai Settings con permisos de ads | Director | ⏳ |

---

### 🟡 CABLE 3 — GA4 → Google Search Console → Business Profile
**Documentación:** `02-google/` (GTI disponible)
**Por qué:** Vincular todo el stack de Google para visión 360°.

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 3.1 | Verificar propiedad GSC (usar GTM tag ya instalado) | Director | ⏳ |
| 3.2 | Vincular GSC → GA4 (Admin → Search Console Linking) | Director | ⏳ |
| 3.3 | Vincular Business Profile → GA4 | Director | ⏳ |
| 3.4 | Configurar 4 eventos conversión en GTM (SEO-ANALYTICS-001) | Antigravity | ⏳ |
| 3.5 | Crear audiencias GA4 para remarketing Meta | Antigravity | ⏳ |
| 3.6 | Vincular GA4 → Meta Ads (cuenta 328851958884001) | Antigravity | ⏳ |

---

### 🟡 CABLE 4 — WhatsApp Business API → Chatwoot → CRM
**Documentación:** `01-meta/whatsapp-business-api-v23.0/GTI-WHATSAPP-BUSINESS-API-v23.0.md`
**Estado actual:** WA en Scam Strike. NO cambiar configuración del número.

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 4.1 | Esperar resolución Scam Strike +1 829-964-8443 | Meta (automático) | ⏳ |
| 4.2 | Verificar webhook Chatwoot → WF-CHATWOOT-HERMES-v1 | Hermes Ops | ⏳ |
| 4.3 | Canal WA → canal_recibir_mensaje() → session layer | ATLAS-TECH | ✅ |
| 4.4 | Atribución: WA lead → crm_leads.source = 'whatsapp' | ATLAS-TECH | ✅ |
| 4.5 | CAPI: enviar evento Lead cuando WA lead entra al CRM | ATLAS-TECH | ⏳ |

---

### 🟠 CABLE 5 — TikTok Marketing API
**Documentación:** `03-tiktok/tiktok-marketing-api/GTI-TIKTOK-MARKETING-API.md`

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 5.1 | Crear cuenta TikTok Business | Director | ⏳ |
| 5.2 | TikTok Pixel en frontend (GTM) | Antigravity | ⏳ |
| 5.3 | TikTok Events API server-side (como CAPI de Meta) | ATLAS-TECH | ⏳ |
| 5.4 | Credencial TikTok en n8n | Antigravity | ⏳ |
| 5.5 | WF-TIKTOK-PUBLISH: publicar videos via API | ATLAS-TECH | ⏳ |

---

### 🔵 CABLE 6 — Supabase → Meta CAPI (Attribution Loop)
**El cable que cierra el loop completo.**

```
Meta Ad (anuncio) → Cliente hace clic
    ↓ fbclid capturado en URL
aliuntravelsrl.com → GTM captura fbclid
    ↓ se guarda en crm_leads.meta_fbclid
Chatwoot / WhatsApp → Lead entra al CRM
    ↓ CRM tiene el fbclid
n8n WF-META-CAPI → envía Purchase a Meta con fbclid
    ↓
Meta sabe que ese anuncio generó esa reserva
    ↓ ROAS real calculado
```

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 6.1 | Añadir campo `meta_fbclid` en crm_leads | ATLAS-TECH | ⏳ |
| 6.2 | GTM captura fbclid de URL → dataLayer | Antigravity | ⏳ |
| 6.3 | Pasar fbclid en el payload del CAPI (user_data.fbc) | ATLAS-TECH | ⏳ |
| 6.4 | Evento Purchase cuando booking pasa a completado | ATLAS-TECH | ⏳ |

---

### 🔵 CABLE 7 — MCP Meta en Claude.ai (ATLAS-TECH directo)
**Capacidad:** Desde aquí puedo gestionar campañas y leads directamente.

| Paso | Descripción | Owner | Estado |
|------|-------------|-------|--------|
| 7.1 | Confirmar MCP Meta conectado con permisos correctos | Director | ⏳ |
| 7.2 | Confirmar Pixel ID para CAPI | Director → ATLAS-TECH | ⏳ |
| 7.3 | Listar campañas activas vía MCP | ATLAS-TECH | ⏳ |
| 7.4 | Crear audiencias personalizadas vía MCP | ATLAS-TECH | ⏳ |

---

## SECUENCIA DE EJECUCIÓN RECOMENDADA

```
SEMANA 1 — Base:
  Cable 3.1-3.3 → Director (30 min en Google)
  Cable 1.1 → Antigravity (confirmar Pixel ID)
  Cable 7.1-7.2 → Director (Pixel ID + MCP Meta permisos)

SEMANA 2 — CAPI (el más crítico):
  Cable 1.2 → Director genera Access Token Meta
  Cable 1.3-1.6 → ATLAS-TECH construye WF-META-CAPI
  Cable 1.7-1.8 → Antigravity + Director verifica

SEMANA 3 — Marketing API + GA4:
  Cable 2.1-2.5 → Director + ATLAS-TECH
  Cable 3.4-3.6 → Antigravity (SEO-ANALYTICS-001)
  Cable 6.1-6.4 → ATLAS-TECH cierra el attribution loop

DESPUÉS:
  Cable 4.1 → esperar Meta resuelva Scam Strike
  Cable 5.1-5.5 → TikTok (cuando sea prioridad)
```

---

## EL CABLE MÁS IMPORTANTE

**Cable 1 (CAPI)** es el que convierte toda la infraestructura en máquina de atribución.

Sin CAPI:
- Meta no sabe qué anuncio generó cada reserva
- No puede optimizar
- ROAS calculado es incorrecto

Con CAPI:
- Cada reserva se atribuye al anuncio correcto
- Meta optimiza hacia clientes que realmente reservan
- ROAS real visible en Ads Manager
- Audiencias lookalike de compradores reales

*ATLAS-TECH · 23 Jul 2026 · atlas-api-toolbox/CABLE-MAP-v1.md*


---

## ESTADO AL 23 JUL 2026

### CABLE 1 — Meta CAPI + Pixel ← IMPLEMENTADO, PENDIENTE TOKEN

| Componente | Estado | Evidencia |
|-----------|--------|-----------|
| Pixel ID | ✅ `4167218546884724` | confirmado por Director |
| Frontend Pixel | ✅ instalado en producción | commit 8be56eb |
| Deduplicación event_id | ✅ sellado en cliente | commit 8be56eb |
| fbclid captura | ✅ cookie + localStorage | commit 8be56eb |
| dataLayer.push generate_lead | ✅ en HotelBookingForm.jsx | commit 8be56eb |
| dataLayer.push purchase | ✅ en CheckoutPage.jsx | commit 8be56eb |
| WF-META-CAPI-v1 | ✅ creado en n8n | ID: oMycQdTpSKsTHBRc |
| Access Token Meta | ⏳ PENDIENTE DIRECTOR | System User en Business Manager |
| Activar WF | ⏳ Después del token | n8n → env → META_CAPI_ACCESS_TOKEN |

### Flujo de datos sellado (Antigravity + ATLAS-TECH)

```
LEAD (cuando el usuario cotiza):
  SPA Web / Chatwoot
    → event_id generado: ALIUN-{lead_id}-{random}
    → Pixel client: fbq('track', 'Lead', data, { eventID })
    → POST /webhook/meta-capi-event { event_name: 'Lead', event_id, fbclid }
    → WF-META-CAPI: hash phone/email → graph.facebook.com
    → Meta deduplica: Pixel + CAPI = 1 evento

PURCHASE (cuando el pago se confirma):
  Commercial Runtime (deposito_recibido stage)
    → mismo event_id del lead original
    → POST /webhook/meta-capi-event { event_name: 'Purchase', event_id, fbclid, precio }
    → WF-META-CAPI: envía Purchase con fbclid para atribución
    → Meta sabe qué anuncio generó esa reserva → ROAS real
```

### Lo único que falta para activar todo

```
Director → Meta Business Manager → System Users
  → Generate Token (ads_management + OFFLINE_CONVERSION)
  → n8n Admin → Variables → META_CAPI_ACCESS_TOKEN = [token]
  → Activar WF oMycQdTpSKsTHBRc
```

### CABLE 3 — GA4 + GTM (Antigravity commit 8be56eb)

```
GA4 Measurement ID: G-VBJQPVHEET ✅ en meta-pixel.js
GTM Container ID: VITE_GTM_CONTAINER_ID → pendiente Director
4 eventos GTM: declarados en dataLayer, pendiente configurar tags en GTM consola
GA4 → Meta Ads: pendiente vincular (5 min en GA4 Admin)
```

*ATLAS-TECH + Antigravity · 23 Jul 2026*
