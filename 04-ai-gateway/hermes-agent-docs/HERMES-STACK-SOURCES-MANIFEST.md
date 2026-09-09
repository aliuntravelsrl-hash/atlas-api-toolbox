# HERMES STACK — MANIFIESTO DE FUENTES ORIGINALES

**Fecha de Registro:** 09 de Septiembre de 2026  
**Custodio:** ATLAS-TECH · Data & Analytics  

---

## 🌐 Fuentes y Repositorios Oficiales del Stack

| Componente | Rol en el Stack | Fuente / Documentación Oficial |
|---|---|---|
| **Hermes Agent** | Motor de Inferencia & Agentes | [https://hermes-agent.nousresearch.com/docs/developer-guide/](https://hermes-agent.nousresearch.com/docs/developer-guide/) |
| **Nous Research** | Laboratorio IA / Modelos Hermes | [https://github.com/NousResearch](https://github.com/NousResearch) |
| **Chatwoot** | Gateway Omnicanal (WhatsApp/Web) | [https://github.com/chatwoot/chatwoot](https://github.com/chatwoot/chatwoot) |
| **OpenRouter** | Orquestación de Modelos & Fallbacks | [https://openrouter.ai/docs](https://openrouter.ai/docs) |
| **FastAPI** | Framework del Gateway HTTP (:8645) | [https://fastapi.tiangolo.com/](https://fastapi.tiangolo.com/) |
| **Supabase** | Persistencia Relacional & PostgREST | [https://supabase.com/docs](https://supabase.com/docs) |
| **n8n** | Orquestador de Flujos & Webhooks | [https://docs.n8n.io/](https://docs.n8n.io/) |

---

## 📦 Adaptaciones Específicas de ALIUN Travel:
1. **Gateway Dual (:8645 y :4860):** Puerto 8645 exclusivo para la API REST de chat con Tool Calling; puerto 4860 para el dashboard de control.
2. **Persistencia Híbrida:** Memoria de corto plazo en VPS2 (`state.db`); memoria de largo plazo en Supabase Cloud (`conversation_sessions`, `crm_leads`).
