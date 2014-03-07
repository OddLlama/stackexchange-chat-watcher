# get your access token at this URL:
# https://stackexchange.com/oauth/dialog?client_id=2666&redirect_uri=http://keyboardfire.com/chatdump.html&scope=no_expiry

ACCESS_TOKEN = 'INSERT YOUR ACCESS TOKEN HERE!!!'
$root = 'http://stackexchange.com'
$chatroot = 'http://chat.stackexchange.com'
email = 'INSERT YOUR EMAIL HERE!!!'
#password = open('chatWatcherPassword.pwd').read
password = 'INSERT YOUR PASSWORD HERE!!!' # or use the file option above and remove this line
$room_number = 13215 # this bot is configured for http://chat.stackexchange.com/rooms/13215/
site = nil # set to a site name to dump activity from that site with the API (old, old version, not recommended)
$ERRCOUNT = 0

# you'll need these gems for this bot
require 'rubygems'
require 'mechanize'
require 'logger'
require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'cgi'
require 'net/http'
puts 'requires finished'

loop{begin

$agent = Mechanize.new
$agent.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
#$agent.log = Logger.new STDOUT

login_form = $agent.get('https://openid.stackexchange.com/account/login').forms.first
login_form.email = email
login_form.password = password
$agent.submit login_form, login_form.buttons.first
puts 'logged in with SE openid'

meta_login_form = $agent.get($root + '/users/login').forms.last
meta_login_form.openid_identifier = 'https://openid.stackexchange.com/'
$agent.submit meta_login_form, meta_login_form.buttons.last
puts 'logged in to root'

chat_login_form = $agent.get('http://stackexchange.com/users/chat-login').forms.last
$agent.submit chat_login_form, chat_login_form.buttons.last
puts 'logged in to chat'

$fkey = $agent.get($chatroot + '/chats/join/favorite').forms.last.fkey
puts 'found fkey'

def send_message text
  loop {
    begin
      resp = $agent.post("#{$chatroot}/chats/#{$room_number}/messages/new", [['text', text], ['fkey', $fkey]]).body
      success = JSON.parse(resp)['id'] != nil
      return if success
    rescue Mechanize::ResponseCodeError => e
      puts "Error: #{e.inspect}"
    end
    puts 'sleeping'
    sleep 3
  }
end

send_message $ERR ? "An unknown error occurred. Bot restarted." : "Bot initialized."

if site

  last_date = 0
  loop {
    uri = URI.parse "https://api.stackexchange.com/2.2/events?pagesize=100&since=#{last_date}&site=#{site}&filter=!9WgJfejF6&key=thqRkHjZhayoReI9ARAODA((&access_token=#{ACCESS_TOKEN}"
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    data = JSON.parse http.get(uri.request_uri).body
    events = data['items']

    data['items'].each do |event|
      last_date = [last_date, event['creation_date'].to_i + 1].max
      #send_message "#{event['event_type'].sub('_', " #{event['event_id']} ").capitalize}: [`#{event['excerpt'].gsub(/\s/, ' ')}`](#{event['link']})"
      unless ['post_edited'].include? event['event_type']
        send_message event['link']
      end
    end

    puts "#{data['quota_remaining']}/#{data['quota_max']} quota remaining"
    sleep(40 + (data['backoff'] || 0).to_i) # add backoff time if any, just in case
  }

else

  # find the site IDs here: http://meta.stackoverflow.com/a/222845/180276
  actions = {
    '200-questions-newest' => ->data{
      title = data['body'].match(/class="question-hyperlink">([^<]*)</)[1] # HE COMES
      tags = data['tags']
      url = 'http://codegolf.stackexchange.com' + data['body'].match(/<a href="([^"]+)"/)[1] # CTHULHU

      triggers = []
      triggers.push 'missing winning criterion' unless tags.any? {|t| %w[algorithm atomic-code-golf busy-beaver code-bowling code-challenge code-golf code-shuffleboard code-trolling fastest-code king-of-the-hill metagolf popularity-contest puzzle restricted-source tips].include? t }
      triggers.push 'allcaps title' if title == title.upcase
      triggers.push 'tag in title' if title =~ /\[[\w\d -]+\]/
      triggers.push 'label in title' if title =~ /[\w\d -]+:/
      triggers.push 'repeated characters in title' if title =~ /(.)\1{4}/
      triggers.push 'new user' if [*1..11,*101..111].include?(data['body'].match(/<span class="reputation-score".*?([\d,]+)/)[1].gsub(',', '').to_i)

      send_message "New post!#{triggers.empty? ? '' : ' **Triggers detected: ' + triggers.join(', ') + '** @Doorknob'}"
      sleep 0.5
      send_message url
    },
    '202-questions-newest' => ->data{
      url = 'http://meta.codegolf.stackexchange.com' + data['body'].match(/<a href="([^"]+)"/)[1] # I FEEL SO EVIL

      send_message '**New meta post!** @Doorknob'
      sleep 0.5
      send_message url
    }
  }
  EM.run {
    ws = Faye::WebSocket::Client.new('ws://sockets.ny.stackexchange.com')

    ws.on :open do |event|
      actions.keys.each{|k| ws.send(k.dup) } # dup because hash keys are frozen
    end

    ws.on :message do |event|
      p event.data
      p Time.now.to_i
      msg = JSON.parse event.data
      if msg["action"] == 'hb'
        ws.send 'hb'
      else
        data = JSON.parse(msg['data']) rescue nil
        actions[msg["action"]][data] if data
      end
    end
  }

end

rescue Interrupt => e
  send_message 'Bot killed manually.'
  raise e

rescue => e
  $ERR = e
  $ERRCOUNT += 1
  p e
  p e.backtrace
  exit if $ERRCOUNT > 5
end}
