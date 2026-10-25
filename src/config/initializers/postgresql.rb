# Instantes em timestamptz (o "hoje" do sistema é o de Brasília; o banco guarda o instante). Vale para as migrações e para o esquema.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end
