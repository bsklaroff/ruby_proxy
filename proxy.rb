require 'socket'
require 'net/http'

server = TCPServer.new(2347)
puts "hello"
while true
  Thread.start(server.accept) do |session|
    puts "log: got input from client"
    input = session.gets
    puts input
    uri = URI(input.split(' ')[1])
    puts uri
    Net::HTTP.new(uri.host, uri.port).start do |http|
      request = Net::HTTP::Get.new uri.request_uri
      res = http.request request
      puts res.is_a?(Net::HTTPSuccess)
      session.puts res.body
     end
    session.close
  end
end
