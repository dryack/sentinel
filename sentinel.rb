require 'logger'
require 'rubygems'
require 'yaml'
require 'net/https'
require 'gli'
include GLI::App

#program :name, 'sentinel'
version '0.01'
program_desc 'Alert upon task completion'
subcommand_option_handling :normal
sort_help :manually

config_file '.sentinel.rc'

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
                                                                   "fatal" => 4}


def get_sentinel_ops(global)
  sentinel_opts = {
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
  g_Sentinel_Opts = get_sentinel_opts(global)
  
  logger = Logger.new(STDOUT)
  #logger.level = g_Sentinel_Opts[:debug_lvl]
  logger.level = Logger::DEBUG

  logger.info("Sentinel starting...")
  logger.debug("g_Sentinel_Opts = #{g_Sentinel_Opts}, args = #{ARG}")
  
  $sentinel = Sentinel::Client.new(g_Sentinel_opts)
  
  logger.info("Sentinel 'pre do' complete")
end
exit run(ARGV)
