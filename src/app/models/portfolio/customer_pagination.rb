module Portfolio
  # Paginação da lista de clientes: os mesmos números da `Pagination`, com o total e a página pelos caminhos curtos da `CustomerList`.
  class CustomerPagination < Pagination
    def initialize(list, page:, per_page:)
      super(list.relation, page: page, per_page: per_page)
      @list = list
    end

    def total = @total ||= @list.total

    def records = @list.records(limit: per_page, offset: (page - 1) * per_page)
  end
end
