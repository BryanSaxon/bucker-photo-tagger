class PasswordsMailer < ApplicationMailer
  # Forgot-password email (short-lived token).
  def reset(user)
    @user = user
    @token = user.generate_token_for(:password_reset)
    mail subject: "Reset your Photo Tagger password", to: user.email_address
  end

  # Admin invitation email (long-lived token) — routes the new user through the
  # same set-password screen.
  def invite(user, invited_by: nil)
    @user = user
    @invited_by = invited_by
    @token = user.generate_token_for(:invitation)
    mail subject: "You've been invited to Photo Tagger", to: user.email_address
  end
end
