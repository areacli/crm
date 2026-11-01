module Segments
  # "Conferir" no editor (13, R288): quantos clientes ou contratos o segmento pega hoje, o saldo deles e quantos pegaria cada condição sozinha;
  # nada é gravado. Responde em até 10 s (SG-14); passando disso, a consulta é cancelada e a tela diz que o segmento é pesado demais.
  class Probe
    TIMEOUT = "10s"

    def initialize(tenant, expression)
      @tenant = tenant
      @expression = expression
    end

    # { total:, balance_cents:, conditions: { "0" => n, "4.1" => n } } ou { timeout: true }.
    def call
      compiler = Compiler.new(@tenant)
      row = Compiler.select(compiler.probe(@expression), timeout: TIMEOUT).first
      { total: row["total"].to_i, balance_cents: row["balance"].to_i,
        conditions: compiler.probe_addresses.each_with_index.to_h { |address, index| [ address, row["c#{index}"].to_i ] } }
    rescue ActiveRecord::QueryCanceled
      { timeout: true }
    end
  end
end
