# Paginação simples (P22): 20 registros por página por padrão, com 20, 50 ou 100 à escolha. Sem gem: o Active Record já tem limit e offset.
class Pagination
  PER_PAGE_OPTIONS = [ 20, 50, 100 ].freeze

  attr_reader :page, :per_page

  def initialize(relation, page:, per_page:)
    @relation = relation
    @per_page = PER_PAGE_OPTIONS.include?(per_page.to_i) ? per_page.to_i : PER_PAGE_OPTIONS.first
    @page = [ page.to_i, 1 ].max
  end

  def total = @total ||= @relation.except(:select, :order).count

  def pages = [ (total / per_page.to_f).ceil, 1 ].max

  def records = @relation.limit(per_page).offset((page - 1) * per_page)

  def first_item = total.zero? ? 0 : (page - 1) * per_page + 1

  def last_item = [ page * per_page, total ].min

  def previous_page = page > 1 ? page - 1 : nil

  def next_page = page < pages ? page + 1 : nil
end
