require 'bunny'
require 'json'
require 'logger'

module DelayedMessages
  class Runner
    attr_reader :logger, :pid_file_path, :conn, :chan,
      :exch, :queue_name, :routing_key, :rabbitmq_url,
      :to_schedule, :schedule, :to_schedule_mutex, :schedule_mutex

    DEFAULTS = {
      rabbitmq_url: 'amqp://guest:guest@localhost:5672',
      exchange: {
        name: 'delayed_messages',
        durable: false
        },
      queue: {
        name: 'delayed_messages'
        },
      channel: {
        prefetch: 1000
        },
      binding: { routing_key: 'delayed_messages' }
    }

    def initialize(opts={})
      opts = DEFAULTS.merge(opts)
      @to_schedule = []
      @to_schedule_mutex = Mutex.new

      @schedule = {}
      @schedule_mutex = Mutex.new

      Process.daemon(true) if opts.has_key?(:daemonize)

      @pid_file_path = opts[:pid_file_path]
      if pid_file_path
        File.open(pid_file_path, 'w') { |f| f.write(Process.pid) }
      end

      @queue_name   = opts[:queue][:name]
      @routing_key  = opts[:binding][:routing_key]

      @logger = init_logger(opts[:log_path], opts[:log_level])
      bunny_init(opts)
    end

    def start
      now = Time.now.to_i
      logger.info { "Starting..." }
      logger.info { "pid_file_path: #{pid_file_path.inspect}" }
      logger.info { "rabbitmq_url: #{rabbitmq_url.inspect}, queue_name: #{queue_name.inspect}, routing_key: #{routing_key.inspect}" }

      start_fetching

      loop do
        analyze(now)
        now += 1
        to_sleep = now - Time.now.to_i
        sleep to_sleep if to_sleep > 0
      end

    rescue SystemExit => e
      raise e

    rescue SignalException => e
      logger.info(e.inspect)
      File.delete(pid_file_path) if pid_file_path
      raise e

    rescue Exception => e
      ([e.inspect] + e.backtrace).each { |line| logger.fatal(line) }
      raise e
    end

    private

    def bunny_init(opts)
      @rabbitmq_url = opts[:rabbitmq_url]
      @conn = Bunny.new(rabbitmq_url)
      @conn.start
      @chan = conn.create_channel
      chan.prefetch(opts[:channel][:prefetch])
      @exch = chan.topic(opts[:exchange][:name], durable: opts[:exchange][:durable])
    end

    def analyze(time_int)
      schedule_new(time_int)

      to_pub = nil
      lock_schedule do
        to_pub = schedule.delete(time_int)
      end
      to_pub.each { |msg| publish(msg) } if to_pub
    end

    def start_fetching
      @chan.queue(queue_name, durable: false).bind(@exch, routing_key: routing_key).subscribe(ack: true) do |delivery_info, _, msg|
        msg = JSON.parse(msg)
        lock_to_schedule do
          to_schedule << { msg: msg, tag: delivery_info.delivery_tag, delay_until: DateTime.parse(msg['delay_until']).strftime('%s').to_i }
        end
      end
    end

    def lock_to_schedule
      to_schedule_mutex.synchronize do
        yield
      end
    end

    def lock_schedule
      schedule_mutex.synchronize do
        yield
      end
    end

    def schedule_new(now)
      msgs = nil

      lock_to_schedule do
        msgs = to_schedule.dup
        to_schedule.clear
      end

      msgs.each do |msg|
        pub_at = msg[:delay_until]
        if pub_at <= now
          publish(msg)
        else
          lock_schedule do
            schedule[pub_at] ||= []
            schedule[pub_at] << msg
          end
        end
      end
    end

    def publish(msg)
      @exch.publish(msg[:msg]['delayed_message'].to_json, routing_key: msg[:msg]['delayed_key'])
      @chan.ack(msg[:tag])
    end

    def init_logger(log_path, log_level)
      logger = if log_path
        Logger.new(log_path)
      else
        Logger.new(STDOUT)
      end
      logger.level = log_level.to_i || 1
      logger
    end
  end
end
