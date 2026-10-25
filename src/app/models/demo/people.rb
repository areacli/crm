module Demo
  # Nomes, produtos e endereços fictícios, escolhidos de forma determinística pelo número do cliente (a mesma carga sai igual todo dia).
  module People
    FIRST = %w[Maria João Ana Pedro Lucas Juliana Carlos Fernanda Rafael Patrícia Bruno Camila Gabriel Larissa Marcos Beatriz Felipe Aline Rodrigo Vanessa
               Thiago Luciana Diego Renata Gustavo Priscila André Mariana Leandro Tatiane Eduardo Carolina Ricardo Daniela Fábio Letícia Sérgio Débora Paulo Clara].freeze
    LAST = %w[Silva Souza Oliveira Santos Pereira Lima Costa Ribeiro Almeida Carvalho Gomes Martins Araújo Barbosa Rocha Dias Nunes Moreira Cardoso Teixeira
              Mendes Freitas Ramos Azevedo Cavalcanti Pinto Machado Monteiro Moraes Correia Campos Batista Vieira Lopes Fernandes Duarte Barros Siqueira
              Borges Nogueira Farias].freeze
    TRADE = %w[Comércio Serviços Transportes Construções Alimentos Tecnologia Consultoria Distribuidora].freeze
    PRODUCTS = [ [ "Mensalidade", 55 ], [ "Matrícula", 10 ], [ "Material didático", 15 ], [ "Cartão de crédito", 12 ], [ "Uniforme", 8 ] ].freeze
    STREETS = [ "Rua das Flores", "Avenida Brasil", "Rua Sete de Setembro", "Rua XV de Novembro", "Avenida Paulista", "Rua da Paz", "Rua Bela Vista", "Avenida Central" ].freeze
    CITIES = [ [ "São Paulo", "SP", "01310100" ], [ "Campinas", "SP", "13010001" ], [ "Rio de Janeiro", "RJ", "20040020" ], [ "Belo Horizonte", "MG", "30130010" ],
               [ "Curitiba", "PR", "80010000" ], [ "Porto Alegre", "RS", "90010000" ], [ "Salvador", "BA", "40020000" ], [ "Goiânia", "GO", "74003010" ] ].freeze

    module_function

    # Número pseudoaleatório estável de (cliente, sal).
    def pick(seed, salt) = Zlib.crc32("#{salt}:#{seed}")

    def person_name(seed) = "#{FIRST[pick(seed, 1) % FIRST.size]} #{LAST[pick(seed, 2) % LAST.size]} #{LAST[pick(seed, 3) % LAST.size]}"
    def company?(seed) = (seed % 20).zero?
    def company_name(seed) = "#{LAST[pick(seed, 2) % LAST.size]} #{TRADE[pick(seed, 4) % TRADE.size]} Ltda"
    def name(seed) = company?(seed) ? company_name(seed) : person_name(seed)
    def document(seed) = company?(seed) ? FakeData.cnpj(seed) : FakeData.cpf(seed)

    def product(seed, salt)
      roll = pick(seed, salt) % 100
      PRODUCTS.each { |name, weight| return name if (roll -= weight) < 0 }
      PRODUCTS.first.first
    end

    def phone(seed, salt = 5) = "(#{[ 11, 19, 21, 31, 41, 51, 71, 62 ][pick(seed, salt) % 8]}) 9#{(pick(seed, salt + 1) % 90_000_000 + 10_000_000)}".sub(/(\d{5})(\d{4})\z/, '\1-\2')
    def email(seed) = "#{I18n.transliterate(person_name(seed).downcase).tr(' ', '.')}#{seed}@exemplo.com.br"
  end
end
