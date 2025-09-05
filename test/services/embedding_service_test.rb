require 'test_helper'

class EmbeddingServiceTest < ActiveSupport::TestCase
  test 'uses embedding model and returns vector' do
    sent = {}
    HTTP.stub :headers, ->(*args) {
      Class.new do
        define_method(:post) do |url, json:|
          sent[:url] = url
          sent[:body] = json
          Struct.new(:body).new({ data: [{ embedding: [0.1, 0.2] }] }.to_json)
        end
      end.new
    } do
      vector = EmbeddingService.embed('hola')
      assert_equal EmbeddingService::EMBEDDING_URL, sent[:url]
      assert_equal EmbeddingService::MODEL, sent[:body][:model]
      assert_equal [0.1, 0.2], vector
    end
  end
end