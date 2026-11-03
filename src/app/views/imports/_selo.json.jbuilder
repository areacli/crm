# Situação da importação na SPA: o selo com o tom de cada estado e, enquanto trabalha, o percentual.
tom = { "received" => :info, "checking" => :info, "checked" => :warning, "confirming" => :info, "confirmed" => :success,
        "discarded" => :neutral, "rejected" => :danger, "failed" => :danger }.fetch(import.status)
json.situacao selo(t("imports.statuses.#{import.status}"), tom)
json.trabalhando import.working?
json.percentual import.progress_percent
