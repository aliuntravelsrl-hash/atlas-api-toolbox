# PROTOCOLO DE HANDOFF: BOT IA (HERMES) ↔ ASESOR HUMANO (CHATWOOT)

**Objetivo:** Garantizar una experiencia de cliente fluida y sin fricción cuando una conversación requiera atención personalizada.

---

## 1. 🚨 Criterios de Transferencia (Handoff Triggers)
El agente Hermes transferirá la conversación de inmediato si:
1. **Petición Explícita:** El usuario escribe palabras clave (*"humano"*, *"asesor"*, *"persona"*, *"agente"*, *"hablar con alguien"*).
2. **Disputa o Queja Severa:** Reclamaciones sobre reservas confirmadas, cobros no reconocidos o incidencias en hotel (*Cláusula 7 de aliun-legal-v1*).
3. **Negociación Compleja de Grupos:** Solicitudes de más de 20 personas o eventos corporativos que requieran contrato especial.
4. **Falla de Cobertura:** Tres iteraciones seguidas sin poder resolver la intención del cliente.

---

## 2. 📝 Procedimiento de Handoff en Chatwoot
Cuando se activa el Handoff:
1. **Mensaje de Despedida al Cliente:**
   > *"Te estoy transfiriendo con uno de nuestros asesores de viaje de ALIUN Travel para darte atención personalizada. Un momento por favor."*
2. **Nota Privada Interna (`private: true`):**
   > *"🤖 [HERMES AI HANDOFF]\n• Motivo: Petición de cliente\n• Hotel de interés: Hard Rock Punta Cana\n• Presupuesto: $1,800 USD\n• Resumen: Cliente busca 2 habitaciones para el 15-Nov."*
3. **Etiquetado de Conversación:**
   * Agregar etiqueta: `handoff-humano`, `pendiente-asesor`.
4. **Asignación:** Desasignar el bot para que suene la alerta a los operadores humanos en la bandeja de Chatwoot.
