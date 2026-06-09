require 'dotenv/load'
require 'net/http'
require 'uri'
require 'json'
require 'base64'

# Read parameters from environment variables
api_key =     ENV['SESAME_API_KEY']
sesame_uuid = ENV['SESAME_UUID']

airtable_pat      = ENV['AIRTABLE_PAT']
airtable_base_id  = ENV['AIRTABLE_BASE_ID']
airtable_table_id = ENV['AIRTABLE_TABLE_ID']

if [api_key, sesame_uuid, airtable_pat, airtable_base_id, airtable_table_id].any?(&:nil?)
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

#
# Check the last log in Airtable
#
puts "Fetching the latest timestamp from Airtable..."

# Airtable API endpoint
airtable_get_uri = URI.parse("https://api.airtable.com/v0/#{airtable_base_id}/#{airtable_table_id}")

# Query parameter to get the latest record
airtable_get_uri.query = URI.encode_www_form({
  "sort[0][field]" => "raw timestamp",
  "sort[0][direction]" => "desc",
  "maxRecords" => 1
})

airtable_get_req = Net::HTTP::Get.new(airtable_get_uri)
airtable_get_req['Authorization'] = "Bearer #{airtable_pat}"

latest_timestamp = 0

begin
  airtable_get_res = Net::HTTP.start(airtable_get_uri.hostname, airtable_get_uri.port, use_ssl: true) do |http|
    http.request(airtable_get_req)
  end

  if airtable_get_res.code.start_with?('2')
    records = JSON.parse(airtable_get_res.body)["records"]
    if records && !records.empty?
      latest_timestamp = records.first["fields"]["raw timestamp"].to_i
      puts "Latest timestamp in Airtable: #{latest_timestamp}"
    else
      puts "Airtable is empty. Will fetch all available history."
    end
  else
    warn "Failed to fetch from Airtable: Status #{airtable_get_res.code}"
    exit 1
  end
rescue => e
  warn "Error connecting to Airtable: #{e.message}"
  exit 1
end

#
# Fetch Sesame history data
#
new_sesame_records = []
page = 0
max_safety_pages = 10 # 10 pages x 50 records/page = 500 records max, to prevent infinite loops in case of API issues

puts "Fetching new records from Sesame..."

loop do
  puts "Fetching Sesame page #{page}..."
  sesame_uri = URI.parse("https://app.candyhouse.co/api/sesame2/#{sesame_uuid}/history?page=#{page}&lg=50")
  sesame_request = Net::HTTP::Get.new(sesame_uri)
  sesame_request['x-api-key'] = api_key

  sesame_response = Net::HTTP.start(sesame_uri.hostname, sesame_uri.port, use_ssl: true) do |http|
    http.request(sesame_request)
  end

  if sesame_response.code != '200'
    warn "Sesame API Error at page #{page}: Status Code #{sesame_response.code}"
    break
  end

  page_data = JSON.parse(sesame_response.body)
  break if page_data.nil? || page_data.empty?

  reached_old_record = false

  page_data.each do |record|
    record_ts = record['timeStamp'].to_i
    
    # Collect only records newer than the latest timestamp in Airtable
    if record_ts > latest_timestamp
      new_sesame_records << record
    else
      # Reached a record that already exists in Airtable (or older), stop fetching
      reached_old_record = true
      break
    end
  end

  # Reached an old record or the maximum safety page, exit the loop
  break if reached_old_record
  
  # Safety lock
  if page >= max_safety_pages
    warn "Reached maximum safety page limit (#{max_safety_pages}). Stopping fetch."
    exit 1
  end

  page += 1
  sleep 1 # Reduce API load
end

puts "Total new records found: #{new_sesame_records.size}"

#
# Upload new records to Airtable (if any)
#
if new_sesame_records.empty?
  puts "No new records to upload. Airtable is already up-to-date."
  exit 0
end

# Convert to Airtable format
airtable_records = new_sesame_records.map do |record|
  {
    "fields" => {
      "raw timestamp" => record['timeStamp'],
      "raw type"      => record['type'],
      "history tag"   => decode_tag(record['historyTag'])
    }
  }
end

airtable_post_uri = URI.parse("https://api.airtable.com/v0/#{airtable_base_id}/#{airtable_table_id}")

airtable_records.each_slice(10) do |chunk|
  airtable_request = Net::HTTP::Patch.new(airtable_post_uri)
  airtable_request['Authorization'] = "Bearer #{airtable_pat}"
  airtable_request['Content-Type']  = 'application/json'
  
  payload = {
    "performUpsert" => {
      "fieldsToMergeOn" => ["raw timestamp"]
    },
    "records" => chunk
  }
  airtable_request.body = payload.to_json

  airtable_response = Net::HTTP.start(airtable_post_uri.hostname, airtable_post_uri.port, use_ssl: true) do |http|
    http.request(airtable_request)
  end

  if airtable_response.code.start_with?('2')
    puts "Successfully uploaded #{chunk.size} new records to Airtable."
  else
    warn "Airtable API Error during upload: Status Code #{airtable_response.code}"
    warn airtable_response.body
    exit 1
  end
end

puts "All processes completed successfully!"
