require 'test_helper'

class TextExtractorTest < ActiveSupport::TestCase
  test 'removes null bytes from output' do
    file = OpenStruct.new(read: "abc\x00def", content_type: 'text/plain')
    result = TextExtractor.call(file)
    assert_equal 'abcdef', result
  end
end