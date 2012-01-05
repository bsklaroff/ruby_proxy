require 'socket'
require 'net/http'
require 'tempfile'
require 'thread'
require 'rubygems'
require 'priority_queue'

# Reads the browser's request and parses the first line for the type of request
def handle_request(session)
  req = Array.new
  while (line = session.gets) != "\r\n"
    req << line
  end
  initial = req[0].split(' ')
  puts req[0]
  if initial[0] == 'GET'
    get_request(session, initial[1])
  else
    puts initial[0] + " request not supported"
  end
end

# Handles a GET request from the browser
def get_request(session, url, limit = 10)
  # Get the cached page
  $cache_mutex.synchronize do
    if $cache.has_key?(url)
      # Check if cache has expired
      if Time.now.to_i - $cache_data[url]['time'] < $default_cache_age
        $cache_heap[url] = cache_score($cache_data[url])
        $cache[url].rewind
        session.puts $cache[url].read
        return
      end
    end
  end

  uri = URI(url)
  res = Net::HTTP.get_response(uri)

  case res
  when Net::HTTPRedirection then
    # If we get redirected, try to find the right page
    location = res['location']
    puts "redirected to #{location}"
    if limit == 0
      puts "redirect limit reached"
      send_browser_response(session, res)
    else
      get_request(session, location, limit - 1)
    end
  when Net::HTTPSuccess then
    # On a successful GET, cache the page if it is small enough
    if res.body and res.body.bytesize <= $max_page_size
      $cache_mutex.synchronize do
        # Reduce size of cache if necessary
        while $max_cache_size - $cache_size < res.body.bytesize
            deleted = $cache_heap.delete_min
            url = deleted[0]
            $cache[url].close
            $cache.delete(url)
            $cache_size -= $cache_data[url]['byte_size']
            $cache_data.delete(url)
          end
        # Add new value to cache unless the response tells us not to
        cache_file = Tempfile.new('rbcache')
        $cache[url] = cache_file
        $cache_data[url] = {'time' => Time.now.to_i, 'freq' => 0, 'byte_size' => res.body.bytesize}
        $cache_heap[url] = cache_score($cache_data[url])
        $cache_size += res.body.bytesize
        cache_file.puts(res.body)
        cache_file.flush
      end
    end
    send_browser_response(session, res)
  else
    # Even if the request was unsuccessful we should probably send something
    send_browser_response(session, res)
  end
end

# This is where we actually send data to the browser
def send_browser_response(session, res)
  session.puts res.body
end

# This computes a score for our PriorityQueue so we can tell what to get rid of from our cache
def cache_score(data)
  data['freq'] += 1
  if data['freq'] > 10
    data['freq'] = 10
  end
  freq = data['freq']
  byte_size = data['byte_size']
  byte_size /= Float($max_page_size)
  time = data['time']
  time_diff = Float(time - $start_time) / $start_time
  freq /= 10.0
  return freq * time_diff / byte_size
end

$max_page_size = 1048576
cache_mult = ARGV[1] ? Integer(ARGV[1]) : 10
$max_cache_size = cache_mult * $max_page_size
$cache = Hash.new
$cache_mutex = Mutex.new
$cache_data = Hash.new
$cache_heap = PriorityQueue.new
$cache_size = 0
# How long we keep things in the cache without revalidation (in seconds)
$default_cache_age = 1000
$start_time = Time.now.to_i
# Default port is 2347
server = TCPServer.new(ARGV[0] ? Integer(ARGV[0]) : 2347)
puts "Starting server..."
while true
  Thread.start(server.accept) do |session|
    handle_request(session)
    session.close
  end
end
