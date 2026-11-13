module Agreements
  # Dados de referência que vêm com o sistema (11, R249, revisões 9 e 14): a lista de municípios do IBGE e os feriados estaduais e das capitais. Carregados
  # quando o sistema sobe (`crm:reference_data`, no `bin/docker-entrypoint`), pelo seed e pela carga da demonstração, sem comando do administrador. Repetir
  # não duplica: os municípios só entram com a tabela vazia (atualizar a lista é `crm:import_municipalities`), e os feriados são gravados pela chave.
  module ReferenceData
    module_function

    def load
      CalendarImporter.new.municipalities(Municipality::BUNDLED) if Municipality.none?
      LocalHolidays.generate
    end
  end
end
