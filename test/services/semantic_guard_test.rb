class SemanticGuardTest < ActiveSupport::TestCase
  class DummyRelation
    def where(*); self; end
    def not(*); self; end
    def order(*); self; end
    def last; OpenStruct.new; end
  end

  test 'uses valid temperature when calling OpenAI' do
    sent = {}
    risk_assistant = OpenStruct.new(messages: DummyRelation.new)

    HTTP.stub :headers, ->(*args) {
      Class.new do
        define_method(:post) do |url, json:|
          sent[:url] = url
          sent[:body] = json
          Struct.new(:parse).new({ 'choices' => [{ 'message' => { 'content' => 'OK' } }] })
        end
      end.new
    } do
      SemanticGuard.validate(question: 'q', answer: 'a', context: 'c', risk_assistant: risk_assistant, thread_id: 1)
    end

    assert_equal SemanticGuard::ENDPOINT, sent[:url]
    assert_equal 0.3, sent[:body][:temperature]
  end
end