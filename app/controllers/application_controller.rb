class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :admin?

  private
    def admin?
      Current.user&.admin?
    end

    def require_admin
      return if admin?

      redirect_to root_path, alert: "You don’t have access to that area."
    end
end
