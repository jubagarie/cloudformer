require 'cloudformer'
require 'json'

# SAMPLE with custom config
# Sample command line usage
# STACK_NAME=xxx AWS_ACCESS_KEY=xxx AWS_SECRET_ACCCESS_KEY=xxx REGION=xxx CF_TEMPLATE=xxx.json CF_PARAM_ClusterSize=xxx CF_PARAM_SSLCertName=xxx rake -T

class AWSConfig

  attr_reader :profile

  def initialize key_file_path, profile_name
    @file_path = File.expand_path(key_file_path)
    @profile_name = profile_name
    load_profile
  end

  def cf_template_params
    aws_cf_params = {}
    ENV.select{|k,v| k.start_with?('CF_PARAM') }.each do |k,v|
        key = k.gsub("CF_PARAM_","")
      aws_cf_params[key] = v
    end
    aws_cf_params
  end

  def auth_config
    {
      stack_name: ENV['STACK_NAME'],
      aws_access_key: @profile['AWS_ACCESS_KEY'],
      aws_secret_access_key: @profile['AWS_SECRET_ACCESS_KEY'],
      region: ENV['REGION']
    }
  end

  def template
    ENV['CF_TEMPLATE']
  end

	def print_config_params
    cf_params = cf_template_params
    auth_cfg = auth_config
    final_params = cf_params.merge(auth_cfg)
		final_params.each do |k,v|
      puts "#{k}: #{v}" unless  ['aws_access_key','aws_secret_access_key'].include?(k.to_s)
		end
	end

  private

  def load_profile
    throw "Error: AWS config is not present! at #{@file_path}" unless File.exists? @file_path

    file = File.read(@file_path)
    @profile = JSON.parse(file)[@profile_name]
    throw "AWS Profile does not exist: #{profile_name}" if @profile.empty?
  end

end

aws_profile_name = ENV["AWS_PROFILE"]
key_file_path = "~/.aws/keys.json"
aws_config_obj = AWSConfig.new key_file_path, aws_profile_name

puts '##' + '-'*74 + '##'
puts "Running AWS Cloud Formation for profile #{aws_profile_name} tasks with following configuration"

#puts "PROFILE: #{aws_config_obj.profile}"
#puts "AWS_CONFIG: #{aws_config_obj.auth_config}"
#puts "CF_PARAMS: #{aws_config_obj.cf_template_params}"
aws_config_obj.print_config_params

puts '##' + '-'*74 + '##'

Cloudformer::Tasks.new(aws_config_obj.auth_config) do |t, args|
  t.template = aws_config_obj.template
  t.parameters = aws_config_obj.cf_template_params
  t.disable_rollback = false
  t.capabilities=[]
end
