require 'aws-sdk'

class Stack
  attr_accessor   :stack, :name, :deployed, :resource

  SUCESS_STATES  = ["CREATE_COMPLETE", "UPDATE_COMPLETE"]
  FAILURE_STATES = ["CREATE_FAILED", "DELETE_FAILED", "UPDATE_ROLLBACK_FAILED", "ROLLBACK_FAILED", "ROLLBACK_COMPLETE","ROLLBACK_FAILED","UPDATE_ROLLBACK_COMPLETE","UPDATE_ROLLBACK_FAILED"]
  END_STATES     = SUCESS_STATES + FAILURE_STATES

  # WAITING_STATES = ["CREATE_IN_PROGRESS","DELETE_IN_PROGRESS","ROLLBACK_IN_PROGRESS","UPDATE_COMPLETE_CLEANUP_IN_PROGRESS","UPDATE_IN_PROGRESS","UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS","UPDATE_ROLLBACK_IN_PROGRESS"]

  # Config options
  # {:aws_access_key => nil, :aws_secert_access_key => nil, :region => nil}

  def initialize(config)
    @name = config[:stack_name]
    puts @name + config[:region]
    Aws.config[:credentials] = Aws::Credentials.new(config[:aws_access_key], config[:aws_secret_access_key])
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

  def apply(template_file, parameters, disable_rollback=false, capabilities=[], notify=[])
    if ( template_file =~ /^https:\/\/.*(.json)$/ )
      template = template_file
    elsif ( template_file =~ /^https:\/\/s3\S+\.amazonaws\.com\/(.*)/ )
      template = template_file
    else
      template_body = File.read(template_file)
    end
    validation = validate(template_body, template_url)
    unless validation["valid"]
      puts "Unable to update - #{validation["response"][:code]} - #{validation["response"][:message]}"
      return :Failed
    end
    pending_operations = false
    begin
      if deployed
        pending_operations = update(template_body, template_url parameters, capabilities)
      else
        pending_operations = create(template_body, template_url parameters, disable_rollback, capabilities, notify)
      end
    rescue ::AWS::CloudFormation::Errors::ValidationError => e
      puts e.message
      return (if e.message == "No updates are to be performed." then :NoUpdates else :Failed end)
    end
    wait_until_end if pending_operations
    return (if deploy_succeded? then :Succeeded else :Failed end)
  end

  def deploy_succeded?
    return true unless FAILURE_STATES.include?(status_message)
    puts "Unable to deploy template. Check log for more information."
    false
  end

  def stop_instances
   update_instances("stop")
  end

  def start_instances
    update_instances("start")
  end

  def delete
    with_highlight do
      puts "Attempting to delete stack - #{name}"
      stack.delete
      wait_until_end
      return deploy_succeded?
    end
  end

  def status
    with_highlight do
      if deployed
        puts "#{stack.name} - #{stack.stack_status} - #{stack.stack_status_reason}"
      else
        puts "#{stack.name} - Not Deployed"
      end
    end
  end

  def events(options = {})
    with_highlight do
      if !deployed
        puts "Stack not up."
        return
      end
      stack.events.sort_by {|a| a.timestamp}.each do |event|
        puts "#{event.timestamp} - #{event.physical_resource_id.to_s} - #{event.logical_resource_id} - #{event.resource_type} - #{event.resource_status} - #{event.resource_status_reason.to_s}"
      end
    end
  end

  def outputs
    with_highlight do
    if !deployed
      puts "Stack not up."
      return 1
    end
      stack.outputs.each do |output|
        puts "#{output.key} - #{output.description} - #{output.value}"
      end
    end
    return 0
  end

  private
  def wait_until_end
    printed = []
    current_time = Time.now
    with_highlight do
      if !deployed
        puts "Stack not up."
        return
      end
      loop do
        printable_events = stack.events.reject{|a| (a.timestamp < current_time)}.sort_by {|a| a.timestamp}.reject {|a| a if printed.include?(a.event_id)}
        printable_events.each { |event| puts "#{event.timestamp} - #{event.physical_resource_id.to_s} - #{event.resource_type} - #{event.resource_status} - #{event.resource_status_reason.to_s}" }
        printed.concat(printable_events.map(&:event_id))
        break if END_STATES.include?(status_message)
        sleep(30)
      end
    end
  end

  def with_highlight &block
    cols = `tput cols`.chomp!.to_i
    puts "="*cols
    yield
    puts "="*cols
  end

  def validate(template_body, template_url)
    ret_val ={}
    begin
      response = @cf.validate_template(template_body: template_body, template_url: template_url)
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

  def update(template_body, template_url, parameters, capabilities)
    template_options = {}
    if template_url.nil? then
      template_options = {:template_body => template_body }
    elsif template_body.nil? then
      template_options = { :template_url =>  template_url }
    else
      puts "Use either template_url or template_body!!"
      exit 1
    end
    
    options = {
                  :stack_name => name,
                  :parameters =>  parameters,
                  :capabilities =>  capabilities

              }
    options = options.merge(template_options)
    stack.update(options)
    return true
  end

  def create(template_body, template_url, parameters, disable_rollback, capabilities, notify)
    puts "Initializing stack creation..."
    
    template_options = {}
    if template_url.nil? then
      template_options = {:template_body => template_body }
    elsif template_body.nil? then
      template_options = { :template_url =>  template_url }
    else
      puts "Use either template_url or template_body!!"
      exit 1
    end
    
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

  def update_instances(action)
    with_highlight do
      puts "Attempting to #{action} all ec2 instances in the stack #{stack.name}"
      return "Stack not up" if !deployed
      stack.resources.each do |resource|
        begin
          next if resource.resource_type != "Aws::EC2::Instance"
          physical_resource_id = resource.physical_resource_id
          puts "Attempting to #{action} Instance with physical_resource_id: #{physical_resource_id}"
          @ec2.instances[physical_resource_id].send(action)
        rescue
          puts "Some resources are not up."
        end
      end
    end
  end
end

