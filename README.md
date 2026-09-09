# Atlas API Toolbox
> Tipo: **Infraestructura · SQL Tools · RPCs · SDKs & API Adapters**

## Propósito
Caja de herramientas transversal de infraestructura, adaptadores de APIs de terceros, especificaciones de integración y DDLs de base de datos compartidas por el War Room (ATLAS-TECH) y los agentes de los 5 dominios del COS.

## Fuente Canónica
Este repositorio es **infraestructura/código** — implementa los adaptadores técnicos requeridos por la doctrina canónica del COS.

## Consumidores
Hermes Commercial · Hermes Marketing · Ariadne Data · Hermes QA · Atlas Intel · Sentinel · War Room Dispatcher

## Módulos de Infraestructura
- `01-meta/` — WhatsApp Business, Marketing API & CAPI
- `02-google/` — Google Ads API & Google Ads MCP
- `03-tiktok/` — TikTok Marketing API
- `04-ai-gateway/`:
  - `omniroute/` — OmniRoute AI Gateway, Combos & Resiliencia para el Swarm
  - `hermes-agent-docs/` — Guía oficial de desarrollo de Nous Research Hermes Agent (CLI, API, Toolsets, Memory, Skills)
- `05-chatwoot/` — Chatwoot API v1, Webhooks, Cliente JS & Protocolo de Handoff Bot/Humano
- `sql/` — DDLs canónicos y RPCs de analítica:
  - `sql/srm-v1.0-kraljic-legal-migration.sql` — DDL de Gobernanza SRM (Kraljic, Invoices, SPI, Evidence)
- `n8n/` — Workflows de integración y cableados operativos

## Repos Relacionados
- `atlas-war-room` — Despacho del Dispatcher / ATLAS-TECH
- `-atlas-cos-financial-domain` — Dominio Financiero (CFI / SRM / Tesorería)
- `atlas-cos-conversion-domain` — Dominio de Conversión y Ventas
- `-atlas-admin-v2` — Panel Administrativo y UI de Gobernanza SRM

## Estado
`CONVERGENCIA RATIFICADA` — REPO-MOD-001 Fase 2 (Grupo C)

---
*Aliun Travel SRL · Director General Aldo Hilario · ATLAS-TECH*
