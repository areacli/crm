module Payments
  module Providers
    # O que o fornecedor diz de si: o formulário de cadastro se monta a partir daqui (R259), sem tela por fornecedor.
    #
    # `fields`: campos do cadastro (`Manifest::Field`). `capabilities`: o que o resto do sistema precisa saber (autenticação do webhook,
    # se o PDF vem como arquivo, se o QR Code vem em imagem, domínios do script de cartão para a política de segurança, limite de lote).
    Manifest = Data.define(:provider, :modalities, :fields, :capabilities) do
      def fields_for(modality) = fields.select { |field| field.applies_to?(modality) }

      def field(name) = fields.find { |field| field.name == name.to_s }

      def label = I18n.t("payments.providers.#{provider}.name")

      def supports?(modality) = modalities.include?(modality.to_s)

      # Rótulo e ajuda de um campo, nos arquivos de idioma (textos de tela em pt-BR).
      def label_of(field) = I18n.t("payments.providers.#{provider}.fields.#{field.name}.label", default: I18n.t("payments.fields.#{field.name}.label", default: field.name.humanize))

      def option_label_of(field, option) = I18n.t("payments.providers.#{provider}.fields.#{field.name}.options.#{option}", default: option.to_s.humanize)

      def help_of(field) = I18n.t("payments.providers.#{provider}.fields.#{field.name}.help", default: I18n.t("payments.fields.#{field.name}.help", default: ""))

      # O que o fornecedor pede antes, por meio, mostrado na escolha do fornecedor (16, revisão 1, R373b; 12, revisão 8, R259).
      def about(modality) = I18n.t("payments.providers.#{provider}.about.#{modality}", default: "")
    end

    class Manifest
      TYPES = %w[text secret file select number].freeze
      # Grupos do formulário, nesta ordem (16, R373b): o que liga o CRM à conta no fornecedor e o que vai em cada instrumento.
      GROUPS = %w[access charge].freeze

      # Um campo do cadastro. `type`: text, number, select, secret (cifrado, entra em branco) ou file (arquivo enviado, cifrado).
      # `modalities`: a que modalidades se aplica (nil = todas). `format: "pkcs12"` marca o arquivo como certificado .p12 (validado ao enviar),
      # `password_field` diz qual campo secreto guarda a senha dele. `generated`: o valor é gerado pelo sistema, não digitado. `group`: o grupo do formulário
      # (`access` ou `charge`, 12, revisão 8); sem declaração, segredo e arquivo são de acesso e o resto, da cobrança.
      Field = Data.define(:name, :type, :modalities, :required, :options, :min, :max, :default, :format, :password_field, :generated, :maxlength, :group) do
        def initialize(name:, type:, modalities: nil, required: false, options: nil, min: nil, max: nil, default: nil, format: nil, password_field: nil, generated: false, maxlength: 200, group: nil)
          raise ArgumentError, "tipo de campo desconhecido: #{type}" unless Manifest::TYPES.include?(type.to_s)

          group = (group || (type.to_s.in?(%w[secret file]) ? "access" : "charge")).to_s
          raise ArgumentError, "grupo de campo desconhecido: #{group}" unless Manifest::GROUPS.include?(group)

          super(name: name.to_s, type: type.to_s, modalities: modalities&.map(&:to_s), required: required, options: options&.map(&:to_s), min: min, max: max,
                default: default, format: format&.to_s, password_field: password_field&.to_s, generated: generated, maxlength: maxlength, group: group)
        end

        def applies_to?(modality) = modalities.nil? || modalities.include?(modality.to_s)

        # Campo cifrado em repouso e que nunca volta para a tela.
        def secret? = type.in?(%w[secret file])

        def file? = type == "file"

        def certificate? = file? && format == "pkcs12"

        def numeric? = type == "number"
      end
    end
  end
end
