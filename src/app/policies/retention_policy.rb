# Guarda de dados (07, R138, R140a): a página e o canal em tempo real valem para quem tem a permissão 13 em algum credor, e mostram só esses credores.
class RetentionPolicy < ApplicationPolicy
  def show? = user.permitted_anywhere?("handle_data_subject_rights")
end
