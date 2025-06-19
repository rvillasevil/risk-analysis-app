require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "user@example.com", password: "password")
    @risk_assistant = @user.risk_assistants.create!(name: "ACME")
    sign_in @user
  end

  test "semantic guard logs warning and continues flow" do
    warning_text = "Test contradiction"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{content: "hello", file_id: nil}]
    runner_mock.expect :run_and_wait, "OK"

    SemanticGuard.stub :validate, warning_text do
      AssistantRunner.stub :new, runner_mock do
        assert_difference -> { Message.count }, 2 do
          post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "hello" } }
        end
        assert_redirected_to risk_assistant_path(@risk_assistant)
      end
    end

    runner_mock.verify
    warning = Message.order(:created_at).last
    assert_equal "assistant", warning.sender
    assert_match warning_text, warning.content
  end
end