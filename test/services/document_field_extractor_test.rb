require 'test_helper'
require 'ostruct'

class DocumentFieldExtractorTest < ActiveSupport::TestCase
  test 'uses valid temperature when calling OpenAI' do
    sent = {}

    HTTP.stub :headers, ->(*args) {
      Class.new do
        define_method(:post) do |url, json:|
          sent[:url] = url
          sent[:body] = json
          Struct.new(:parse).new({ 'choices' => [{ 'message' => { 'content' => '' } }] })
        end
      end.new
    } do
      DocumentFieldExtractor.call('dummy text')
    end

    assert_equal DocumentFieldExtractor::OPENAI_URL, sent[:url]
    assert_equal 0.7, sent[:body][:temperature]
  end
end