require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a valid, unique email address" do
    assert_not User.new(email_address: "", password: "password").valid?
    assert_not User.new(email_address: "not-an-email", password: "password").valid?
    dup = User.new(email_address: users(:one).email_address.upcase, password: "password")
    assert_not dup.valid?
    assert_includes dup.errors[:email_address], "has already been taken"
  end

  test "requires a password of at least 8 characters" do
    assert_not User.new(email_address: "x@y.com", password: "short").valid?
    assert User.new(email_address: "x@y.com", password: "longenough").valid?
  end

  test "role defaults to employee" do
    assert User.new.employee?
    assert_not User.new.admin?
  end

  test "invite! creates a pending admin with a password digest" do
    user = User.invite!(email_address: "New@Example.com", role: :admin)

    assert user.persisted?
    assert_equal "new@example.com", user.email_address
    assert user.admin?
    assert user.pending_invite?
    assert user.password_digest.present?
  end

  test "pending_invite? is false once invited_at is cleared" do
    user = User.invite!(email_address: "p@example.com")
    assert user.pending_invite?
    user.update_column(:invited_at, nil)
    assert_not user.reload.pending_invite?
  end

  test "password_reset and invitation tokens resolve back to the user" do
    user = users(:one)
    assert_equal user, User.find_by_token_for(:password_reset, user.generate_token_for(:password_reset))
    assert_equal user, User.find_by_token_for(:invitation, user.generate_token_for(:invitation))
    assert_nil User.find_by_token_for(:password_reset, "nonsense")
  end

  test "new users are active" do
    assert users(:two).active?
    assert_not users(:two).deactivated?
  end

  test "deactivate! blocks the user and ends live sessions; reactivate! restores" do
    user = users(:two)
    user.sessions.create!
    assert_difference -> { user.sessions.count }, -1 do
      user.deactivate!
    end
    assert user.deactivated?
    assert_includes User.deactivated, user
    assert_not_includes User.active, user

    user.reactivate!
    assert user.active?
    assert_includes User.active, user
  end
end
