class HomeController < ApplicationController

  def index
    if params.keys.include? 'filter'
      no_filter = Regexp.new(/[a-zA-Z|\s]/)
      status_filter = params["filter"]["status"].empty? ? no_filter : params["filter"]["status"]
      bidding_filter = params["filter"]["bidding"].empty? ? no_filter : params["filter"]["bidding"].downcase.to_sym
      filtered_programs = Program.where(status: status_filter, bidding_policy: bidding_filter)
      @selected_programs = filtered_programs.paginate(page: params[:page], per_page: 20)
      @total_count = Program.all.count
      @applied_filters = params["filter"]
    else
      @selected_programs = Program.all.paginate(page: params[:page], per_page: 20)
    end
  end

  def modal
    @selected_program = Program.where(prgm_id: params[:prgm_id]).first
  end

end