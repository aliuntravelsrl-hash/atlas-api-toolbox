# GTI — GUÍA TÉCNICA DE INTEGRACIÓN CHATWOOT API v1

**Versión:** 1.0  
**Referencia Oficial:** [Chatwoot API Docs](https://www.chatwoot.com/developers/api/) & [GitHub Repo](https://github.com/chatwoot/chatwoot)  
**Autenticación:** `api_access_token` vía cabecera HTTP `api_access_token: <USER_OR_BOT_TOKEN>`.

---

## 1. 🔑 Autenticación & Variables de Entorno

```env
CHATWOOT_BASE_URL=https://chat.aliuntravelsrl.com  # o IP de VPS
CHATWOOT_API_TOKEN=tu_api_token_aqui
CHATWOOT_ACCOUNT_ID=1
```

---

## 2. 📩 Endpoints Principales

### A. Enviar Mensaje a una Conversación
* **Método:** `POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/messages`
* **Payload:**
```json
{
  "content": "¡Hola! Tu cotización para Hard Rock Punta Cana está lista por $1,800 USD.",
  "message_type": "outgoing",
  "private": false
}
```
> **Nota Interna / Whisper:** Para dejar una nota técnica que solo vea el equipo humano (sin que el cliente la reciba), envía `"private": true`.

### B. Asignar Etiquetas (Labels) a una Conversación
* **Método:** `POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/labels`
* **Payload:**
```json
{
  "labels": ["cotizado", "hard-rock", "prioridad-alta"]
}
```

### C. Actualizar Atributos Personalizados (Custom Attributes)
Permite adjuntar metadatos de reserva y CRM al contacto o conversación:
* **Método:** `POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/custom_attributes`
* **Payload:**
```json
{
  "custom_attributes": {
    "hotel_interes": "hard-rock-punta-cana",
    "fechas_viaje": "2026-11-01 a 2026-11-05",
    "pax_adultos": 2,
    "lead_id": "a1b2c3d4-...",
    "presupuesto_usd": 1800.00
  }
}
```

### D. Cambiar Estado de la Conversación (Handoff / Cierre)
* **Método:** `POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/toggle_status`
* **Payload:**
```json
{
  "status": "open" // "open", "resolved", "pending", "snoozed"
}
```

---

## 3. ⚡ Webhooks & Eventos de Chatwoot hacia n8n

Chatwoot emite webhooks ante eventos clave:

| Evento | Cuándo se Dispara | Acción en Ecosistema ATLAS |
|---|---|---|
| `message_created` (`incoming`) | El cliente envía un mensaje | Dispara `WF-CHATWOOT-HERMES-v1` para procesar con Hermes AI |
| `conversation_created` | Nuevo chat iniciado | Crea o avanza Lead en `public.crm_leads` y CAPI `Lead` |
| `conversation_status_changed` | Se abre/cierra el chat | Sincroniza estado de atención en CRM |

---

## 4. 🔄 Protocolo de Handoff (Bot IA ↔ Humano)
1. **Atención Automatizada:** Hermes responde consultas, cotizaciones y disponibilidades.
2. **Disparadores de Handoff:**
   - El cliente escribe: *"quiero hablar con una persona"*, *"asesor humano"*, *"queja"*.
   - El agente detecta una disputa legal/pago o excepción operativa.
3. **Acción de Handoff:**
   - Hermes envía nota privada: `"🤖 [Hermes AI] Transfiriendo conversación a agente humano. Razón: Solicitud expresa del cliente."` (`private: true`).
   - Chatwoot cambia la asignación a un agente humano y remueve el lock del bot.
