# 💬 Módulo 05 — Chatwoot Omnichannel Integration
**Plataforma:** Chatwoot (Customer Engagement Suite & WhatsApp Gateway)  
**Dominio:** Conversión & Soporte Omnicanal  
**Owner:** ATLAS-TECH & Hermes Commercial  
**Guía Oficial de Referencia:** [https://github.com/chatwoot/chatwoot](https://github.com/chatwoot/chatwoot)

---

## 🎯 Propósito en el Ecosistema ATLAS
Chatwoot es la **puerta de entrada omnicanal** del cliente hacia el ecosistema COS (WhatsApp, Web Chat, Facebook Messenger, Instagram DM).

Conecta de forma bidireccional:
$$\text{Cliente (WhatsApp)} \leftrightarrow \text{Chatwoot Inbound} \leftrightarrow \text{n8n WF-CHATWOOT-HERMES} \leftrightarrow \text{Hermes Commercial Gateway (:8645)} \leftrightarrow \text{Supabase SSOT}$$

---

## 📂 Contenido del Módulo
1. `GTI-CHATWOOT-API-GUIDE.md`: Guía técnica exhaustiva de la API v1 de Chatwoot (Endpoints, Autenticación, Headers, Payloads).
2. `chatwoot-client.js`: Cliente JavaScript ligero para n8n y scripts de backend.
3. `webhooks-schema.json`: Esquemas JSON de eventos de webhook (`message_created`, `conversation_status_changed`).
4. `handoff-protocol.md`: Protocolo de transferencia inteligente entre el bot IA (Hermes) y el asesor humano.
