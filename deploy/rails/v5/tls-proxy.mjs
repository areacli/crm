// Terminador TLS mínimo para verificar uma instalação em http://127.0.0.1:<porta> com navegador: o Rails da demonstração assume TLS (`assume_ssl`, cookies
// seguros, redirecionamentos para https) porque o nginx do servidor fica na frente. Este proxy faz o papel do nginx só nesta verificação: certificado
// autoassinado, repasse dos bytes (o WebSocket passa sem mudança). Uso: TARGET_PORT=3220 LISTEN_PORT=3443 node tls-proxy.mjs
import { createServer } from 'node:tls';
import { connect } from 'node:net';
import { readFileSync } from 'node:fs';

const alvo = Number(process.env.TARGET_PORT ?? 3220);
createServer({ key: readFileSync('/tmp/proxy-key.pem'), cert: readFileSync('/tmp/proxy-cert.pem') }, (socket) => {
    const origem = connect(alvo, '127.0.0.1');
    socket.pipe(origem);
    origem.pipe(socket);
    const encerrar = () => { socket.destroy(); origem.destroy(); };
    socket.on('error', encerrar);
    origem.on('error', encerrar);
}).listen(Number(process.env.LISTEN_PORT ?? 3443), '127.0.0.1', () => console.log('proxy TLS pronto'));
