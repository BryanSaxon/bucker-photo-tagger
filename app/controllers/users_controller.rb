class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: %i[update destroy resend_invite deactivate reactivate]

  def index
    @users = User.order(:email_address)
    @user = User.new
    # Fallback for when the invite email is blocked or lands in spam: a copyable
    # link (same set-password page the email opens) the admin can send manually.
    @invite_links = @users.each_with_object({}) do |user, links|
      links[user.id] = invite_link_for(user) if user.pending_invite? && user.active?
    end
  end

  # Invite a new user: create them and email a set-password link.
  def create
    @user = User.invite!(email_address: user_params[:email_address], role: role_param)
    PasswordsMailer.invite(@user, invited_by: Current.user.email_address).deliver_later
    redirect_to users_path, notice: "Invitation sent to #{@user.email_address}."
  rescue ActiveRecord::RecordInvalid => e
    @users = User.order(:email_address)
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :index, status: :unprocessable_entity
  end

  # Change a user's role.
  def update
    if @user.update(role: role_param)
      redirect_to users_path, notice: "#{@user.email_address} is now #{@user.role}."
    else
      redirect_to users_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  def destroy
    if @user == Current.user
      redirect_to users_path, alert: "You can’t remove your own account."
    else
      @user.destroy
      redirect_to users_path, notice: "Removed #{@user.email_address}.", status: :see_other
    end
  end

  def resend_invite
    if @user.pending_invite?
      PasswordsMailer.invite(@user, invited_by: Current.user.email_address).deliver_later
      redirect_to users_path, notice: "Invitation resent to #{@user.email_address}."
    else
      redirect_to users_path, alert: "#{@user.email_address} has already activated their account."
    end
  end

  # Soft-disable: blocks sign-in and ends live sessions, but keeps the record.
  def deactivate
    if @user == Current.user
      redirect_to users_path, alert: "You can’t deactivate your own account."
    else
      @user.deactivate!
      redirect_to users_path, notice: "Deactivated #{@user.email_address}."
    end
  end

  def reactivate
    @user.reactivate!
    redirect_to users_path, notice: "Reactivated #{@user.email_address}."
  end

  private
    def set_user
      @user = User.find(params[:id])
    end

    # Absolute set-password URL for a pending invite — identical to the link the
    # invite email carries. Uses the same signed, self-expiring :invitation token,
    # so it auto-invalidates once the user sets a password.
    def invite_link_for(user)
      edit_password_url(user.generate_token_for(:invitation))
    end

    def user_params
      params.require(:user).permit(:email_address, :role)
    end

    def role_param
      params.dig(:user, :role).presence_in(User.roles.keys) || "employee"
    end
end
