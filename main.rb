require 'dotenv/load'
require 'net/http'
require 'uri'
require 'json'
require 'base64'

# Read parameters from environment variables
api_key =     ENV['SESAME_API_KEY']
sesame_uuid = ENV['SESAME_UUID']

airtable_pat        = ENV['AIRTABLE_PAT']
airtable_base_id    = ENV['AIRTABLE_BASE_ID']
airtable_table_name = ENV['AIRTABLE_TABLE_NAME']

if [api_key, sesame_uuid, airtable_pat, airtable_base_id, airtable_table_name].any?(&:nil?)
  warn "Error: Required environment variables are missing."
  exit 1
end

# Base64 decode helper
def decode_tag(tag)
  return "" if tag.nil? || tag.to_s.strip.empty?
  decoded = Base64.decode64(tag).force_encoding('UTF-8')
  decoded.valid_encoding? ? decoded.strip : tag
rescue
  tag
end

# Construct the endpoint URL (page=0 to get the latest 50 records)
sesame_uri = URI.parse("https://app.candyhouse.co/api/sesame2/#{sesame_uuid}/history?page=0&lg=50")
sesame_request = Net::HTTP::Get.new(sesame_uri)
sesame_request['x-api-key'] = api_key

begin
  sesame_response = Net::HTTP.start(sesame_uri.hostname, sesame_uri.port, use_ssl: true) do |http|
    http.request(sesame_request)
  end

  if sesame_response.code != '200'
    warn "Sesame API Error: Status Code #{sesame_response.code}"
    exit 1
  end

  history_data = JSON.parse(sesame_response.body)
  puts "Successfully fetched #{history_data.size} records from Sesame."

  # Convert Sesame history data to Airtable format
  airtable_records = history_data.map do |record|
    {
      "fields" => {
        "raw timestamp" => record['timeStamp'],
        "raw type"      => record['type'],
        "history tag"   => decode_tag(record['historyTag'])
      }
    }
  end

  # Upload to Airtable (in chunks of 10)
  escaped_table_name = URI.encode_www_form_component(airtable_table_name)
  airtable_uri = URI.parse("https://api.airtable.com/v0/#{airtable_base_id}/#{escaped_table_name}")

  airtable_records.each_slice(10) do |chunk|
    airtable_request = Net::HTTP::Post.new(airtable_uri)
    airtable_request['Authorization'] = "Bearer #{airtable_pat}"
    airtable_request['Content-Type']  = 'application/json'
    airtable_request.body             = { "records" => chunk }.to_json

    airtable_response = Net::HTTP.start(airtable_uri.hostname, airtable_uri.port, use_ssl: true) do |http|
      http.request(airtable_request)
    end

    if airtable_response.code.start_with?('2') # 2xx -> success
      puts "Successfully uploaded #{chunk.size} records to Airtable."
    else
      warn "Airtable API Error: Status Code #{airtable_response.code}"
      warn airtable_response.body
      exit 1
    end
  end

rescue => e
  warn "An error occurred: #{e.message}"
  exit 1
end
