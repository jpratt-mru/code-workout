
class LtiController < ApplicationController
  require 'date'

  # load_and_authorize_resource
  after_action :allow_iframe, only: :launch

  def launch
    # must include the oauth proxy object
    require 'oauth/request_proxy/rack_request'

    if request.post?
      render :error and return unless lti_authorize!

<<<<<<< e8d50a5860cd52b92e7e8427cc76f5a6664bb257
      @lms_instance = LmsInstance.find_by(consumer_key: params[:oauth_consumer_key])

      # Retrieve user information and sign in the user.

      # First check if we can find a user using the LtiIdentity
      lti_user_id = params[:user_id]
      @lti_identity = LtiIdentity.find_by(lms_instance: @lms_instance, lti_user_id: lti_user_id)
      if @lti_identity
        @user = @lti_identity.user
      else
        # If not, check both email parameters
        @user = User.find_by(email: params[:lis_person_contact_email_primary])
        if @user.blank? && params[:custom_canvas_user_login_id]
          @user = User.find_by(email: params[:custom_canvas_user_login_id])
        end
      end

=======
      # Retrieve user information and sign in the user
      email = params[:lis_person_contact_email_primary]
      first_name = params[:lis_person_name_given]
      last_name = params[:lis_person_name_family]
      @user = User.where(email: email).first
>>>>>>> Enrolled students and instructors get directed to the appropriate
      if @user.blank?
        if params[:custom_canvas_user_login_id]
          email = params[:custom_canvas_user_login_id]
        else
          email = params[:lis_person_contact_email_primary]
        end

        @user = User.new(
          email: email,
          first_name: params[:lis_person_name_given],
          last_name: params[:lis_person_name_family]
        )
        @user.skip_password_validation = true
        @user.save!
        @lti_identity = LtiIdentity.new(user: @user, lms_instance: @lms_instance, lti_user_id: lti_user_id)
        @lti_identity.save!
      else
        # We've found a user, so we'll check for incomplete fields and give them values
        # before proceeding
        if @user.first_name.blank?
          @user.first_name = params[:lis_person_name_given]
        end

        if @user.last_name.blank?
          @user.last_name = params[:lis_person_name_family]
        end

        if !@user.lti_identities.where(lms_instance: @lms_instance).andand.first
          @lti_identity = LtiIdentity.new(user: @user, lms_instance: @lms_instance, lti_user_id: lti_user_id)
          @lti_identity.save!
        end

        @user.save!
      end

      # We have a user, sign them in
      sign_in @user

      @lms_instance = LmsInstance.find_by consumer_key: params[:oauth_consumer_key]

      @organization = @lms_instance.organization
      course_number = params[:custom_course_number] || params[:context_label].gsub(/[^a-zA-Z0-9 ]/, '')
      term_slug = params[:custom_term]
      course_name = params[:context_title]
      course_slug = course_number.gsub(/[^a-zA-Z0-9]/, '').downcase

      # Finding appropriate course offerings and workout offerings from the workout
      resource_link_title = params[:resource_link_title]
      if (/\A[0-9][0-9].[0-9][0-9].[0-9][0-9] -/ =~ resource_link_title).nil?
        workout_name = resource_link_title
      else
        workout_name = resource_link_title[11..resource_link_title.length]
      end

      if @organization.blank?
        @message = 'Organization not found'
        render 'lti/error' and return
      end

      @course = Course.find_by(slug: course_slug, organization: @organization)
      if @course.blank?
        if @tp.context_instructor?
          @course = Course.new(
            name: course_name,
            number: course_number,
            creator_id: @user.id,
            organization_id: @organization.id,
            slug: course_slug
          )
          @organization.courses << @course
          @course.save
        else
          @message = 'Course not found.'
          render 'lti/error' and return
        end
      end

      @term = Term.find_by(slug: term_slug) || Term.current_term
      if @term.blank?
        @message = 'Term not found.'
        render 'lti/error' and return
      end

      redirect_to organization_find_workout_offering_path(
        organization_id: @organization.slug,
        term_id: @term.slug,
        workout_name: workout_name,
        user_id: @user.id,
        course_id: @course.slug,
        lis_outcome_service_url: params[:lis_outcome_service_url],
        lis_result_sourcedid: params[:lis_result_sourcedid]
      )
    end
  end

  def assessment
    request_params = JSON.parse(request.body.read.to_s)
    launch_params = request_params['launch_params']
    if launch_params
      key = launch_params['oauth_consumer_key']
    else
      @message = "The tool never launched"
      render(:error)
    end

    @tp = IMS::LTI::ToolProvider.new(key, $oauth_creds[key], launch_params)

    if !@tp.outcome_service?
      @message = "This tool wasn't launched as an outcome service"
      render(:error)
    end

    # post the given score to the TC
    score = (request_params['score'] != '' ? request_params['score'] : nil)
    res = @tp.post_replace_result!(score)

    if res.success?
      # @score = request_params['score']
      # @tp.lti_msg = "Message shown when arriving back at Tool Consumer."
      render :json => { :message => 'success' }.to_json
      # erb :assessment_finished
    else
      render :json => { :message => 'failure' }.to_json
      # @tp.lti_errormsg = "The Tool Consumer failed to add the score."
      # show_error "Your score was not recorded: #{res.description}"
      # return erb :error
    end
  end

  private
    def lti_authorize!
      if key = params['oauth_consumer_key']
        if secret = LmsInstance.find_by(consumer_key: key).andand.consumer_secret
          @tp = IMS::LTI::ToolProvider.new(key, secret, params)
        else
          @tp = IMS::LTI::ToolProvider.new(nil, nil, params)
          @tp.lti_msg = "Your consumer didn't use a recognized key."
          @tp.lti_errorlog = "You did it wrong!"
          @message = "Consumer key wasn't recognized"
          return false
        end
      else
        render("No consumer key")
        return false
      end

      if !@tp.valid_request?(request)
        @message = "The OAuth signature was invalid"
        return false
      end

      if Time.now.utc.to_i - @tp.request_oauth_timestamp.to_i > 60*60
        @message = "Your request is too old."
        return false
      end

      # this isn't actually checking anything like it should, just want people
      # implementing real tools to be aware they need to check the nonce
      if was_nonce_used_in_last_x_minutes?(@tp.request_oauth_nonce, 60)
        @message = "Why are you reusing the nonce?"
        return false
      end

      # @username = @tp.username("Dude")
      return true
    end

    def allow_iframe
      response.headers.except! 'X-Frame-Options'
    end

    def was_nonce_used_in_last_x_minutes?(nonce, minutes=60)
      # some kind of caching solution or something to keep a short-term memory of used nonces
      false
    end
end
