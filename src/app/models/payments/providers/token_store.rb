module Payments
  module Providers
    # Guarda do token OAuth dos adaptadores (era da Efí; desde a revisão 4 da 12 serve também ao Bradesco), só na memória do processo (nunca no cache
    # compartilhado, que fica no Valkey): o token vale de 10 minutos a 1 hora e pedir um por emissão dobraria as chamadas de um lote. A chave é um
    # resumo das credenciais (e do certificado, quando o token é ligado a ele), nunca as credenciais.
    module TokenStore
      MARGIN = 30
      @tokens = {}
      @mutex = Mutex.new

      class << self
        def fetch(key, now: Time.current)
          token = @mutex.synchronize { @tokens[key] }
          return token[:value] if token && token[:expires_at] > now

          value, ttl = yield
          @mutex.synchronize { @tokens[key] = { value: value, expires_at: now + [ ttl.to_i - MARGIN, 1 ].max } }
          value
        end

        def forget(key) = @mutex.synchronize { @tokens.delete(key) }

        def reset! = @mutex.synchronize { @tokens.clear }
      end
    end
  end
end
