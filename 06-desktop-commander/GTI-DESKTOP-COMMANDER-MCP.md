# GTI — GUÍA TÉCNICA DE INTEGRACIÓN DESKTOP COMMANDER MCP

**Versión:** 1.0  
**Repositorio Oficial:** [GitHub: wonderwhy-er/desktopcommandermcp](https://github.com/wonderwhy-er/desktopcommandermcp)  
**Paquete npm:** `@wonderwhy-er/desktop-commander`  
**Protocolo:** Model Context Protocol (MCP) v1.0 (stdio / SSE / Remote WebSocket Bridge)  
**Dominio / Rol en ATLAS:** Infraestructura · Runtime Execution Envelope · Agente-a-SO Bridge · War Room & Swarm Automation  

---

## 1. 🏗️ Arquitectura y Rol en el Ecosistema ATLAS

Desktop Commander MCP es el adaptador estándar de ejecución de sistema operativo y gestión de procesos del Ecosistema ATLAS. Permite a los agentes cognitivos (Antigravity, Nous Hermes Agent, ATLAS Intel, Ariadne Data, Sentinel) interactuar de forma segura y auditada con entornos locales y remotos (Windows `DESKTOP-2HAFT48`, Servidores Linux / VPS).

```
┌────────────────────────────────────────────────────────┐
│                   COS AGENT LAYER                      │
│ (Antigravity / Hermes Agent / ATLAS Intel / War Room)   │
└───────────────────────────┬────────────────────────────┘
                            │ (JSON-RPC 2.0 / MCP Calls)
                            ▼
┌────────────────────────────────────────────────────────┐
│            DESKTOP COMMANDER MCP SERVER                │
│             (@wonderwhy-er/desktop-commander)          │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 1. Local Stdio Mode                              │  │
│  │ 2. Remote Bridge Mode (mcp.desktopcommander.app) │  │
│  └──────────────────────────────────────────────────┘  │
└───────────────────────────┬────────────────────────────┘
                            │ (OS Envelope / Fencing & Auditing)
                            ▼
┌────────────────────────────────────────────────────────┐
│               TARGET OPERATING SYSTEM                  │
│  • File System (Read / Write / Diff / Search)          │
│  • Process Execution (PTY / Background Daemons)        │
│  • Session & Telemetry Registry                        │
└────────────────────────────────────────────────────────┘
```

---

## 2. 🔑 Modos de Operación y Autenticación

### A. Modo Local (Stdio Directo)
Utilizado para orquestadores locales (Antigravity IDE, Claude Desktop) ejecutándose en la misma máquina física.
```json
{
  "mcpServers": {
    "desktop-commander": {
      "command": "npx",
      "args": ["-y", "@wonderwhy-er/desktop-commander"]
    }
  }
}
```

### B. Modo Remoto (Bridge / Remote Device)
Utilizado para enlazar estaciones de trabajo o servidores remotos a través del túnel seguro de Desktop Commander.
* **Comando de inicio:**
  ```bash
  npx @wonderwhy-er/desktop-commander remote
  ```
* **Almacenamiento de sesión y tokens:**
  - Archivo persistente: `~/.desktop-commander-device/device.json`
  - Variables: `deviceId`, `jwt_token`, `channel_id`.
  - El daemon restaura automáticamente el canal de sockets en tiempo real (`user:<id>`).

---

## 3. 🛠️ Catálogo de Herramientas MCP Disponibles

Desktop Commander expone un conjunto de 26 herramientas organizadas en 5 familias operativas:

### 📁 1. Filesystem & Documentos
| Herramienta | Descripción | Parámetros Clave |
|---|---|---|
| `read_file` | Lee el contenido de un archivo local | `filePath`, `startLine`, `lineCount` |
| `read_multiple_files` | Lee múltiples archivos en lote para optimizar contexto | `filePaths` |
| `write_file` | Escribe o sobrescribe archivos | `filePath`, `content` |
| `write_pdf` | Genera documentos PDF a partir de Markdown / HTML | `outputPath`, `markdownContent` |
| `create_directory` | Crea directorios recursivamente | `directoryPath` |
| `list_directory` | Lista archivos y carpetas con metadatos | `directoryPath`, `recursive` |
| `move_file` | Mueve o renombra archivos y directorios | `sourcePath`, `destinationPath` |
| `get_file_info` | Obtiene tamaño, permisos y marcas de tiempo | `filePath` |

### ✏️ 2. Edición Quirúrgica de Código
| Herramienta | Descripción | Parámetros Clave |
|---|---|---|
| `edit_block` | Reemplaza o inserta bloques de texto sin reescribir el archivo completo | `filePath`, `oldText`, `newText` |

### 🔍 3. Búsqueda y Descubrimiento
| Herramienta | Descripción | Parámetros Clave |
|---|---|---|
| `start_search` | Inicia una búsqueda asíncrona por texto o patrón regex | `query`, `directoryPath`, `filePattern` |
| `get_more_search_results` | Pagina resultados de búsquedas en curso | `searchId` |
| `stop_search` | Cancela una búsqueda activa | `searchId` |
| `list_searches` | Lista búsquedas en ejecución | — |

### ⚡ 4. Terminal & Gestión de Procesos
| Herramienta | Descripción | Parámetros Clave |
|---|---|---|
| `start_process` | Lanza un proceso o comando en terminal PTY / Shell | `command`, `workingDirectory`, `isDaemon` |
| `read_process_output` | Lee logs y salida stdout/stderr de un proceso | `processId`, `offset` |
| `interact_with_process` | Envía stdin a procesos interactivos | `processId`, `input` |
| `force_terminate` | Finaliza de forma forzosa un proceso | `processId` |
| `kill_process` | Termina ordenadamente un proceso | `processId` |
| `list_processes` | Lista todos los procesos activos gestionados | — |
| `list_sessions` | Lista las sesiones de terminal activas | — |

### 📊 5. Configuración y Telemetría
| Herramienta | Descripción | Parámetros Clave |
|---|---|---|
| `get_config` | Lee la configuración activa del servidor MCP | — |
| `set_config_value` | Actualiza parámetros de configuración (directorios permitidos, timeouts) | `key`, `value` |
| `get_usage_stats` | Métricas de uso: llamadas totales, tasa de éxito y categorías | — |
| `get_recent_tool_calls` | Historial reciente de invocaciones para auditoría | `limit` |
| `get_prompts` | Plantillas de prompts registradas en el servidor | — |
| `give_feedback_to_desktop_commander`| Envío de feedback de telemetría | `feedback` |

---

## 4. 🛡️ Estándar de Hardening y Fencing (COS Compliance)

Conforme a la doctrina `COS-HARDENING-BIDIMENSIONAL-STANDARD-v1` y `HEH-001 v0.2.5`:

1. **Zero Self-Authorization:** Los agentes no deben ejecutar comandos destructivos (`rm -rf`, `DROP TABLE`, formateo de discos) sin validación previa o gates de aprobación.
2. **Read-Before-Write Invariant:** Antes de aplicar `edit_block` o `write_file`, se debe ejecutar `read_file` para comprobar la existencia y estado exacto del código.
3. **Execution Envelope & Side-Effect Ledger:** Toda ejecución de comandos de largo aliento (`start_process`) debe ser registrada con su respectivo `processId` y monitoreada mediante lectura de logs.
4. **Directorios de Trabajo Seguros:** Limitar las operaciones a las rutas del workspace del proyecto (`c:/Users/Admin/Downloads/...`).

---

## 5. 🚀 Verificación de Estado Operativo

Para comprobar el estado del servidor desde un agente o script:
```javascript
// Invocación vía MCP Client
const stats = await mcpClient.callTool("desktop-commander", "get_usage_stats", {});
console.log(stats);
// Salida esperada: Success rate > 95%, Device: Online
```
