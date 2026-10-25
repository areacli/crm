# Planilha modelo: cabeçalho e uma linha de exemplo, em CSV com ponto e vírgula.
module Imports
  class TemplatesController < ApplicationController
    def show
      authorize Import, :new?
      send_data "﻿#{Portfolio::CsvFile::REQUIRED.join(';')};#{Portfolio::CsvFile::OPTIONAL.join(';')}\r\n" \
                "529.982.247-25;Maria Souza;2026-001;15/11/2026;1.250,00;(11) 99999-0000;maria@exemplo.com.br;C-100;Mensalidade de novembro;\r\n",
                filename: "modelo-carteira.csv", type: "text/csv; charset=utf-8"
    end
  end
end
