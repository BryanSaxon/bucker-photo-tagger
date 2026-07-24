# Preview all emails at http://localhost:3000/rails/mailers/passwords_mailer
class PasswordsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/passwords_mailer/reset
  def reset
    PasswordsMailer.reset(User.take)
  end

  # Preview this email at http://localhost:3000/rails/mailers/passwords_mailer/invite
  def invite
    PasswordsMailer.invite(User.take, invited_by: "admin@example.com")
  end
end
