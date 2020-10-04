# frozen_string_literal: true

module DeviseJwtAuth
  class RegistrationsController < DeviseJwtAuth::ApplicationController
    before_action :set_user_by_token, only: [:destroy, :update]
    before_action :validate_sign_up_params, only: :create
    before_action :validate_account_update_params, only: :update
    # skip_after_action :update_auth_header, only: [:create, :destroy]

    def create
      build_resource

      unless @resource.present?
        raise DeviseJwtAuth::Errors::NoResourceDefinedError,
              "#{self.class.name} #build_resource does not define @resource,"\
              ' execution stopped.'
      end

      # give redirect value from params priority
      @redirect_url = params.fetch(
        :confirm_success_url,
        DeviseJwtAuth.default_confirm_success_url
      )

      # success redirect url is required
      if confirmable_enabled? && !@redirect_url
        return render_create_error_missing_confirm_success_url
      end

      # if whitelist is set, validate redirect_url against whitelist
      if blacklisted_redirect_url?(@redirect_url)
        return render_create_error_redirect_url_not_allowed
      end

      # override email confirmation, must be sent manually from ctrl
      callback_name = defined?(ActiveRecord) && resource_class < ActiveRecord::Base ? :commit : :create
      resource_class.set_callback(callback_name, :after, :send_on_create_confirmation_instructions)
      resource_class.skip_callback(callback_name, :after, :send_on_create_confirmation_instructions)

      if @resource.respond_to? :skip_confirmation_notification!
        # Fix duplicate e-mails by disabling Devise confirmation e-mail
        @resource.skip_confirmation_notification!
      end

      if @resource.save
        yield @resource if block_given?

        unless @resource.confirmed?
          # user will require email authentication
          @resource.send_confirmation_instructions({
                                                     client_config: params[:config_name],
                                                     redirect_url: @redirect_url
                                                   })
        end

        update_refresh_token_cookie if active_for_authentication?

        render_create_success
      else
        clean_up_passwords @resource
        render_create_error
      end
    end

    def update
      if @resource
        if @resource.send(resource_update_method, account_update_params)
          yield @resource if block_given?
          render_update_success
        else
          render_update_error
        end
      else
        render_update_error_user_not_found
      end
    end

    def destroy
      if @resource
        @resource.destroy
        yield @resource if block_given?
        render_destroy_success
      else
        render_destroy_error
      end
    end

    def sign_up_params
      params.permit(*params_for_resource(:sign_up))
    end

    def account_update_params
      params.permit(*params_for_resource(:account_update))
    end

    protected

    def build_resource
      @resource            = resource_class.new(sign_up_params)
      @resource.provider   = provider

      # honor devise configuration for case_insensitive_keys
      @resource.email = if resource_class.case_insensitive_keys.include?(:email)
                          sign_up_params[:email].try(:downcase)
                        else
                          sign_up_params[:email]
                        end
    end

    def render_create_error_missing_confirm_success_url
      response = {
        status: 'error',
        data: resource_data
      }
      message = I18n.t('devise_jwt_auth.registrations.missing_confirm_success_url')
      render_error(422, message, response)
    end

    def render_create_error_redirect_url_not_allowed
      response = {
        status: 'error',
        data: resource_data
      }
      message = I18n.t('devise_jwt_auth.registrations.redirect_url_not_allowed', redirect_url: @redirect_url)
      render_error(422, message, response)
    end

    def render_create_success
      response_data = {
        status: 'success',
        data: resource_data
      }

      if active_for_authentication?
        response_data.merge!(@resource.create_named_token_pair)
      end
      render json: response_data
    end

    def render_create_error
      render json: {
        status: 'error',
        data: resource_data,
        errors: resource_errors
      }, status: 422
    end

    def render_update_success
      render json: {
        status: 'success',
        data: resource_data
      }
    end

    def render_update_error
      render json: {
        status: 'error',
        errors: resource_errors
      }, status: 422
    end

    def render_update_error_user_not_found
      render_error(404, I18n.t('devise_jwt_auth.registrations.user_not_found'), status: 'error')
    end

    def render_destroy_success
      render json: {
        status: 'success',
        message: I18n.t('devise_jwt_auth.registrations.account_with_uid_destroyed', uid: @resource.uid)
      }
    end

    def render_destroy_error
      render_error(404, I18n.t('devise_jwt_auth.registrations.account_to_destroy_not_found'), status: 'error')
    end

    private

    def resource_update_method
      if DeviseJwtAuth.check_current_password_before_update == :attributes
        'update_with_password'
      elsif DeviseJwtAuth.check_current_password_before_update == :password && account_update_params.key?(:password)
        'update_with_password'
      elsif account_update_params.key?(:current_password)
        'update_with_password'
      else
        'update'
      end
    end

    def validate_sign_up_params
      validate_post_data sign_up_params, I18n.t('errors.messages.validate_sign_up_params')
    end

    def validate_account_update_params
      validate_post_data account_update_params, I18n.t('errors.messages.validate_account_update_params')
    end

    def validate_post_data(which, message)
      if which.empty?
        render_error(:unprocessable_entity, message, status: 'error')
      end
    end

    def active_for_authentication?
      !@resource.respond_to?(:active_for_authentication?) || @resource.active_for_authentication?
    end
  end
end
