
module Brewbit
  class DeviceSessionsController < ApplicationController
    layout 'brewbit/layouts/devices'
    before_action :correct_user
    before_action :correct_device
    before_action :correct_device_session, only: [:show, :edit, :destroy, :stop_session]

    # GET /sessions
    def index
      @device_sessions = @device.sessions.where(active: false).order( 'created_at DESC' )
    end

    # GET /sessions/1
    def show
    end

    # GET /sessions/new
    def new
      @device_session = Defaults.build_device_session @device, brewbit_current_user.temperature_scale
    end

    # GET /sessions/1/edit
    def edit
    end

    # POST /sessions
    def create
      begin
        DeviceSession.transaction do
          # create the new session, but don't save it yet because we need to
          # find and deactivate the old session first
          @device_session = DeviceSession.new(device_session_params)
          @device_session.active = true

          # deactivate old session
          old_session = @device.active_session_for @device_session.sensor_index
          if old_session
            old_session.active = false
            old_session.save!
          end

          # save the new session
          @device_session.save!

          DeviceService.send_session @device, @device_session
        end
      rescue ActiveRecord::RecordInvalid => invalid
        @device_session = reset_device_session_on_error

        flash[:error] = invalid.record.errors.full_messages.to_sentence
        render action: 'new'
      rescue => e
        puts $!.inspect, $@

        logger.debug e.inspect

        @device_session = reset_device_session_on_error
        flash[:error] = 'Session could not be sent to the device.'
        render action: 'new'
      else
        redirect_to @device, notice: 'Device session was successfully sent.'
      end
    end

    # DELETE /sessions/1
    def destroy
      @device_session.destroy
      redirect_to device_sessions_path, notice: 'Device session was successfully destroyed.'
    end

    def stop_session
      begin
        DeviceSession.transaction do
          empty_session = @device_session.clone
          empty_session.output_settings = []

          @device_session.active = false
          @device_session.save!
          DeviceService.send_session @device, empty_session
        end

        redirect_to @device, error: 'Device session was successfully destroyed.'
      rescue => exception
        logger.debug "--- #{exception.inspect}"
        redirect_to @device, error: 'Session could not be sent to the device.'
      end
    end

    private
      # Use callbacks to share common setup or constraints between actions.
      def correct_device_session
        @device_session = @device.sessions.find(params[:id])
        redirect_to root_path, error: 'You can only see your own sessions' unless @device_session
      end

      def correct_device
        @device = brewbit_current_user.devices.find(params[:device_id])
        redirect_to root_path, error: 'You can only see your own devices' unless @device
        
        @active_session_output_info = @device.active_session_output_info
      end
      
      def correct_user
        redirect_to login_path unless brewbit_current_user
      end

      # Only allow a trusted parameter "white list" through.
      def device_session_params
        params.require(:device_session).permit(
          :name, :device_id, :sensor_index, :setpoint_type, :static_setpoint, :temp_profile_id,
          output_settings_attributes: [:id, :output_index, :function, :cycle_delay, :_destroy])
      end

      def reset_device_session_on_error
        dsp = device_session_params
        dsp[:output_settings_attributes].each {|id, attrs| attrs.delete '_destroy' }
        DeviceSession.new(dsp)
      end
  end
end
