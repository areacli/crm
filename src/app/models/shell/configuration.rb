# O que a casca entrega à SPA na abertura (decisão 0025): quem está conectado (ou ninguém), as versões e o que a entrada mostra na
# demonstração. O resto (menu, contadores) vem por JSON depois.
module Shell
  class Configuration
    def initialize(user) = @user = user

    def as_json(*)
      {
        usuario: usuario,
        openui5: Ui5App.openui5,
        aplicacao: "/crm/#{Ui5App.versao}",
        demonstracao: (demonstracao if Demo.enabled?),
        # Na demonstração a senha dos usuários públicos não muda (Demo::Restrictions): o item some do menu do usuário.
        pode_trocar_senha: !Demo.enabled?
      }
    end

    private
      def usuario
        return unless @user

        { id: @user.id, nome: @user.name, email: @user.email_address, iniciais: @user.name.first.upcase,
          senha_temporaria: @user.temporary_password?, operacao: @user.operation&.short_name }
      end

      def demonstracao
        { recriacao: Demo.reset_at, usuarios: Demo::WHO.map { |who| { rotulo: Demo::LABELS.fetch(who), email: Demo.email(who), senha: Demo.password(who) } } }
      end
  end
end
