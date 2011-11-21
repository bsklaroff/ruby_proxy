require 'socket'
require 'net/http'
require 'tempfile'
require 'thread'

def handle_request(session)
  req = Array.new
  while (line = session.gets) != "\r\n"
    req << line
  end
#  puts req[0]
  initial = req[0].split(' ')
  case initial[0]
  when 'GET'
    get_request(session, initial[1])
  when 'POST'
    puts req
    post_request(session, req)
  else
    puts initial[0] + " request not supported"
  end
end

def get_request(session, url, limit = 10)
  if $cache.has_key?(url)
    $cache_mutex[url].synchronize do
      $cache[url].rewind
      session.puts $cache[url].read
    end
    return
  end
  uri = URI(url)
  puts uri.request_uri
  res = Net::HTTP.new(uri.host, uri.port).start do |http|
    http.get uri.request_uri
  end

  case res
  when Net::HTTPRedirection then
    location = res['location']
    puts "redirected to #{location}"
    if limit == 0
      puts "redirect limit reached"
      session.puts res.body
    else
      get_request(session, location, limit - 1)
    end
  when Net::HTTPSuccess then
    if res.body and res.body.bytesize <= $max_page_size
      while $max_cache_size - $cache_size < res.body.bytesize
        puts "ouch"
      end
      cache_file = Tempfile.new('rbcache')
      $cache[url] = cache_file
      $cache_mutex[url] = Mutex.new
      $cache_score_data[url] = [0, res.body.bytesize]
      puts cache_score($cache_score_data[url])
      $cache_size += res.body.bytesize
      cache_file.puts(res.body)
      cache_file.flush
    end
    session.puts res.body
  else
    session.puts res.body
  end
end

def post_request(url)
  uri = URI(url)
  puts uri
  Net::HTTP.new(uri.host, uri.port).start do |http|
    request = Net::HTTP::Get.new uri.request_uri
    res = http.request request
    puts res.is_a?(Net::HTTPSuccess)
    session.puts res.body
  end
end

def cache_score(data)
  data[0] += 1
  if data[0] > 10
    data[0] = 10
  end
  freq = data[0]
  byte_size = data[1]
  byte_size /= 1048576.0
  time = Time.now.to_i
  time_diff = Float(time - $start_time) / $start_time
  freq /= 10.0
  return freq * time_diff / byte_size
end

$max_page_size = 1048576
$max_cache_size = 100 * $max_page_size
$cache = Hash.new
$cache_mutex = Hash.new
$cache_score_data = Hash.new
#$cache_heap = PriorityQueue.new
$cache_size = 0
$start_time = Time.now.to_i
server = TCPServer.new(2347)
puts "Starting server..."
while true
  Thread.start(server.accept) do |session|
    puts session
    handle_request(session)
    session.close
  end
end
