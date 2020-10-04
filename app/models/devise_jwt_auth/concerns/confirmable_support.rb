# frozen_string_literal: true

module DeviseJwtAuth::Concerns::ConfirmableSupport
  extend ActiveSupport::Concern

  included do
    # Override standard devise `postpone_email_change?` method
    # for not to use `will_save_change_to_email?` & `email_changed?` methods.
    def postpone_email_change?
      postpone = self.class.reconfirmable &&
                 email_value_in_database != email &&
                 !@bypass_confirmation_postpone &&
                 email.present? &&
                 (!@skip_reconfirmation_in_callback || !email_value_in_database.nil?)
      @bypass_confirmation_postpone = false
      postpone
    end
  end

  protected

  def email_value_in_database
    if Devise.rails51? && respond_to?(:email_in_database)
      email_in_database
    else
      email_was
    end
  end
end
