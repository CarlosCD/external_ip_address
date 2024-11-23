#!/usr/bin/env -S ruby

# Get the external IP address (external to the WIFI router), and email it
#   Pass -v to get some feedback when running it from the Terminal:
#     ./send_external_ip_address.rb -v

class SendExternalIpAddress
  class << self
    MEMORY_FILE = 'last_ip_address.txt'
    SENDGRID_KEY = ENV['SENDGRID_KEY']
    EMAIL_RECIPIENT = ENV['EMAIL_RECIPIENT']

    def do_it(arguments)
      @verbose = !arguments.collect(&:downcase).delete('-v').nil?
      old_address, num_emails, date_last_sent = read_last_address(MEMORY_FILE)
      today = Time.now.utc.strftime('%Y/%m/%d')
      num_emails ||= 0
      new_address, message = get_ip_address(number_urls: 3)
      message ||= "IP address is '#{new_address}'"
      if (new_address != old_address) || (today != date_last_sent) || (num_emails < 10)
        if @verbose
          puts 'Email sending conditions'
          # For testing this, to set the file 1 day before (24h), run:
          #   touch -A -240000 last_ip_address.txt
          if today != date_last_sent
            puts "Last sent (UTC): #{date_last_sent}"
            puts "Today     (UTC): #{today}"
          end
        end
        send_by_email(message: message, pass: SENDGRID_KEY)
        # It is just a new day, we won't change num_emails (only sending it once):
        if (new_address != old_address) || (num_emails < 10)
          puts("IP Addresses: '#{old_address || 'None'}' -> '#{new_address || 'None'}'") if @verbose && (new_address != old_address)
          num_emails = (new_address != old_address) ? 1 : (num_emails + 1)
          puts("Email message number #{num_emails} for today, #{today} (UTC)") if @verbose
        end
        save_last_address(MEMORY_FILE, new_address, num_emails)
      elsif @verbose
        puts 'No action taken, no changes found.'
      end
    end

    private

    require 'net/http'

    def load_dependencies
      %w(mail).each do |gem_name|
        begin
          Gem::Specification.find_by_name(gem_name)
        rescue Gem::MissingSpecError
          puts "Installing the '#{gem_name}' Ruby gem..."
          system "gem install #{gem_name}"
        end
        require gem_name
      end
    end

    # Notes on these URLs:
    #   https://api.ipify.org         adds a "\n" at the end of the IP address
    #   http://whatismyip.akamai.com  fast and reliable, but does not support HTTPS
    IP_ECHO_SERVICES = %w( https://api.ipify.org/
                           https://icanhazip.com/
                           https://ident.me/
                           https://ipecho.net/plain
                           http://whatismyip.akamai.com )

    def get_ip_address(url: nil, number_urls: nil)
      number = url ? 1 : (number_urls || 3)
      number = IP_ECHO_SERVICES.size if number > IP_ECHO_SERVICES.size
      services = url ? [ url ] : IP_ECHO_SERVICES.sample(number)
      hash = {}
      services.each{|url| hash[url] = get_ip_address_from_url(url) }
      ip_address = hash.values.select{|v| !v.nil? && !v.empty?}
      if (ip_address.size < number || ip_address.uniq.size > 1)
        message = "No consensus. IP addresses: #{hash.map{|u,b| "#{u} -> #{b || 'None'}"}.join(', ')}"
        puts("Special case: #{message}") if @verbose
      end
      [ ip_address.first, message ]
    end

    def get_ip_address_from_url(url)
      uri = URI(url)
      begin
        response = Net::HTTP.get_response(uri)
        body = response.is_a?(Net::HTTPSuccess) ? response.body : nil
      rescue Errno::ECONNREFUSED => e
        puts("Connection refused. URL: '#{url}': #{e}") if @verbose
      end
      if body.is_a?(String)
        body = body.chomp
      else
        body = nil
      end
      body
    end

    def send_by_email(message: '', pass: nil)
      load_dependencies
      Mail.defaults do
        delivery_method :smtp,
          address: 'smtp.sendgrid.net', port: 587, #465, #587, #25, # 465,
          # domain: 'gmail.com',
          user_name: 'apikey',
          password: pass,
          enable_ssl: true,
          authentication: :plain
      end
      puts('Sending email...') if @verbose
      Mail.deliver do
             to EMAIL_RECIPIENT
           from EMAIL_RECIPIENT
        subject message
           body message
      end
      # it seems that it never arrives to gmail, because a security domain check...
      puts('...email sent!') if @verbose
    end

    # Looks into the given file, & reads it ifm present.
    #   It's content should be two comma-separated strings:
    #     "#{ip Address},#{Num emails sent}"
    #   Returns 3 values:
    #     - IP Address                                          (String)
    #     - Number of emails sent since the IP address changed  (Integer)
    #     - File's last modification, or today if no file       (String with the format 'YYYY/MM/DD', date as UTC)
    def read_last_address(filename)
      return ['', 0, Time.now.utc.strftime('%Y/%m/%d') ] unless File.exist?(filename)
      file_date = File.mtime(filename).utc.strftime('%Y/%m/%d')
      file_content = File.read(filename) rescue ',0'
      ip_address, num_emails = file_content.split(',')
      ip_address = ip_address.to_s
      num_emails = num_emails.to_i
      [ ip_address, num_emails, file_date ]
    end

    def save_last_address(filename, ip_address, num_emails)
      File.open(filename, 'w') {|f| f.write "#{ip_address},#{num_emails}" }
    end
  end
end

SendExternalIpAddress.do_it(ARGV)
