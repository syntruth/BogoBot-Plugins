require 'active_record'

class Quote < ActiveRecord::Base

  def Quote.setup(db_file, adapter='sqlite3')
    establish_connection(:database => db_file, :adapter => adapter)
  end

  def Quote.get_random(term="")
    if term.empty?
      sql = "select * from quotes order by random() limit 1"
    else
      sql = "select * from quotes where quote like '%#{term}%' " + 
      "order by random() limit 1"
    end
    return find_by_sql(sql).first()
  end

  def Quote.stats(sort_by_nick=true)
    sts = {}

    find(:all).each do |quote|
      nick = quote.nick
      sts[nick] = 0 if not sts.has_key?(nick)
      sts[nick] += 1
    end

    sorted = sts.sort do |q1, q2|
      sort_by_nick ? q1[0] <=> q2[0] : q2[1] <=> q1[1]
    end

    return sorted
  end

end

class QuoteDB < Plugin::PluginBase

  def initialize()
    author "Syn"
    name "Quote DB"
    version "1.0b"
    @DB = nil
  end

  def start(bot, config)
    @DB = bot.get_storage_path(config.get("filename", "quotes.db"))

    Quote.setup(@DB)

    term_opts = config.get("format", "").split(/,/).inject({}) do |opts, f|
      f = f.strip.downcase.to_sym()
      opts[f] = true
      opts
    end

    fg_color = config.get("fg_color", nil)
    bg_color = config.get("bg_color", nil)

    term_opts[:fg] = fg_color if fg_color
    term_opts[:bg] = bg_color if bg_color

    @term_format = bot.get_format_string(term_opts)

    qlog_help = "{cmd}qlog <quote> -- Logs a quote."
    bot.add_command(self, "qlog", false, false, qlog_help) do |bot, event|
      self.do_qlog(bot, event)
    end

    quote_help = "{cmd}quote <term>|id: <num> -- Looks for a quote, " + 
      "optionally with a search term or id number."
    bot.add_command(self, "quote", false, false, quote_help) do |bot, event|
      self.do_quote(bot, event)
    end

    qcount_help = "{cmd}qcount <term> -- Finds out many quotes contain " + 
      "the term given. The term can be a regex.\n" + 
      "For example: {cmd}qcount stick --or-- {cmd}qcount Bob|Tim"
    bot.add_command(self, "qcount", false, false, qcount_help) do |bot, event|
      self.do_qcount(bot, event)
    end

    qstats_help = "{cmd}qstats [sort_by_num] " + 
      "-- Shows the number of quotes per person. " +
      "If sort_by_num is a true value, the results are sorted " +
      "by the number of quotes, instead of people's nicks."
    bot.add_command(self, "qstats", false, false, qstats_help) do |bot, event|
      self.do_qstats(bot, event)
    end

    qcmd_help = "{cmd}qcmd :command <quote_id> [args] -- Owner only " +
      "command to modify quotes. Commands are :delete and :chgnick. The " +
      ":chgnick command takes a nick to assign the quote to."
    bot.add_command(self, "qcmd", true, false, qcmd_help) do |bot, event|
      self.do_qcmd(bot, event)
    end

  end

  def stop
    Quote.remove_connection()
  end

  # Plugin functions

  def do_qlog(bot, event)
    quote = bot.parse_message(event)
    nick = event.from()

    if quote.any?
      quote = Quote.new do |q|
        q.nick = nick
        q.quote = quote
        q.timestamp = Time.now()
      end

      if quote.save()
        num = Quote.count()

        msg = case num
        when 666
          "Totally evil, #{nick}! That was the 666th quote!"
        when 1000
          "That is the 1000th quote! Congrats. I hope it was worth it."
        when 1234
          "Totally sequential, #{nick}! That was the 1234th quote!"
        when 1337
          "You are elite, #{nick}! That was the 1337th quote!"
        else
          "Thank you, #{nick}. There are now #{num} quotes."
        end
        msg += " (id: #{Quote.find(:last).id})"
      else
        msg = "I was unable to save the quote!"
      end

    else
      msg = "I need a quote to log!"
    end

    bot.reply(event, msg)
  end

  def do_quote(bot, event)
    term = bot.parse_message(event)

    if term.downcase.start_with?("id:")
      quote = Quote.find_by_id(term.gsub("id:", "").to_i())
    else
      quote = Quote.get_random(term)
    end

    if quote
      quote_str = quote.quote()
      timestamp = quote.timestamp.strftime("%a %b %d %Y at %I:%M %p")

      quote_str.gsub!(/(\b#{term}\b)/i, @term_format % '\1') if term.any?

      msg = "#{quote_str}\nSubmitted by #{quote.nick} on #{timestamp} " +
        "(id: #{quote.id})"
    else
      if term.any?
        msg = "No quotes match term: #{term}"
      else
        msg = "There are no quotes!"
      end
    end

    bot.reply(event, msg)
  end

  def do_qcount(bot, event)
    term = bot.parse_message(event)

    return if term.length < 3

    if term.any?
      quotes = Quote.find(:all, 
        :conditions => "quote like '%#{term}%'",
        :order => :id
      )

      msg  = "There are #{quotes.count} quote(s) that match the term: #{term} "
      msg += "(#{quotes.collect{|q| q.id }.join(', ')})" if quotes.count <= 10

    else
      num = Quote.count()
      msg = "There are #{num} quotes."
    end

    bot.reply(event, msg)
  end

  def do_qstats(bot, event)
    sort_by_nick = bot.parse_message(event).strip.empty?

    stats = Quote.stats(sort_by_nick).collect do |stat| 
      "%s: %s" % [stat[0], stat[1]]
    end

    msg = "Quote Stats: " + stats.join(", ")
    msg += "\nThere are #{Quote.count} total quotes saved."

    bot.reply(event, msg)
  end

  def do_qcmd(bot, event)
    message = bot.parse_message(event).strip()
    return if message.empty?
  
    cmd_re = /^:([a-z]+)\s(\d+)\s*(.*?)$/

    match = message.match(cmd_re)

    if match
      args = match.captures()
      cmd = args[0].to_sym()
      id = args[1]
      extra = args[2]

      begin
        quote = Quote.find(id)
      rescue
        msg = "Unable to find quote for ID: #{id}"
        bot.reply(event, msg)
      end

      case cmd
      when :delete
        quote.destroy()
        msg = "Quote ID: #{id} deleted."
      when :chgnick
        quote.nick = extra
        quote.save()
        msg = "Quote ID: #{id} nick changed to #{extra}."
      else
        msg = "Unknown qcmd command: #{cmd}"
      end
    else
      msg = "Malformed qcmd string: #{message}"
    end

    bot.reply(event, msg)
  end

end

register_plugin(QuoteDB)

