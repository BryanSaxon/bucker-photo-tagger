require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)     # role: admin
    @employee = users(:two)  # role: employee
  end

  test "employees are denied access to user management" do
    sign_in_as(@employee)
    get users_path
    assert_redirected_to root_path
    follow_redirect!
    assert_select "div", /don.t have access/i
  end

  test "admins can list users" do
    sign_in_as(@admin)
    get users_path
    assert_response :success
    assert_match @employee.email_address, @response.body
  end

  test "inviting a user creates them pending and emails an invitation" do
    sign_in_as(@admin)

    assert_difference -> { User.count }, 1 do
      assert_enqueued_email_with PasswordsMailer, :invite, args: ->(args) { args.first.email_address == "invitee@example.com" } do
        post users_path, params: { user: { email_address: "invitee@example.com", role: "admin" } }
      end
    end
    assert_redirected_to users_path

    invited = User.find_by(email_address: "invitee@example.com")
    assert invited.admin?
    assert invited.pending_invite?
  end

  test "inviting with a bad email re-renders without creating a user" do
    sign_in_as(@admin)
    assert_no_difference -> { User.count } do
      post users_path, params: { user: { email_address: "nope", role: "employee" } }
    end
    assert_response :unprocessable_entity
  end

  test "admin can change a user's role" do
    sign_in_as(@admin)
    patch user_path(@employee), params: { user: { role: "admin" } }
    assert_redirected_to users_path
    assert @employee.reload.admin?
  end

  test "admin can remove another user but not themselves" do
    sign_in_as(@admin)

    assert_difference -> { User.count }, -1 do
      delete user_path(@employee)
    end
    assert_redirected_to users_path

    assert_no_difference -> { User.count } do
      delete user_path(@admin)
    end
    follow_redirect!
    assert_select "div", /can.t remove your own account/i
  end

  test "admin can deactivate and reactivate another user" do
    sign_in_as(@admin)

    post deactivate_user_path(@employee)
    assert_redirected_to users_path
    assert @employee.reload.deactivated?

    post reactivate_user_path(@employee)
    assert @employee.reload.active?
  end

  test "admin cannot deactivate themselves" do
    sign_in_as(@admin)
    post deactivate_user_path(@admin)
    assert @admin.reload.active?
    follow_redirect!
    assert_select "div", /can.t deactivate your own account/i
  end

  test "a deactivated user cannot sign in" do
    @employee.deactivate!
    post session_path, params: { email_address: @employee.email_address, password: "password" }
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "div", /deactivated/i
  end

  test "admin sees a copyable invite link for pending users only" do
    sign_in_as(@admin)
    User.invite!(email_address: "pending@example.com")

    get users_path
    assert_response :success

    # Exactly one pending user (the fixtures are both already activated), so
    # exactly one clipboard control, pointing at the set-password page.
    assert_select "[data-controller='clipboard']", 1
    assert_select "[data-controller='clipboard'][data-clipboard-text-value*='/passwords/']"
  end

  test "the copyable invite link uses a working invitation token" do
    sign_in_as(@admin)
    pending = User.invite!(email_address: "pending@example.com")

    get users_path
    link = css_select("[data-controller='clipboard']").first["data-clipboard-text-value"]
    token = link[%r{/passwords/([^/]+)/edit}, 1]

    # A fresh, unauthenticated visitor follows the link and sets a password.
    reset!
    put password_path(token), params: { password: "newpassword", password_confirmation: "newpassword" }
    assert_redirected_to new_session_path

    pending.reload
    assert_not pending.pending_invite?, "setting a password should clear the pending invite"
    assert pending.authenticate("newpassword"), "the recipient's chosen password should now work"
  end

  test "resending an invite only works for pending users" do
    sign_in_as(@admin)
    pending = User.invite!(email_address: "pending@example.com")

    assert_enqueued_email_with PasswordsMailer, :invite, args: ->(args) { args.first == pending } do
      post resend_invite_user_path(pending)
    end
    assert_redirected_to users_path

    # @employee has already activated (no invited_at) -> no email
    assert_no_enqueued_emails do
      post resend_invite_user_path(@employee)
    end
  end
end
