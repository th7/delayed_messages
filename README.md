# Delayed Messages

Read messages from RabbitMQ and republish at the specified time.

## Installation
Add this line to your application's Gemfile:

    gem 'delayed_messages'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install delayed_messages

## Usage
From your project's (or an arbitrary) directory:

    $ delayed-messages -init

Rename the example config and tweak as needed.

Then run in your console with default config:

    $ delayed-messages

Or start a daemon that uses your config file.

    $ delayed_messages -d -c 'config/delayed_messages.yml' -e development

I'd recommend using Monit (or something similar) to manage and monitor daemons.

Another RabbitMQ client can now publish messages to your configured exchange using your configured routing key. Messages should be a JSON string and include the following:

```
{
    "delayed_message": { "this will": "be republished"}, # note that the republishable message must itself be valid JSON
    "delay_until": "2014-05-14T10:53:03-05:00", # will be evaluated by Ruby's DateTime.parse
    "delayed_key": "republish.with.this.routing.key"
}
```
[DateTime.parse](http://www.ruby-doc.org/stdlib-2.1.1/libdoc/date/rdoc/DateTime.html#method-c-parse) can accept multiple input formats

The delayed messages service will pick messages up from the configured exchange and routing key, and republish only the "delayed_message" portion using the "delayed_key" routing key at the specified time.

## Limitations

If there are more long-delay messages than your prefetch limit, short-delay messages will not reach the service until longer-delayed messages republish first. Messages will not be dropped, but could be delayed longer than intended.

The service's ability to republish messages is limited to the speed of your network and RabbitMQ instance. It is possible for the service to fall behind, for example, if thousands of messages are due to republish at once. In most cases this shouldn't be a problem, but if you're intending to have 10k messages go out at once be aware the service may temporarily fall a few seconds behind.

#### Very basic benchmark on Mac OSX and MRI 2.1.1

With no messages in RabbitMQ the process starts at about 15MB.

With >50k messages in RabbitMQ set to republish at the same time:

With prefetch set to 10k the process waited at about 50MB and spiked to 200MB while mass republishing messages.

Reducing the prefetch to 1k changed memory usage to 20MB while waiting up to 50MB during a mass republish.

On my 2013 1.3GHz Macbook Air with RabbitMQ on localhost, the service was able to mass republish about 1.5k messages per second.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
