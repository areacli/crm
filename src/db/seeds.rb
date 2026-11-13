# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Dados de referência que vêm com o sistema (11, R249, revisões 9 e 14): os municípios do IBGE e os feriados estaduais e das capitais. No ambiente de
# teste o banco fica só com as fixtures (cada teste cria os municípios de que precisa); a carga em si é testada em `Agreements::ReferenceData`.
Agreements::ReferenceData.load unless Rails.env.test?
