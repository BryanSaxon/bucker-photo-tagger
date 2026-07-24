class ApplicationMailer < ActionMailer::Base
  # The from-address must be a SendGrid-verified sender. Set credentials.mailer.from.
  default from: Rails.application.credentials.dig(:mailer, :from) || "no-reply@example.com"
  layout "mailer"
end
