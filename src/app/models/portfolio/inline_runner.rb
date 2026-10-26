module Portfolio
  # Executa as etapas de uma importação sem fila, uma depois da outra, na mesma chamada (demonstração, tarefas de medição e testes de regra).
  # Tem a mesma forma do `step` do `ActiveJob::Continuable`, que é quem as roda em segundo plano, com cursor e retomada (decisão 0021).
  module InlineRunner
    # Cursor da etapa: igual ao do Continuable, sem checkpoint.
    Step = Struct.new(:cursor) do
      def set!(value) = self.cursor = value
      def resumed? = false
      def checkpoint! = nil
    end

    module_function

    def step(_name, start: nil, **) = yield(Step.new(start))
  end
end
