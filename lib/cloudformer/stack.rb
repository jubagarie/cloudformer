require 'aws-sdk'
require 'httparty'
require 'rainbow'

class Stack
  attr_accessor   :stack, :name, :deployed, :resource

  SUCESS_STATES  = ["CREATE_COMPLETE", "UPDATE_COMPLETE", "ROLLBACK_COMPLETE", "UPDATE_ROLLBACK_COMPLETE"]
  FAILURE_STATES = ["CREATE_FAILED", "DELETE_FAILED", "UPDATE_ROLLBACK_FAILED", "ROLLBACK_FAILED", "ROLLBACK_FAILED", "UPDATE_ROLLBACK_FAILED"]
  END_STATES     = SUCESS_STATES + FAILURE_STATES

  WAITING_STATES = ["CREATE_IN_PROGRESS","DELETE_IN_PROGRESS","ROLLBACK_IN_PROGRESS","UPDATE_COMPLETE_CLEANUP_IN_PROGRESS","UPDATE_IN_PROGRESS","UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS","UPDATE_ROLLBACK_IN_PROGRESS"]

  # Config options
  # {:aws_access_key => nil, :aws_secert_access_key => nil, :region => nil}

  def initialize(config)
    @name = config[:stack_name]
    @cf = Aws::CloudFormation::Client.new(region: config[:region])
    @resource = Aws::CloudFormation::Resource.new(client: @cf)
    @stack = @resource.stack(@name) 
    @ec2 = Aws::EC2::Client.new region: config[:region]
  end

  
  def status_message
    message = ""
    begin
      message =  stack.stack_status   
    rescue Exception => e
      message = "DOESNT_EXIST" if e.message == "Stack:#{name} does not exist" 
    end 
    return message
  end
  
  def status_reason
    message = ""
    begin
      message =  stack.stack_status_reason  
    rescue Exception => e
      message =  e.message 
    end 
    return message
  end

  def deployed
    SUCESS_STATES.include?(status_message) ? true : false
  end

  def apply(template_file, template_body, parameters, disable_rollback=false, capabilities=[], notify=[], tags=[])
    validation = validate(template_file)
    unless validation["valid"]
      puts "Unable to update - #{validation["response"][:code]} - #{validation["response"][:message]}"
      return :Failed
    end
    pending_operations = false
    begin
      if deployed
        pending_operations = update(template_body, parameters, capabilities)
      else
        pending_operations = create(template_body, parameters, disable_rollback, capabilities, notify, tags)
      end
    rescue Aws::CloudFormation::Errors::ServiceError => e
      puts Rainbow(e.message).red
      return (if e.message == "No updates are to be performed." then :NoUpdates else :Failed end)
    end
    wait_until_end if pending_operations
    return (if deploy_succeded? then :Succeeded else :Failed end)
  end

  def validate(template_file)
    template_body = File.read(template_file)
    begin
      response = @cf.validate_template(template_body: template_body, template_url: nil)
      return {
        "valid" => true,
        "response" => response
      }
    rescue Exception => e
      return {
        "valid" => false,
        "response" => e.message
      }
    end
  end

  def update(template_body, parameters, capabilities)
    template_options = {:template_body => template_body }
    options = {
      :stack_name => name,
      :parameters =>  parameters,
      :capabilities =>  capabilities
    }
    options = options.merge(template_options)
    stack.update(options)
    return true
  end

  def create(template_body, parameters, disable_rollback, capabilities, notify, tags)
    puts Rainbow("---> Initializing stack creation...").yellow
    template_options = {:template_body => template_body }
    options = {
      :stack_name => name,
      :disable_rollback =>  disable_rollback,
      :parameters =>  parameters,
      :capabilities =>  capabilities
    }
    options = options.merge(template_options)
    resource.create_stack(options)
    sleep 10
    return true
  end

  def deploy_succeded?
    return true if SUCESS_STATES.include?(status_message)
    return true if WAITING_STATES.include?(status_message)
    puts Rainbow("--> Unable to deploy template. Check log for more information.").red
    false
  end

  def stop_instances
   update_instances("stop")
  end

  def start_instances
    update_instances("start")
  end

  def delete
    puts Rainbow("---> Attempting to delete stack - #{name}").yellow
    stack.delete
    wait_until_end
    return deploy_succeded?
  end

  def status
    if deployed
      puts Rainbow("    #{stack.name} - #{stack.stack_status} - #{stack.stack_status_reason}").green
    else
      puts Rainbow("    #{stack.name} - Not Deployed").red
    end
  end

  def events(options = {})
    if !deployed
      puts Rainbow("---> Stack not up.").red
      return
    end
    stack.events.sort_by {|a| a.timestamp}.each do |event|
      puts Rainbow("#{event.timestamp} - #{event.physical_resource_id.to_s} - #{event.logical_resource_id} - #{event.resource_type} - #{event.resource_status} - #{event.resource_status_reason.to_s}").yellow
    end
  end

  def outputs
    if !deployed
      puts Rainbow("Stack not up.").red
      return 1
    end
    stack.outputs.each do |output|
      puts Rainbow("#{output.output_key} - #{output.description} - #{output.output_value}").yellow
    end
    return 0
  end

  private
  def wait_until_end
    printed = []
    current_time = Time.now
    if !deployed
      puts Rainbow("Stack not up.").red
      return
    end
    loop do
      sleep(3)
      puts Rainbow("--> events loop : #{stack.stack_status}").blue
      printable_events = stack.events.reject{|a| (a.timestamp < current_time)}.sort_by {|a| a.timestamp}.reject {|a| a if printed.include?(a.event_id)}
      printable_events.each { |event| puts Rainbow("---> #{event.timestamp} - #{event.physical_resource_id.to_s} - #{event.resource_type} - #{event.resource_status} - #{event.resource_status_reason.to_s}").yellow }
      printed.concat(printable_events.map(&:event_id))
      break if END_STATES.include?(stack.stack_status)
      sleep(10)
    end
  end

  def update_instances(action)
    puts Rainbow("---> Attempting to #{action} all ec2 instances in the stack #{stack.name}").yellow
    return "Stack not up" if !deployed
    stack.resources.each do |resource|
      begin
        next if resource.resource_type != "Aws::EC2::Instance"
        physical_resource_id = resource.physical_resource_id
        puts Rainbow("    Attempting to #{action} Instance with physical_resource_id: #{physical_resource_id}").yellow
        @ec2.instances[physical_resource_id].send(action)
      rescue
        puts Rainbow("---> Some resources are not up.").red
      end
    end
  end
end

