# 🧠 Hermes Agent — Developer & Architecture Guide
**Fuente Oficial:** [Nous Research Hermes Agent Docs](https://hermes-agent.nousresearch.com/docs/developer-guide/)  
**Framework:** Nous Research Hermes Agent / OpenClaw  
**Ubicación en Ecosistema:** VPS2 (`hermes-agent-dpkf-hermes-agent-1`, Gateway :8645)  
**Propósito:** Guía de referencia para desarrolladores, colaboradores y autores de PRs en el stack de IA de ALIUN Travel.

---

## 1. 🏛️ Arquitectura del Core de Hermes Agent

Hermes Agent es un framework de agentes autónomos diseñado por **Nous Research** para inferencia con modelos avanzados de razonamiento y function calling estructurado:

```text
                  USUARIO / TRANSPORTE (Chatwoot, WhatsApp, API)
                                        │
                                        ▼
                  HTTP GATEWAY (FastAPI :8645 / Traefik)
                                        │
                    ┌───────────────────┴───────────────────┐
                    ↓                                       ↓
         PROMPT / SOUL CONTEXT                    SESSION & MEMORY
       (SOUL.md · Persona · Reglas)             (state.db SQLite · /sessions/)
                    │                                       │
                    └───────────────────┬───────────────────┘
                                        ▼
                           INFERENCE ENGINE (OpenRouter)
                  (Qwen 2.5 72B · Gemini 2.0 Flash · Nemotron)
                                        │
                             FUNCTION CALLING LOOP
                                        │
                   ┌────────────────────┼────────────────────┐
                   ↓                    ↓                    ↓
             SUPABASE RPCS          SALES MCP          OPERATIONS APIS
           (buscar_hoteles,     (cotizaciones,      (vouchers, logs,
            disponibilidad)       abonos, crm)          seguimiento)
                                        │
                                        ▼
                            RESPUESTA DETERMINISTA
```

---

## 2. ⚙️ Ciclo de Ejecución (Agent Execution Loop)

1. **Ingesta:** El Gateway FastAPI recibe el payload `{ message: string, session_id: string, user_id?: string }` en `POST /chat`.
2. **Rehidratación de Sesión:**
   - Carga el historial desde `/opt/data/sessions/{session_id}.json` o `/opt/data/state.db`.
   - Inyecta el archivo de identidad canónica (`SOUL.md`) y el catálogo de herramientas activas (`tools`).
3. **Inferencia & Tool Calling (Multi-turn):**
   - El modelo evalúa si la intención del usuario requiere invocar herramientas (`tool_calls`).
   - Si invoca herramientas: ejecuta la función contra Supabase/MCP, reinyecta el resultado como mensaje de rol `tool` y solicita al modelo la respuesta final en lenguaje natural.
4. **Persistencia & Retorno:** Guarda el turno en la base de datos de estado y retorna el JSON al transport adapter (n8n / Chatwoot).

---

## 3. 🛠️ Definición de Herramientas (Tool Calling Spec)

Cada herramienta debe cumplir con la especificación estándar JSON Schema de OpenAI / Nous Hermes:

```json
{
  "type": "function",
  "function": {
    "name": "calcular_cotizacion",
    "description": "Calcula el precio final exacto de un paquete turístico con desglose de márgenes.",
    "parameters": {
      "type": "object",
      "properties": {
        "hotel_slug": { "type": "string", "description": "Slug del hotel en hotels_master" },
        "checkin": { "type": "string", "description": "Fecha checkin YYYY-MM-DD" },
        "checkout": { "type": "string", "description": "Fecha checkout YYYY-MM-DD" },
        "adults": { "type": "integer", "description": "Cantidad de adultos" },
        "children": { "type": "integer", "description": "Cantidad de niños" }
      },
      "required": ["hotel_slug", "checkin", "checkout", "adults"]
    }
  }
}
```

---

## 4. 🗄️ Capas de Memoria y Estado (`state.db`)

* **`state.db` (SQLite):** Almacena metadatos de agentes, locks de ejecución, contadores de tokens y claves de sesión.
* **`/opt/data/sessions/`:** Volcados JSON estructurados de cada hilo conversacional para auditoría forense (FRONT G).
* **Supabase Cloud (SSOT):** Almacena el conocimiento inmutable de la empresa (`hotels_master`, `crm_leads`, `atlas_payments`, `supplier_requests`).

---

## 5. 🛡️ Convenciones de Desarrollo y Aportes (PRs)
1. **Inmutabilidad de Schemas:** Ningún PR puede alterar los parámetros de herramientas RPC existentes sin actualizar el archivo de migración SQL correspondiente.
2. **Cero Dependencias Volátiles:** Toda herramienta debe tener fallback elegante en caso de timeout de red (>45s).
3. **Auditoría Forense:** Cada invocación de herramienta debe registrarse en `public.logs_operativos` con su `session_id`.
