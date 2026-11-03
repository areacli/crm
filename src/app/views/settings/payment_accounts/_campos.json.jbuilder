# Campos do manifesto do fornecedor para o formulário da integração (12, R261): segredo e arquivo vão em branco e nunca voltam; do arquivo, só os dados
# do certificado guardado.
manifest = account.manifest
json.campos(account.fields.reject(&:generated).map do |field|
  grupo = { "secret" => "secrets", "file" => "files" }.fetch(field.type, "config")
  campo = { nome: field.name, grupo: grupo, tipo: field.type, rotulo: manifest.label_of(field), ajuda: manifest.help_of(field).to_s, obrigatorio: field.required, max: field.maxlength,
            minimo: field.min, maximo: field.max }
  case field.type
  when "text", "number" then campo[:valor] = account.config.fetch(field.name) { field.default if account.new_record? }.to_s
  when "select"
    campo[:valor] = (account.config[field.name] || field.default).to_s
    campo[:opcoes] = field.options.map { |option| { id: option.to_s, nome: manifest.option_label_of(field, option) } }
  when "secret"
    campo[:obrigatorio] = field.required && !account.secret_set?(field.name)
    campo[:ajuda] = "#{account.secret_set?(field.name) ? "Definido (não é mostrado). Deixe em branco para manter; preencha para trocar." : "Será cifrado e não voltará para a tela."} #{campo[:ajuda]}".strip
  when "file"
    info = account.file_info(field.name)
    campo[:obrigatorio] = field.required && !info
    campo[:ajuda] = "#{campo[:ajuda]} Aceita só o arquivo com a chave privada e dentro da validade.".strip
    campo[:certificado] = info && [ { rotulo: "Titular", valor: info["subject"] }, { rotulo: "Vence em", valor: date_br(Date.iso8601(info["not_after"])) },
                                    { rotulo: "Impressão digital (SHA-256)", valor: info["sha256"] } ]
  end
  campo
end)
