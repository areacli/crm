module Notices
  # Marcar todos os avisos como lidos.
  class ReadingsController < ApplicationController
    def create
      Current.user.notices.unread.update_all(read_at: Time.current, updated_at: Time.current)
      htmx_fragment? ? render(partial: "notices/bell") : redirect_back_or_to(root_path, status: :see_other)
    end
  end
end
