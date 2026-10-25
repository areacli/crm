require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a permissão vale por credor: a Ana é operadora na Alfa e gestora na Beta" do
    ana = users(:ana)

    assert ana.permitted?("record_contact_attempts", tenants(:alfa))
    assert_not ana.permitted?("manage_users", tenants(:alfa))
    assert ana.permitted?("manage_users", tenants(:beta))
    assert_equal [ tenants(:beta).id ], ana.tenant_ids_with("manage_users")
    assert_equal [ tenants(:alfa).id, tenants(:beta).id ].sort, ana.tenant_ids_with("view_portfolio").sort
  end

  test "vínculo ou credor inativo tira a permissão" do
    memberships(:ana_beta).update!(active: false)
    assert_empty users(:ana).tenant_ids_with("manage_users")

    memberships(:ana_beta).update!(active: true)
    tenants(:beta).update!(active: false)
    assert_empty users(:ana).tenant_ids_with("manage_users")
  end

  test "só entra quem está ativo e tem vínculo ativo com um credor ativo" do
    assert users(:joana).can_sign_in?
    assert_not users(:inativo).can_sign_in?
    assert_not users(:sem_vinculo).can_sign_in?

    memberships(:joana_alfa).update!(active: false)
    assert_not users(:joana).can_sign_in?
  end

  test "o e-mail é normalizado e único" do
    user = User.new(name: "Maria", email_address: "  MARIA@Exemplo.com.br ", password: "uma-senha-longa-1")
    assert_equal "maria@exemplo.com.br", user.email_address

    outro = User.new(name: "Outra", email_address: "joana@exemplo.com.br", password: "uma-senha-longa-1")
    assert_not outro.valid?
  end

  test "a autenticação confere o e-mail e a senha" do
    assert_equal users(:joana), User.authenticate_by(email_address: "JOANA@exemplo.com.br", password: "senha-de-teste-1")
    assert_nil User.authenticate_by(email_address: "joana@exemplo.com.br", password: "errada")
  end

  test "bloqueio" do
    assert_not users(:joana).locked?
    users(:joana).update!(locked_until: 15.minutes.from_now)
    assert users(:joana).locked?
  end
end
