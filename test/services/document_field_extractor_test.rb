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
    assert_equal DocumentFieldExtractor::MAX_TOKENS, sent[:body][:max_tokens]
  end

  test 'parses multiline response and sets max_tokens' do
    sent = {}

    response = <<~TEXT
      ##name## &&ACME Corp&&
      ##address## &&123 Fake St&&
    TEXT

    HTTP.stub :headers, ->(*args) {
      Class.new do
        define_method(:post) do |url, json:|
          sent[:url] = url
          sent[:body] = json
          Struct.new(:parse).new({ 'choices' => [{ 'message' => { 'content' => response } }] })
        end
      end.new
    } do
      result = DocumentFieldExtractor.call('dummy text')
      assert_equal({ 'name' => 'ACME Corp', 'address' => '123 Fake St' }, result)
    end

    assert_equal DocumentFieldExtractor::OPENAI_URL, sent[:url]
    assert_equal 512, sent[:body][:max_tokens]
  end  
end