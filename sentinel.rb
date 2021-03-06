require 'logger'
require 'rubygems'
require 'yaml'
require 'net/https'
require 'gli'
require './pagerduty'
include GLI::App

#program :name, 'sentinel'
version '0.01'
program_desc 'Alert upon task completion'
subcommand_option_handling :normal
sort_help :manually

config_file '.sentinel.rc'

desc 'PagerDuty hostname' 
flag [:h, :hostname, 'hostname']

desc 'PagerDuty API Key'
flag [:k, :api_key, 'api_key']

desc 'User email'
flag [:u, :username, 'user_email']

desc 'Target PagerDuty Escalation Policy'
flag [:e, :escalation_policy, 'escalation_p']

desc 'Delete Escalation Policy Upon:'
flag [:d, :delete_on], 'delete_flag', :must_match => ["ack", "key", "no"]

desc 'Number of loops target escalation policy will run'
flag [:l, :loops, 'loops'], :default_value => 1 

desc 'Escalation Policy repeatable'
switch :r, :repeatable, :default_value => false

desc 'Debug Level'
flag [:debug], 'debug_level', :default_value => 3, :must_match => { "debug" => 0,
                                                                    "info" => 1,
                                                                    "warn" => 2,
                                                                    "error" => 3,
                                                                    "fatal" => 4 }

desc "Test sentinel's readiness to monitor and alert"
command :test do |c|
  c.action do |global, options, arg|
    $logger.info("Action: Test, starting...")
    @sentinel = Sentinel.new($g_Sentinel_Opts)
    @sentinel.all_users
    puts("Able to connect to PagerDuty") if @sentinel.last_response = 200
    #@sentinel.run_command('/bin/ls -la > /dev/null')
    @sentinel.run_command(arg.join(" "))
    @sentinel.create_escalation_policy($g_Sentinel_Opts[:escal_policy], 
                                       $g_Sentinel_Opts[:user_email],
                                       $g_Sentinel_Opts[:loops],
                                       $g_Sentinel_Opts[:repeat])
    puts("Able to create policies") if @sentinel.last_response = 201
    @sentinel.delete_escalation_policy($g_Sentinel_Opts[:escal_policy])
    puts("Able to delete policies") if @sentinel.last_response = 204
  end
end

def get_sentinel_opts(global)
  sentinel_opts = {
    :hostname => global[:h],
    :api_key => global[:k],
    :user_email => global[:u],
    :escal_policy => global[:e],
    :delete_flag => global[:d],
    :loops => global[:l],
    :repeat => global[:r],
    :debug_lvl => global[:debug]
  }
  return sentinel_opts
end


pre do |global,commands,options,arg|
  $g_Sentinel_Opts = get_sentinel_opts(global)
  $logger = Logger.new(STDOUT)
  #logger.level = g_Sentinel_Opts[:debug_lvl]
  $logger.level = Logger::DEBUG
  $logger.info("Sentinel starting...")
  $logger.debug("g_Sentinel_Opts = #{$g_Sentinel_Opts}, args = #{arg}")
  
  $logger.info("Sentinel 'pre do' complete")
end
exit run(ARGV)
