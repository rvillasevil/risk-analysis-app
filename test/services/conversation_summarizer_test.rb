require 'test_helper'

class ConversationSummarizerTest < ActiveSupport::TestCase
  test 'summarizes confirmed fields using OpenAI' do
    ra = risk_assistants(:one)
    ra.update!(name: 'RA1') if ra.name.blank?
    ra.messages.create!(sender: 'assistant', role: 'assistant', key: 'name', value: 'ACME', content: 'c')
    ra.messages.create!(sender: 'assistant', role: 'assistant', key: 'address', value: '123 St', content: 'c')

    sent = {}

    HTTP.stub :headers, ->(*args) {
      Class.new do
        define_method(:post) do |url, json:|
          sent[:url] = url
          sent[:body] = json
          Struct.new(:parse).new({ 'choices' => [{ 'message' => { 'content' => 'resumen' } }] })
        end
      end.new
    } do
      RiskFieldSet.stub :label_for, ->(k) { k.to_s.capitalize } do
        result = ConversationSummarizer.summarize(ra)
        assert_equal 'resumen', result
      end
    end

    assert_equal ConversationSummarizer::OPENAI_URL, sent[:url]
    assert_equal ConversationSummarizer::MODEL, sent[:body][:model]
    assert_match 'Name: ACME', sent[:body][:messages][0][:content]
    assert_match 'Address: 123 St', sent[:body][:messages][0][:content]
  end
end