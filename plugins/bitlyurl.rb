require "bitly"
require "yaml"

class UrlObject
  attr_accessor :user_hash
  attr_accessor :url
  attr_accessor :tags

  def initialize(hash, url, tags=[])
    @user_hash = hash
    @url = url
    @tags = tags
  end
end

class BitlyUrl < Plugin::PluginBase

  URL_RE = /(https?:\/\/\S*)/
  BITLY_RE = /http:\/\/bit\.ly\//

  KNOWN_TAGS = ["funny", "nsfw", "nosave", "video"]

  def initialize
    name "Bit.ly Urls"
    author "Syn"
    version "0.5"

    @bitly = nil
    @file = nil
    @verbose = nil
    @ignore_channels = []
  end

  def start(bot, config)
    login = config.get("login")
    api_key = config.get("api_key")

    bot.error("Bitly: No bitly login in config!") if login.nil?
    bot.error("Bitly: No bitly api key in config!") if api_key.nil?

    return if login.nil? or api_key.nil?

    @versbose = config.get("verbose", false)

    file = config.get("file", "bitlyurls.dat")
    @file = bot.get_storage_path(file) if file

    @bitly = Bitly.new(login, api_key)

    @min_length = config.get("minimal_length", 25).to_i()

    @ignore_channels = config.get("ignore", []).collect do |chan|
      chan.gsub(/^[#%!+]/, "")
    end

    bot.add_handler(self, "pubmsg") do |event|
      self.do_bitly(bot, event)
      true
    end
  end

  def do_bitly(bot, event)
    message = event.message()

    channel = event.channel.gsub(/^[#%!+]/, "")
    return true if @ignore_channels.include?(channel)

    bot.debug("URL Shorten: Looking for url in #{message}")

    match = message.match(URL_RE)

    if match
      url = match.captures.first()

      # Find any tags. 
      tags = KNOWN_TAGS.inject([]) do |tags, tag|
        message.match(/\:#{tag}/) ? tags.push(tag) : tags
      end

      # Ignore if we got a "nosave" tag.
      return if tags.include?("nosave")
 
      # Ignore bit.ly urls.
      return if url.match(BITLY_RE)

      bot.debug("URL Shorten: Found an url: #{url}")

      # Only bit.ly the url if it's too long.
      if @bitly and url.length >= @min_length
        begin
          data = @bitly.shorten(url)
        rescue BitlyError => err
          bot.error("URL Shorten: Problem getting bit.ly short url!", err)
        end
      end

      short_url = data.short_url()
      hash = data.user_hash()

      msg = @verbose ? "%s\nFor: %s" % [short_url, url] : short_url

      bot.reply(event, msg)

      begin
        urlobj = UrlObject.new(hash, url, tags)
        self.save_url(urlobj)
      rescue Exception => err
        bot.error("URL Shorten: Problem saving url!", err)
      end
      
    end

    return
  end

  def load
    urls = {}

    return urls if not @file

    begin
      File.open(@file) do |fp|
        urls = YAML.load(fp.read())
      end
    rescue Exception
      raise
    end

    return urls
  end

  def save_url(urlobj)
    if urlobj.is_a?(UrlObject)
      urls = self.load()

      urls[urlobj.user_hash] = urlobj

      self.save(urls)
    end
  end

  def save(urls={})
    if @file
      begin
        File.open(@file, "w") do |fp|
          fp.write(YAML.dump(urls))
        end
      rescue
        raise
      end
    end
  end

end

register_plugin(BitlyUrl)
