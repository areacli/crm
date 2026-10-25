module Payments
  module Providers
    class Efi
      # Guarda do token OAuth da Efí, só na memória do processo (nunca no cache compartilhado, que fica no Valkey): o token vale 10 minutos
      # (cobranças) ou 1 hora (Pix) e pedir um por emissão dobraria as chamadas de um lote. A chave é um resumo das credenciais, nunca as credenciais.
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
end
