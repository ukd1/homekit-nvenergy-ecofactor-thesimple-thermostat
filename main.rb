require "ruby_home"
require "typhoeus"

unless ENV.has_key?("THESIMPLE_BEARER_TOKEN")
  puts "Please set the THESIMPLE_BEARER_TOKEN ENV var. You can get the token by inspecting the API calls from the website."
  exit 1
end

RubyHome.configure do |c|
  c.discovery_name = 'NV Energy'
  c.model_name = 'S100 Thermostat Bridge'
  c.password = "111-11-111"
end

response = Typhoeus::Request.new(
  "https://home.thesimple.com/ws/v1.0/user",
  method: :get,
  headers: { Accept: "application/json", Authorization: "Bearer #{ENV["THESIMPLE_BEARER_TOKEN"]}" }
).run

if response.response_code == 200
  user_info = JSON.parse(response.body)
  puts "Hi #{user_info['first_name']}"
else
  raise "Error, something went wrong checking for your user info #{response.inspect}"
end

if user_info['location_id_list'].count == 0
  puts "Somehow, there are no locations listed on your user profile."
  exit 1
elsif user_info['location_id_list'].count > 0
  puts "Only looking at the first location of #{user_info['location_id_list'].join(', ')}."
end

response = Typhoeus::Request.new(
  "https://home.thesimple.com/ws/v1.0/location/#{user_info['location_id_list'][0]}",
  method: :get,
  headers: { Accept: "application/json", Authorization: "Bearer #{ENV["THESIMPLE_BEARER_TOKEN"]}" }
).run

if response.response_code == 200
  thermostat_ids = JSON.parse(response.body)['thermostat_id_list']
  puts "Found: " + thermostat_ids.join(', ')
else
  raise "Error, something went wrong checking for your location #{response.inspect}"
end

def get_lastest_data(thermostat_ids)
  thermostats = {}

  thermostat_ids.each do |thermostat_id|
    response = Typhoeus::Request.new(
      "https://home.thesimple.com/ws/v1.0/thermostat/#{thermostat_id}/state",
      method: :get,
      headers: { Accept: "application/json", Authorization: "Bearer #{ENV["THESIMPLE_BEARER_TOKEN"]}" }
    ).run

    if response.response_code == 200
      thermostats[thermostat_id] = JSON.parse(response.body)
    end
  end

  thermostats
end

def get_names(thermostat_ids)
  thermostats = {}

  thermostat_ids.each do |thermostat_id|
    response = Typhoeus::Request.new(
      "https://home.thesimple.com/ws/v1.0/thermostat/#{thermostat_id}",
      method: :get,
      headers: { Accept: "application/json", Authorization: "Bearer #{ENV["THESIMPLE_BEARER_TOKEN"]}" }
    ).run

    if response.response_code == 200
      thermostats[thermostat_id] = JSON.parse(response.body)
    end
  end

  thermostats
end

def set_target(thermostat_id, target_temperature_celsius)
  response = Typhoeus::Request.new(
    "https://home.thesimple.com/ws/v1.0/thermostat/#{thermostat_id}/state",
    method: :patch,
    headers: { Accept: "application/json", "Content-Type" => "application/json", Authorization: "Bearer #{ENV["THESIMPLE_BEARER_TOKEN"]}" },
    body: {cool_setpoint: target_temperature_celsius.to_f.to_fahrenheit, hvac_mode: "cool"}.to_json
  ).run

  response.response_code == 200
end

class Float
  def to_celsius
    (self - 32) * 5 / 9
  end

  def to_fahrenheit
    (self * 9 / 5) + 32
  end
end

rh_thermostats = {}
thermostats = get_names(thermostat_ids)
thermostat_states = get_lastest_data(thermostat_ids)

accessory_information = RubyHome::ServiceFactory.create(:accessory_information)

