require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:two) }

  def reset_token = @user.generate_token_for(:password_reset)

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create enqueues a reset email" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path
    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path
  end

  test "edit with a valid token" do
    get edit_password_path(reset_token)
    assert_response :success
  end

  test "edit with an invalid token redirects" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path
    follow_redirect!
    assert_notice "invalid or has expired"
  end

  test "update sets a new password and clears sessions" do
    @user.sessions.create!
    assert_changes -> { @user.reload.password_digest } do
      put password_path(reset_token), params: { password: "newpassword", password_confirmation: "newpassword" }
      assert_redirected_to new_session_path
    end
    assert_equal 0, @user.sessions.count
    follow_redirect!
    assert_notice "password has been set"
  end

  test "update with non-matching passwords re-renders with an error" do
    token = reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "newpassword", password_confirmation: "different" }
      assert_redirected_to edit_password_path(token)
    end
  end

  test "update rejects a too-short password" do
    token = reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short", password_confirmation: "short" }
      assert_redirected_to edit_password_path(token)
    end
  end

  test "an invitation token also lets the user set their password and clears the invite" do
    @user.update_column(:invited_at, Time.current)
    token = @user.generate_token_for(:invitation)
    put password_path(token), params: { password: "newpassword", password_confirmation: "newpassword" }
    assert_redirected_to new_session_path
    assert_nil @user.reload.invited_at
  end

  private
    def assert_notice(text)
      assert_select "div", /#{text}/i
    end
end
