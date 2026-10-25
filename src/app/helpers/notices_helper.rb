# Sino de avisos no cabeçalho: os não lidos do usuário (os mais novos primeiro) e o texto de cada tipo de aviso.
module NoticesHelper
  UNREAD_LIMIT = 20

  def unread_notices = Current.user.notices.unread.order(id: :desc).limit(UNREAD_LIMIT)

  def unread_notices_count = Current.user.notices.unread.count

  def notice_title(notice) = t("notices.kinds.#{notice.kind}.title", **notice.data.symbolize_keys)

  def notice_body(notice) = t("notices.kinds.#{notice.kind}.body", **notice.data.symbolize_keys)
end
