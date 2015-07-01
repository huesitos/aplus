class ShareRequestController < ApplicationController
  def new
    @share_request = ShareRequest.new
    @view_title = "Share with"
    @users = User.where(:_id => { "$ne" => session[:user_id]}).pluck(:username, :_id)
    @url = share_requests_path(params[:object_type],params[:oid], params[:name])
  end

  def create
    @view_title = "Share with"
    @users = User.where(:_id => { "$ne" => session[:user_id]}).pluck(:username, :_id)
    sender = User.find(session[:user_id])
    if params[:commit] = "Send copy"
      @share_request = ShareRequest.new(
        kind: "share", 
        object_type: params[:object_type], 
        name: params[:name], 
        oid: params[:oid], 
        sender_id: sender.id, 
        sender_uname: sender.username, 
        recipient: params[:share_request][:recipient])

      user=User.find(params[:share_request][:recipient])

      respond_to do |format|
        if user
          if @share_request.save
            if params[:object_type] == 'topic'
              format.html { redirect_to Topic.find(params[:oid]) }
            else
              format.html { redirect_to Subject.find(params[:oid]) }
              end
          else
            format.html { render :new }
            format.json { render json: @share_request.errors, status: :unprocessable_entity }
          end
        else
          flash[:error] = "Username not found."
          format.html { redirect_to share_request_new_path }
        end
      end
    end
  end

  def share
     share_request = ShareRequest.find(params[:id])
     if share_request[:object_type] == "topic"
      topic = Topic.find(share_request[:oid])
      topic.share(share_request.recipient, nil)
     else
      subject = Subject.find(share_request[:oid])
      subject.share(share_request.sender_id, share_request.recipient)
     end
     share_request.destroy

     respond_to do |format|
       format.html { redirect_to share_request_notify_path }
     end
  end

  def notify
    @view_title = "Notifications"
    @share_requests = ShareRequest.where(recipient: session[:user_id])
  end

  def destroy
    share_request = ShareRequest.find(params[:id])
    share_request.destroy

    respond_to do |format|
      format.html { redirect_to share_request_notify_path }
    end
  end
end
