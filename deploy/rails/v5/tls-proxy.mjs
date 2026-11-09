// Terminador TLS mínimo para verificar uma instalação em http://127.0.0.1:<porta> com navegador: o Rails da demonstração assume TLS (`assume_ssl`, cookies
// seguros, redirecionamentos para https) porque o nginx do servidor fica na frente. Este proxy faz o papel do nginx só nesta verificação: certificado
// autoassinado e o cabeçalho `X-Forwarded-Proto: https` em cada pedido, como o nginx manda; sem ele, o Rails de desenvolvimento (que não assume TLS) recusa
// as gravações pela proteção de origem. O WebSocket passa com o mesmo cabeçalho e, depois do aperto de mão, byte a byte.
// Uso: TARGET_PORT=3220 LISTEN_PORT=3443 node tls-proxy.mjs
import { createServer } from 'node:https';
import { request } from 'node:http';
import { connect } from 'node:net';
import { readFileSync } from 'node:fs';

const alvo = Number(process.env.TARGET_PORT ?? 3220);
const cabecalhos = (req) => ({ ...req.headers, 'x-forwarded-proto': 'https', 'x-forwarded-for': req.socket.remoteAddress });

const servidor = createServer({ key: readFileSync('/tmp/proxy-key.pem'), cert: readFileSync('/tmp/proxy-cert.pem') }, (req, res) => {
    const repasse = request({ host: '127.0.0.1', port: alvo, method: req.method, path: req.url, headers: cabecalhos(req) }, (resposta) => {
        res.writeHead(resposta.statusCode, resposta.headers);
        resposta.pipe(res);
    });
    repasse.on('error', () => res.destroy());
    req.pipe(repasse);
});

servidor.on('upgrade', (req, socket, inicio) => {
    const origem = connect(alvo, '127.0.0.1', () => {
        const linhas = Object.entries(cabecalhos(req)).map(([nome, valor]) => `${nome}: ${valor}`);
        origem.write(`${req.method} ${req.url} HTTP/1.1\r\n${linhas.join('\r\n')}\r\n\r\n`);
        if (inicio.length) origem.write(inicio);
        socket.pipe(origem);
        origem.pipe(socket);
    });
    const encerrar = () => { socket.destroy(); origem.destroy(); };
    socket.on('error', encerrar);
    origem.on('error', encerrar);
});

servidor.listen(Number(process.env.LISTEN_PORT ?? 3443), '127.0.0.1', () => console.log('proxy TLS pronto'));
