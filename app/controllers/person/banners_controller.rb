# frozen_string_literal: true

class Person::BannersController < ApplicationController
  include PersonConcern

  before_action :require_banner_manager
  before_action :set_person_banner, only: [:edit, :update, :destroy]

  def index
    @person_banners = @person.person_banner.order(created_at: :desc)
  end

  def new
    @person_banner = @person.person_banner.build
  end

  def create
    @person_banner = @person.person_banner.build(person_banner_params)

    if @person_banner.save
      redirect_to person_banners_path(@person), success: "Banner record created."
      return
    end

    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @person_banner.update(person_banner_params)
      redirect_to person_banners_path(@person), success: "Banner record updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @person_banner.destroy
    redirect_to person_banners_path(@person), success: "Banner record deleted."
  end

  private

  def require_banner_manager
    return true if can_manage_banners?

    redirect_to person_path(@person), error: "You are not authorized to manage account banners."
    false
  end

  def set_person_banner
    @person_banner = @person.person_banner.find(params[:id])
  end

  def person_banner_params
    params.expect(person_banner: [:is_permanent, :message])
  end
end
