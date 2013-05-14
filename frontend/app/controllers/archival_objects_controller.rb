class ArchivalObjectsController < ApplicationController
  skip_before_filter :unauthorised_access, :only => [:index, :show, :new, :edit, :create, :update, :parent, :transfer, :delete]
  before_filter(:only => [:index, :show]) {|c| user_must_have("view_repository")}
  before_filter(:only => [:new, :edit, :create, :update, :parent, :transfer]) {|c| user_must_have("update_archival_record")}
  before_filter(:only => [:delete]) {|c| user_must_have("delete_archival_record")}

  FIND_OPTS = {
    "resolve[]" => ["subjects", "location", "linked_agents", "digital_object", "resource", "parent"]
  }

  def new
    @archival_object = JSONModel(:archival_object).new._always_valid!
    @archival_object.parent = {'ref' => JSONModel(:archival_object).uri_for(params[:archival_object_id])} if params.has_key?(:archival_object_id)
    @archival_object.resource = {'ref' => JSONModel(:resource).uri_for(params[:resource_id])} if params.has_key?(:resource_id)

    return render :partial => "archival_objects/new_inline" if inline?

    # render the full AO form

  end

  def edit
    @archival_object = JSONModel(:archival_object).find(params[:id], FIND_OPTS)
    render :partial => "archival_objects/edit_inline" if inline?
  end


  def create
    handle_crud(:instance => :archival_object,
                :find_opts => FIND_OPTS,
                :on_invalid => ->(){ render :partial => "new_inline" },
                :on_valid => ->(id){

                  success_message = @archival_object.parent ?
                                      I18n.t("archival_object._frontend.messages.created_with_parent", JSONModelI18nWrapper.new(:archival_object => @archival_object, :resource => @archival_object['resource']['_resolved'], :parent => @archival_object['parent']['_resolved'])) :
                                      I18n.t("archival_object._frontend.messages.created", JSONModelI18nWrapper.new(:archival_object => @archival_object, :resource => @archival_object['resource']['_resolved']))

                  @refresh_tree_node = true

                  if params.has_key?(:plus_one)
                    flash[:success] = success_message
                  else
                    flash.now[:success] = success_message
                  end

                  render :partial => "archival_objects/edit_inline"

                })
  end


  def update
    @archival_object = JSONModel(:archival_object).find(params[:id], FIND_OPTS)
    resource = @archival_object['resource']['_resolved']
    parent = @archival_object['parent'] ? @archival_object['parent']['_resolved'] : false

    handle_crud(:instance => :archival_object,
                :obj => @archival_object,
                :on_invalid => ->(){ return render :partial => "edit_inline" },
                :on_valid => ->(id){
                  success_message = parent ?
                    I18n.t("archival_object._frontend.messages.updated_with_parent", JSONModelI18nWrapper.new(:archival_object => @archival_object, :resource => @archival_object['resource']['_resolved'], :parent => parent)) :
                    I18n.t("archival_object._frontend.messages.updated", JSONModelI18nWrapper.new(:archival_object => @archival_object, :resource => @archival_object['resource']['_resolved']))
                  flash.now[:success] = success_message

                  @refresh_tree_node = true

                  render :partial => "edit_inline"
                })
  end


  def show
    @resource_id = params['resource_id']
    @archival_object = JSONModel(:archival_object).find(params[:id], FIND_OPTS)
    render :partial => "archival_objects/show_inline" if inline?
  end


  def parent
    parent_id = (params[:parent] and !params[:parent].blank?) ? params[:parent] : nil
    response = JSONModel::HTTP.post_form(JSONModel(:archival_object).uri_for(params[:id]) + "/parent",
                              :parent => parent_id,
                              :position => params[:index])

    if response.code == '200'
      render :json => {:parent => parent_id ? JSONModel(:archival_object).uri_for(parent_id) : nil}
    else
      raise "Error setting parent of archival object: #{response.body}"
    end
  end


  def transfer
    begin
      post_data = {
        :target_resource => params["transfer"]["ref"],
        :component => JSONModel(:archival_object).uri_for(params[:id])
      }

      response = JSONModel::HTTP.post_form("/repositories/#{session[:repo_id]}/component_transfers", post_data)

      if response.code == '200'
        @archival_object = JSONModel(:archival_object).find(params[:id], FIND_OPTS)

        flash[:success] = I18n.t("archival_object._frontend.messages.transfer_success", JSONModelI18nWrapper.new(:archival_object => @archival_object, :resource => @archival_object['resource']['_resolved']))
        redirect_to :controller => :resources, :action => :edit, :id => JSONModel(:resource).id_for(params["transfer"]["ref"]), :anchor => "tree::archival_object_#{params[:id]}"
      else
        raise ASUtils.json_parse(response.body)['error'].to_s
      end

    rescue Exception => e
      flash[:error] = I18n.t("archival_object._frontend.messages.transfer_error", :exception => e)
      redirect_to :controller => :resources, :action => :edit, :id => params["transfer"]["current_resource_id"], :anchor => "tree::archival_object_#{params[:id]}"
    end
  end


  def delete
    archival_object = JSONModel(:archival_object).find(params[:id])
    archival_object.delete

    flash[:success] = I18n.t("archival_object._frontend.messages.deleted", JSONModelI18nWrapper.new(:archival_object => archival_object))

    resolver = Resolver.new(archival_object['resource']['ref'])
    redirect_to resolver.view_uri
  end


end
