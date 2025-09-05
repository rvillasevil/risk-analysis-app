require 'test_helper'
require 'ostruct'

class DocumentFieldExtractorTest < ActiveSupport::TestCase
  test 'uses valid temperature when calling OpenAI' do
    sent = []

    fields = [
      { id: 'name', label: 'Name' }
    ]

    RiskFieldSet.stub :flat_fields, fields do
      RiskFieldSet.stub :by_id, fields.index_by { |f| f[:id].to_sym } do
        HTTP.stub :headers, ->(*args) {
          Class.new do
            define_method(:post) do |url, json:|
              sent << { url: url, body: json }
              content = sent.length == 1 ? '##name## &&ACME Corp&&' : '##name## &&ok&&'
              Struct.new(:parse).new({ 'choices' => [{ 'message' => { 'content' => content } }] })
            end
          end.new
        } do
          DocumentFieldExtractor.call('dummy text')
        end
      end
    end

    assert_equal DocumentFieldExtractor::OPENAI_URL, sent.first[:url]
    assert_equal 0.7, sent.first[:body][:temperature]
    assert_equal DocumentFieldExtractor::MAX_TOKENS, sent.first[:body][:max_tokens]
    assert_equal 2, sent.size
  end

  test 'parses multiline response, sets max_tokens and returns warnings' do
    sent = []

    fields = [
      { id: 'name', label: 'Name' },
      { id: 'address', label: 'Address' }
    ]

    extraction = <<~TEXT
      ##name## &&ACME Corp&&
      ##address## &&123 Fake St&&
    TEXT

    verification = <<~TEXT
      ##name## &&ok&&
      ##address## &&Formato inválido&&
    TEXT

    RiskFieldSet.stub :flat_fields, fields do
      RiskFieldSet.stub :by_id, fields.index_by { |f| f[:id].to_sym } do
        HTTP.stub :headers, ->(*args) {
          Class.new do
            define_method(:post) do |url, json:|
              sent << { url: url, body: json }
              content = sent.length == 1 ? extraction : verification
              Struct.new(:parse).new({ 'choices' => [{ 'message' => { 'content' => content } }] })
            end
          end.new
        } do
          result = DocumentFieldExtractor.call('dummy text')
          expected = {
            values: { 'name' => 'ACME Corp', 'address' => '123 Fake St' },
            warnings: { 'address' => 'Formato inválido' }
          }
          assert_equal expected, result
        end
      end
    end

    assert_equal DocumentFieldExtractor::OPENAI_URL, sent.first[:url]
    assert_equal 512, sent.first[:body][:max_tokens]
  end
end