class OrganizationsController < ApplicationController

  # -------------------------------------------------------------
  def index
    if params[:term_id]
      @term = Term.find(params[:term_id])
    else
      @term = Term.current_term
    end

    # equivalent to load_and_authorize_resource.
    # The authorize is handled with accessible_by, then the load is
    # performed with a custom query
    @organizations = Organization.accessible_by(current_ability).
      includes(courses: :course_offerings).
      joins(courses: :course_offerings).
      where('course_offerings.term_id' => @term).
      distinct
  end

  def search
    if params[:term]
      @organizations = Organization.where('name LIKE ? or abbreviation LIKE ?', "#{params[:term]}%", "#{params[:term]}%")
    else
      @organizations = Organization.all
    end

    @organizations = Organization.all
    render json: @organizations.to_json and return
  end

  # -------------------------------------------------------------
  def show
    if params[:term_id]
      @term = Term.find(params[:term_id])
    else
      @term = Term.current_term
    end

    # equivalent to load_and_authorize_resource.
    # The authorize is handled with accessible_by, then the load is
    # performed with a custom query
    @organization = Organization.accessible_by(current_ability).
      includes(courses: :course_offerings).
      joins(courses: :course_offerings).
      where('course_offerings.term_id' => @term).
      find(params[:id])
  end

  def new_or_existing
    render layout: 'one_column'
  end

  #~ Private instance methods .................................................
  private

    # -------------------------------------------------------------
    # Only allow a trusted parameter "white list" through.
    def organization_params
      params.require(:organization).permit(:name, :abbreviation, :term_id)
    end


    # -------------------------------------------------------------
    # Defines resource human-readable name for use in flash messages.
    def interpolation_options
      { resource_name: @organization.name }
    end


end
