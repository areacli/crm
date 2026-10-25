# Navegador da V5 (verificação pelo caminho do usuário): imagem oficial do Playwright com a versão do pacote igual à da imagem, fixada. Nada é instalado no
# sistema; a imagem é construída uma vez por `v5.sh`.
FROM mcr.microsoft.com/playwright:v1.55.0-noble
WORKDIR /w
RUN npm init -y >/dev/null && npm i playwright@1.55.0 >/dev/null