thermostats.each do |thermostat_id, thermostat|
  thermostat_name = thermostats[thermostat_id]['name']
  thermostat_state = thermostat_states[thermostat_id]

  rh_thermostats[thermostat_id] = RubyHome::ServiceFactory.create(:thermostat,
    temperature_display_units: 1, # f
    target_temperature: thermostat_state['best_known_current_state_thermostat_data']['cool_setpoint'].to_f.to_celsius.clamp(10,38), # required shrug
    current_temperature: thermostat_state['best_known_current_state_thermostat_data']['temperature'].to_f.to_celsius.clamp(0,100),
    target_heating_cooling_state: 0, # required
    current_heating_cooling_state: 0, # required
    name: thermostat_name, # optional
    heating_threshold_temperature: thermostat_state['best_known_current_state_thermostat_data']['heat_setpoint'].to_f.to_celsius.clamp(0,25),
    cooling_threshold_temperature: thermostat_state['best_known_current_state_thermostat_data']['cool_setpoint'].to_f.to_celsius.clamp(10,35),
  )


  rh_thermostats[thermostat_id].target_temperature.after_update do |target_temperature|
    puts "\t#{thermostat_name}: target temperature set to #{target_temperature.to_f.to_fahrenheit}f"
    set_target(thermostat_id, target_temperature.to_f)

    if target_temperature.to_i > rh_thermostats[thermostat_id].current_temperature.to_f.to_celsius
      rh_thermostats[thermostat_id].target_heating_cooling_state = 1
    elsif target_temperature < rh_thermostats[thermostat_id].current_temperature.to_f.to_celsius
      rh_thermostats[thermostat_id].target_heating_cooling_state = 2
    elsif target_temperature.to_i == rh_thermostats[thermostat_id].current_temperature.to_f.to_celsius
      rh_thermostats[thermostat_id].target_heating_cooling_state = 0
    end
  end

  rh_thermostats[thermostat_id].current_temperature.after_update do |current_temperature|
    puts "\t#{thermostat_name}: current temperature is #{current_temperature.to_fahrenheit}f"

    if current_temperature.to_f < rh_thermostats[thermostat_id].target_temperature.to_f.to_celsius
      rh_thermostats[thermostat_id].target_heating_cooling_state = 1
    elsif current_temperature.to_f > rh_thermostats[thermostat_id].target_temperature.to_f.to_celsius
      rh_thermostats[thermostat_id].target_heating_cooling_state = 2
    elsif current_temperature.to_f == rh_thermostats[thermostat_id].target_temperature.to_f.to_celsius
      rh_thermostats[thermostat_id].target_heating_cooling_state = 0
    end
  end

  target_heating_cooling_state_values = {
    0 => 'Off',
    1 => 'Heat',
    2 => 'Cool',
    3 => 'Auto',
  }
  rh_thermostats[thermostat_id].target_heating_cooling_state.after_update do |target_heating_cooling_state|
    state = target_heating_cooling_state_values[target_heating_cooling_state]
    puts "\t#{thermostat_name}: #{state}"

    return if rh_thermostats[thermostat_id].current_heating_cooling_state == target_heating_cooling_state

    if target_heating_cooling_state == 1
      rh_thermostats[thermostat_id].current_heating_cooling_state = 1
    elsif target_heating_cooling_state == 2
      rh_thermostats[thermostat_id].current_heating_cooling_state = 2
    elsif target_heating_cooling_state == 0
      rh_thermostats[thermostat_id].current_heating_cooling_state = 0
    end
  end

  current_heating_cooling_state_values = {
    0 => 'off',
    1 => 'heating',
    2 => 'cooling',
  }
  rh_thermostats[thermostat_id].current_heating_cooling_state.after_update do |current_heating_cooling_state|
    state = current_heating_cooling_state_values[current_heating_cooling_state]
    puts "\t#{thermostat_name}: #{state}"
  end

  rh_thermostats[thermostat_id].heating_threshold_temperature.after_update do |heating_threshold_temperature|
    # maximum_value: 25
    # minimum_value: 0
    # step_value: 0.1
    puts "\t#{thermostat_name}: heating threshold set to #{heating_threshold_temperature.to_fahrenheit}f"
  end

  rh_thermostats[thermostat_id].cooling_threshold_temperature.after_update do |cooling_threshold_temperature|
    # maximum_value: 35
    # minimum_value: 10
    # step_value: 0.1
    puts "\t#{thermostat_name}: cooling threashold set to  #{cooling_threshold_temperature.to_fahrenheit}f"
  end
end

Thread.new do
  loop do
    puts "Fetching state from API......."
    thermostat_state = get_lastest_data(thermostat_ids)

    thermostats.each do |thermostat_id, thermostat|
      thermostat_name = thermostats[thermostat_id]['name']
      thermostat_state = thermostat_states[thermostat_id]

      # puts thermostat_state.inspect

      puts "Updating homekit for #{thermostat_name} --> #{thermostat_state['best_known_current_state_thermostat_data']['temperature']}f"
      rh_thermostats[thermostat_id].current_temperature = thermostat_state['best_known_current_state_thermostat_data']['temperature'].to_f.to_celsius.clamp(0,100)
    end

    sleep 30
  end
end

RubyHome.run