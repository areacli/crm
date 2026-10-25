// Verificação do WebSocket pelo caminho do usuário (decisão 0020): conecta ao Action Cable, assina o canal público da plataforma
// e espera o sinal que `bin/rails crm:platform_check` faz sair de um job de cada fila do Sidekiq. Imprime SUBSCRIBED quando está
// pronto para o disparo e termina com 0 se chegarem os cinco sinais (imports, exports, messaging, webhooks, default).
//
//   WS_URL=wss://crm.areacli.com/cable WS_ORIGIN=https://crm.areacli.com node ws-check.mjs   (Node 22+: WebSocket é global)
const URL_CABLE = process.env.WS_URL;
if (!URL_CABLE) { console.error('Informe WS_URL (…/cable)'); process.exit(2); }

const esperados = new Set(['imports', 'exports', 'messaging', 'webhooks', 'default']);
// O Action Cable exige o subprotocolo actioncable-v1-json e confere a origem (allowed_request_origins), que o navegador envia e o Node não.
const ws = new WebSocket(URL_CABLE, { protocols: ['actioncable-v1-json'], headers: process.env.WS_ORIGIN ? { Origin: process.env.WS_ORIGIN } : undefined });
const identificador = JSON.stringify({ channel: 'PlatformChannel' });
const limite = setTimeout(() => { console.error(`FALTARAM: ${[...esperados].join(', ')}`); process.exit(1); }, Number(process.env.WS_TIMEOUT ?? 90) * 1000);

ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.type === 'welcome') ws.send(JSON.stringify({ command: 'subscribe', identifier: identificador }));
    else if (msg.type === 'confirm_subscription') console.log('SUBSCRIBED');
    else if (msg.type === 'reject_subscription') { console.error('assinatura recusada'); process.exit(1); }
    else if (msg.message?.event === 'platform-ping') {
        esperados.delete(msg.message.queue);
        console.log(`recebido: ${msg.message.queue}`);
        if (esperados.size === 0) { console.log('OK: os cinco sinais chegaram pelo WebSocket'); clearTimeout(limite); process.exit(0); }
    }
};
ws.onclose = (e) => { console.error(`conexão fechada (${e.code}) ${e.reason ?? ''}`); process.exit(1); };
ws.onerror = (e) => { console.error('erro no WebSocket', e.message ?? ''); process.exit(1); };
