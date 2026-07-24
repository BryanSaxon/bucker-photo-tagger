class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if an account with that email exists)."
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.update_column(:invited_at, nil) if @user.invited_at? # invite accepted
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: "Your password has been set — please sign in."
    else
      redirect_to edit_password_path(params[:token]),
        alert: @user.errors.full_messages.to_sentence.presence || "Password could not be set."
    end
  end

  private
    # The link may carry a short-lived reset token or a long-lived invitation
    # token; both land on this same set-password screen.
    def set_user_by_token
      @user = User.find_by_token_for(:password_reset, params[:token]) ||
              User.find_by_token_for(:invitation, params[:token])
      return if @user

      redirect_to new_password_path, alert: "That link is invalid or has expired."
    end
end
