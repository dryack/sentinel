#require './sentinel'
require 'rubygems'
require 'httparty'
require 'time'
require 'json'



class Sentinel
  include HTTParty
  
  attr_accessor :last_response

  def new(g_Sentinel_Opts)
    initialize(g_Sentinel_Opts)
  end

  def initialize(g_Sentinel_Opts)
    $logger.info("Sentinel.initialize() running")
    @base = "https://#{g_Sentinel_Opts[:hostname]}/api/v1"
    @key =  "#{g_Sentinel_Opts[:api_key]}"
    @ids = {}
    @escal_ids = {}
    @users = nil
    @last_response = nil
    $logger.debug("base: #{@base}; key #{@key}")
  end

  def pd_get(url)
    # Returns a hash for the object.
    $logger.info("Entering pd_get() with url: #{url}")
    response = HTTParty.get(url,
                            :headers => {
                              "Authorization" => "Token token=#{@key}"
                            })
    parse_pd_response(response)
  end

  def pd_post(url, data)
    response = HTTParty.post(
      url,
      :headers => {
        "Authorization" => "Token token=#{@key}",
        'Content-Type' => 'application/json',
      },
      :body => data.to_json
    )
    parse_pd_response(response)
  end

  def pd_put(url, data)
    response = HTTParty.put(
      url,
      :headers => {
        "Authorization" => "Token token=#{@key}",
        'Content-Type' => 'application/json',
      },
      :body => data.to_json
    )
    parse_pd_response(response)
  end
  
  def pd_delete(url)
    $logger.info("Entering pd_delete()")
    response = HTTParty.delete(
      url,
      :headers => {
        "Authorization" => "Token token=#{@key}",
        'Content-Type' => 'application/json',
      },
    )
    parse_pd_response(response)
  end

  def all_users
    if @users.nil?
      response = pd_get("#{@base}/users?limit=100")
      @users = {}

      response["users"].each do |user|
        @users[user['email']] = user
      end
    end
    @users
  end

  def user_by_email(email)
    all_users[email]
  end

  def user_id_by_email(email)
    user_by_email(email)['id']
  end

  def oncall_by_escalation(e_id)
    raw_response = pd_get("#{@base}/escalation_policies/on_call")
    found = raw_response['escalation_policies'].select {|details| details['id'] == e_id}
    raise MissingEscalationPolicy.new(e_id) if found.empty?
    found.map {|policy|
      policy.fetch('on_call')
    }.flatten
  end

  def oncall_by_queue(id)
    now = Time.now.utc
    range = now + 1
    result = pd_get("#{@base}/schedules/#{id}/entries?since=#{now.iso8601}&until=#{range.iso8601}&overflow=true")
    result.fetch('entries')
  end

  def oncall(queue_name, escal_or_queue="escalation")
    if escal_or_queue == 'queue'
      id = @ids[queue_name]
      raise InvalidOncallGroup.new(queue_name) unless id
      return oncall_by_queue(id)
    else
      e_id = @escal_ids[queue_name]
      raise InvalidOncallGroup.new(queue_name) unless e_id
      return oncall_by_escalation(e_id)
    end
  end
  
  def create_escalation_policy(escalation_policy, user_email, loops, repeatable)
    id = user_id_by_email(user_email)
    data = {}
    data = {
      "name" => escalation_policy,
      "repeat_enabled" => repeatable,
      "num_loops" => loops.to_i,
      "escalation_rules" => [
        "escalation_delay_in_minutes" => 10,
        "targets" => [
          {
            "type" => "user",
            "id" => "#{id}"
          }
        ]
      ]
   }
   pd_post("#{@base}/escalation_policies", data)
  end

  def delete_escalation_policy(escalation_policy)
    $logger.info("Entering delete_escalation_policy()")
    escalation_id = escalation_policy_by_name(escalation_policy)
    unless escalation_id.nil?
      pd_delete("#{@base}/escalation_policies/#{escalation_id}")
    else
      $logger.info("No escalation policy named #{escalation_policy} was found in PagerDuty.")
    end
  end

  def escalation_policy_by_name(escalation_policy)
    $logger.info("Entering escalation_policy_by_name()")
    response = pd_get("#{@base}/escalation_policies/?query=#{escalation_policy}")
    if response['escalation_policies'][0].nil?
      return nil
    else
      return response['escalation_policies'][0]['id']
    end
  end
    
  def place_override(schedule_id, email, start, finish)
    id = user_id_by_email(email)
    data = {}
    data["override"] = {
      "user_id" => id,
      "start" => start,
      "end" => finish,
    }
    pd_post("#{@base}/schedules/#{schedule_id}/overrides", data)
  end

  def place_override_by_length(schedule_id, email, length)
    start = Time.now.utc
    finish = start + 60 * length
    start = start.iso8601
    finish = finish.iso8601
    place_override(schedule_id, email, start, finish)
  end

  def override(schedule, email, length)
    queue_schedule = @ids[schedule]
    place_override_by_length(queue_schedule, email, length)
  end

  def incidents(status)
    pd_get("#{@base}/incidents?status=#{status}")
  end

  def put_incident(status, requester_id, incident_ids)
    data = {}
    data['requester_id'] = requester_id
    incidents = []
    incident_ids.each do |id|
      incidents.push(
        "id" => id,
        "status" => status
      )
    end
    data['incidents'] = incidents
    pd_put("#{@base}/incidents", data)
  end

  def update(incidents, new_status, user_id)
    matches = incidents.select { |x| x['assigned_to'].detect { |i| i['object']['id'] == user_id }}
    incident_ids = matches.map {|x| x['id']}
    put_incident(new_status, user_id, incident_ids) unless incident_ids.empty?
  end

  def acknowledge(user_id)
    # Just transmute all triggered's to acknowledged's
    update(incidents('triggered')['incidents'], 'acknowledged', user_id)
  end

  def resolve(user_id)
    # Get both types so we can update both
    triggered = incidents('triggered')['incidents']
    acked = incidents('acknowledged')['incidents']
    update(triggered + acked, 'resolved', user_id)
  end

  def run_command(*args)
    $logger.info("Entering run_command()")
    os_response = system(args.join(","))
    parse_os_response(os_response)
  end

  private

  def parse_pd_response(response)
#    raise InvalidPagerDutyToken if response.code == 401
    $logger.info("Entering parse_pd_response()")
    $logger.debug("Response code: #{response.code}")
    @last_response = response.code
    unless response.code == 200 || response.code == 204 || response.body == nil
      if response.body == nil
        $logger.debug("No response.body was returned by server")
      else
        $logger.debug(response)
      end
    end
    JSON.parse(response.body) unless response.body == nil
  end
  
  def parse_os_response(os_response)
    $logger.info("Entering parse_os_response()")
    p os_response 
  end

end
