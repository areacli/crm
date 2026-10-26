# Confirmação curta de uma ação (decisão 0022, fase 2): o botão leva um token assinado com o título, a mensagem e o destino do envio, e o servidor devolve o
# modal pequeno. O navegador não escolhe o destino: o token é verificado e vale por duas horas. A autorização continua na ação de destino.
class Confirmation
  PURPOSE = :confirmacao_do_painel

  # Assinatura com texto seguro para endereço (sem barra nem igual), já que o token vai no caminho da rota.
  def self.verifier = @verifier ||= ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key("confirmacao do painel"), digest: "SHA256", serializer: JSON, url_safe: true)

  def self.sign(payload) = verifier.generate(payload.stringify_keys, expires_in: 2.hours, purpose: PURPOSE)

  # Devolve os dados da confirmação, ou nil se o token for inválido, expirado ou apontar para fora do aplicativo.
  def self.read(token)
    dados = verifier.verified(token, purpose: PURPOSE)
    dados = dados&.to_h&.with_indifferent_access
    dados if dados && dados[:url].to_s.start_with?("/") && !dados[:url].to_s.start_with?("//")
  end
end
