/**
 * ATLAS API TOOLBOX — Chatwoot Client v1.0
 * Conector ligero para interacción con la API v1 de Chatwoot.
 */

const https = require('https');

class ChatwootClient {
  constructor(baseUrl, apiToken, accountId = 1) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.apiToken = apiToken;
    this.accountId = accountId;
  }

  _request(method, path, body = null) {
    return new Promise((resolve, reject) => {
      const url = new URL(this.baseUrl + path);
      const payload = body ? JSON.stringify(body) : null;

      const options = {
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method: method,
        headers: {
          'api_access_token': this.apiToken,
          'Content-Type': 'application/json',
          ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {})
        }
      };

      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const parsed = data ? JSON.parse(data) : {};
            resolve({ status: res.statusCode, data: parsed });
          } catch(e) {
            resolve({ status: res.statusCode, raw: data });
          }
        });
      });

      req.on('error', reject);
      if (payload) req.write(payload);
      req.end();
    });
  }

  // Enviar mensaje público al cliente
  async sendMessage(conversationId, content) {
    return this._request('POST', `/api/v1/accounts/${this.accountId}/conversations/${conversationId}/messages`, {
      content: content,
      message_type: 'outgoing',
      private: false
    });
  }

  // Enviar nota privada interna (solo visible para asesores de Aliun)
  async sendPrivateNote(conversationId, content) {
    return this._request('POST', `/api/v1/accounts/${this.accountId}/conversations/${conversationId}/messages`, {
      content: content,
      message_type: 'outgoing',
      private: true
    });
  }

  // Asignar etiquetas a la conversación
  async addLabels(conversationId, labelsArray) {
    return this._request('POST', `/api/v1/accounts/${this.accountId}/conversations/${conversationId}/labels`, {
      labels: labelsArray
    });
  }

  // Actualizar atributos personalizados
  async updateCustomAttributes(conversationId, attributesObject) {
    return this._request('POST', `/api/v1/accounts/${this.accountId}/conversations/${conversationId}/custom_attributes`, {
      custom_attributes: attributesObject
    });
  }

  // Cambiar estado (open, resolved, pending, snoozed)
  async toggleStatus(conversationId, status = 'open') {
    return this._request('POST', `/api/v1/accounts/${this.accountId}/conversations/${conversationId}/toggle_status`, {
      status: status
    });
  }
}

module.exports = ChatwootClient;
