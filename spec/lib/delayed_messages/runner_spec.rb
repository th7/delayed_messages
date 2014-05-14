require 'spec_helper'
require 'delayed_messages/runner'
require 'json'


describe DelayedMessages::Runner do
  let(:opts) { { queue: {}, binding: {} } }
  let(:runner) { DelayedMessages::Runner.new(opts) }

  let(:delayed_msg) { { 'delayed_msg' => { 'a' => 'message' }, 'delayed_key' => 'a key' } }
  let(:delay_until) { Time.now.to_i }
  let(:msg) { { msg: delayed_msg, delay_until: delay_until, tag: 'a tag' } }

  before do
    DelayedMessages::Runner.any_instance.stub(:bunny_init)
    runner.instance_variable_set(:@exch, double)
    runner.instance_variable_set(:@chan, double)
  end

  context 'a message exists on the to_message list' do
    before do
      runner.to_schedule << msg
    end

    context 'the message is due' do
      it 'publishes and acknowledges the message' do
        expect(runner.exch).to receive(:publish).with(delayed_msg['delayed_msg'].to_json, routing_key: delayed_msg['delayed_key']).ordered
        expect(runner.chan).to receive(:ack).with('a tag').ordered
        runner.send(:analyze, delay_until)
      end
    end

    context 'the message is not due' do
      it 'does not publish the message' do
        expect(runner).not_to receive(:publish)
        runner.send(:analyze, delay_until - 1)
      end

      it 'places the message in the schedule under the appropriate key' do
        runner.stub(:publish)
        expect {
          runner.send(:analyze, delay_until - 1)
        }.to change {
          runner.schedule[delay_until]
        }.from(nil).to([ msg ])
      end
    end

    context 'the message is overdue' do
      it 'publishes and achknowledges the message' do
        expect(runner.exch).to receive(:publish).with(delayed_msg['delayed_msg'].to_json, routing_key: delayed_msg['delayed_key']).ordered
        expect(runner.chan).to receive(:ack).with('a tag').ordered
        runner.send(:analyze, delay_until + 1)
      end
    end
  end

  context 'a message is in the schedule' do
    before do
      runner.schedule[delay_until] = []
      runner.schedule[delay_until] << msg
    end

    context 'at the appropriate time' do
      it 'publishes the message' do
        expect(runner.exch).to receive(:publish).with(delayed_msg['delayed_msg'].to_json, routing_key: delayed_msg['delayed_key']).ordered
        expect(runner.chan).to receive(:ack).with('a tag').ordered
        runner.send(:analyze, delay_until)
      end
    end

    context 'before the appropriate time' do
      it 'does not publish the message' do
        expect(runner).not_to receive(:publish)
        runner.send(:analyze, delay_until - 1)
      end
    end

  end
end
