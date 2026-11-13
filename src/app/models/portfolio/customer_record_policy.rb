module Portfolio
  # Cadastro entre sistemas (17, R410 a R413): quando mais de um sistema informa o mesmo cliente, diz se o sistema da carga prevalece no nome e nos
  # dados dele. Vale a política da hora da confirmação, depois da "correção na tela ou carga" (R117). Os sistemas que já informaram o cliente estão em
  # `customers.source_system_ids`, na ordem em que chegaram: o primeiro é o da importação que criou o cliente (R413).
  class CustomerRecordPolicy
    def initialize(setting, system)
      @system_id = system.id
      @policy = setting.customer_record_policy
      @defined_id = setting.customer_record_system_id
    end

    # `customer` ainda sem o sistema desta carga acrescentado à lista dele.
    def prevails?(customer)
      known = customer.source_system_ids
      case @policy
      # R411: enquanto o sistema definido não informou o cliente, os demais podem atualizar.
      when "defined_system" then @system_id == @defined_id || known.exclude?(@defined_id)
      # Cliente criado antes de haver sistemas, ou pela tela: ninguém criou por carga, e a primeira carga vale.
      when "first_creator" then known.empty? || known.first == @system_id
      else true
      end
    end
  end
end
