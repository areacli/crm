module Payments
  # Registro dos fornecedores de instrumentos de pagamento (12, R258, decisão IP-5). Cada fornecedor é um adaptador que declara o seu
  # manifesto (modalidades, campos do cadastro, capacidades) e implementa um ou mais dos contratos `Boleto`, `Pix` e `Card`. O resto do
  # sistema só fala o vocabulário nosso (instrumento, estado, identificador externo); cada adaptador traduz de e para o fornecedor.
  #
  # O registro é refeito a cada carga do código (`config/initializers/payment_providers.rb`), porque as classes são recarregadas no desenvolvimento.
  module Providers
    class UnknownProvider < StandardError; end

    MODALITIES = %w[boleto pix card].freeze

    @registry = {}

    class << self
      def register(name, class_name) = @registry[name.to_s] = class_name

      def reset! = @registry = {}

      def names = @registry.keys

      def known?(name) = @registry.key?(name.to_s)

      # Instância do adaptador (sem estado: tudo o que ele precisa vem da conta).
      def adapter(name) = (@registry[name.to_s] or raise UnknownProvider, "fornecedor desconhecido: #{name}").constantize.new

      def manifest(name) = adapter(name).manifest

      # Fornecedores que implementam a modalidade.
      def for_modality(modality) = names.select { |name| adapter(name).supports?(modality) }
    end
  end
end
