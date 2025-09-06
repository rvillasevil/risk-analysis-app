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
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

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

  test "stores confirmation when validation passes" do
    assistant_text = "##test## es &&42&&"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{ content: "ok", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

    risk_fields = { test: { id: :test, label: "Test", validation: {} } }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :validate_answer, nil do
        AssistantRunner.stub :new, runner_mock do
          assert_difference -> { Message.where(key: "test").count }, 1 do
            post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "ok" } }
          end
          assert_redirected_to risk_assistant_path(@risk_assistant)
        end
      end
    end

    runner_mock.verify
  end

  test "warning issued and value not stored when validation fails" do
    assistant_text = "##test## es &&-1&&"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{ content: "bad", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

    risk_fields = { test: { id: :test, label: "Test", validation: { min: 0 } } }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :validate_answer, "El valor mínimo es 0" do
        AssistantRunner.stub :new, runner_mock do
          assert_no_difference -> { Message.where(key: "test").count } do
            post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "bad" } }
          end
          assert_redirected_to risk_assistant_path(@risk_assistant)
        end
      end
    end

    runner_mock.verify
    warning = Message.order(:created_at).last
    assert_equal "assistant", warning.sender
    assert_match "El valor mínimo es 0", warning.content
  end

  test "updates field_asked from json response and persists confirmation" do
    assistant_text = {
      campo_actual: "test",
      estado_del_campo: "confirmado",
      valor: "123",
      mensaje_para_usuario: "ok",
      siguiente_campo: nil
    }.to_json

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{ content: "123", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

    risk_fields = { test: { id: :test, label: "Test", assistant_instructions: "" } }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :label_for, ->(_){ "Test" } do
        AssistantRunner.stub :new, runner_mock do
          assert_difference -> { Message.where(sender: "assistant_confirmation", field_asked: "test").count }, 1 do
            post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "123" } }
          end
          user_msg = Message.where(sender: "user").order(:created_at).last
          assert_equal "test", user_msg.field_asked
          assistant_msg = Message.where(sender: "assistant").order(:created_at).last
          assert_equal "test", assistant_msg.field_asked
        end
      end
    end

    runner_mock.verify
  end  

  test "final message uses message field_asked and includes normative explanation" do
    assistant_text = "Gracias por la información"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{ content: "resp", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

    risk_fields = { test: { id: :test, label: "Test", assistant_instructions: "" } }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :normative_tips_for, "Tip" do
        NormativeExplanationGenerator.stub :generate, ->(fid) { assert_equal "test", fid; "Norm" } do
          AssistantRunner.stub :new, runner_mock do
            assert_difference -> { Message.where(sender: "assistant").count }, 1 do
              post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "resp", field_asked: "test" } }
            end
          end
        end
      end
    end

    runner_mock.verify
    final = Message.where(sender: "assistant").order(:created_at).last
    assert_equal "test", final.field_asked
    assert_includes final.content, "Explicación normativa: Norm"
  end

  test "final message falls back to last assistant field when field_asked missing" do
    @risk_assistant.messages.create!(sender: "assistant", role: "assistant", content: "Pregunta previa", field_asked: "test", thread_id: "tid")

    assistant_text = "Entendido"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{ content: "respuesta", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

    risk_fields = { test: { id: :test, label: "Test", assistant_instructions: "" } }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :normative_tips_for, "Tip" do
        NormativeExplanationGenerator.stub :generate, ->(fid) { assert_equal "test", fid; "Norm" } do
          AssistantRunner.stub :new, runner_mock do
            assert_difference -> { Message.where(sender: "assistant").count }, 1 do
              post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "respuesta" } }
            end
          end
        end
      end
    end

    runner_mock.verify
    final = Message.where(sender: "assistant").order(:created_at).last
    assert_equal "test", final.field_asked
    assert_includes final.content, "Explicación normativa: Norm"
  end

  test "uses runner field when response lacks markers" do
    assistant_text = "Pregunta siguiente"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :submit_user_message, nil, [{ content: "resp", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; "test"; end

    risk_fields = { test: { id: :test, label: "Test", assistant_instructions: "" } }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :normative_tips_for, "Tip" do
        NormativeExplanationGenerator.stub :generate, ->(fid, question:) { assert_equal "test", fid; "Norm" } do
          AssistantRunner.stub :new, runner_mock do
            assert_difference -> { Message.where(sender: "assistant").count }, 1 do
              post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "resp" } }
            end
          end
        end
      end
    end

    runner_mock.verify
    final = Message.where(sender: "assistant").order(:created_at).last
    assert_equal "test", final.field_asked
    assert_includes final.content, "Explicación normativa: Norm"
  end

  test "ignores incorrect field_asked param when last question exists" do
    @risk_assistant.messages.create!(
      sender: "assistant", role: "assistant",
      content: "Pregunta real", field_asked: "real", thread_id: "tid"
    )

    assistant_text = "Siguiente"

    runner_mock = Minitest::Mock.new
    runner_mock.expect :thread_id, "tid"
    runner_mock.expect :submit_user_message, nil, [{ content: "resp", file_id: nil }]
    runner_mock.expect :run_and_wait, assistant_text
    def runner_mock.thread_id; "tid"; end
    def runner_mock.last_field_id; nil; end

    risk_fields = {
      real:  { id: :real,  label: "Real",  assistant_instructions: "" },
      wrong: { id: :wrong, label: "Wrong", assistant_instructions: "" }
    }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :normative_tips_for, "" do
        NormativeExplanationGenerator.stub :generate, ->(fid, question:) { assert_equal "real", fid; "Norm" } do
          AssistantRunner.stub :new, runner_mock do
            post risk_assistant_messages_path(@risk_assistant),
                 params: { message: { content: "resp", field_asked: "wrong" } }
          end
        end
      end
    end

    runner_mock.verify
    final = Message.where(sender: "assistant").order(:created_at).last
    assert_equal "real", final.field_asked
    assert_includes final.content, "Explicación normativa: Norm"
  end

  test "skip then answer assigns new field_asked" do
    risk_fields = {
      first:  { id: :first,  label: "First" },
      second: { id: :second, label: "Second" }
    }

    RiskFieldSet.stub :by_id, risk_fields do
      RiskFieldSet.stub :label_for, ->(id) { risk_fields[id.to_sym][:label] } do
        RiskFieldSet.stub :normative_tips_for, "" do
          NormativeExplanationGenerator.stub :generate, ->(fid, question:) { assert_equal "second", fid; "Norm" } do
            @risk_assistant.messages.create!(
              sender: "assistant", role: "assistant",
              content: "Pregunta 1", field_asked: "first", thread_id: "tid"
            )

            skip_runner = Struct.new(:ra) do
              def ask_next!
                ra.messages.create!(
                  sender: "paragraph_generator", role: "assistant",
                  content: "Pregunta 2", field_asked: "second", thread_id: "tid"
                )
              end
            end.new(@risk_assistant)

            AssistantRunner.stub :new, skip_runner do
              post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "skip" } }
            end

            runner_mock = Minitest::Mock.new
            runner_mock.expect :thread_id, "tid"
            runner_mock.expect :submit_user_message, nil, [{ content: "42", file_id: nil }]
            runner_mock.expect :run_and_wait, "Gracias"
            def runner_mock.thread_id; "tid"; end
            def runner_mock.last_field_id; nil; end

            AssistantRunner.stub :new, runner_mock do
              post risk_assistant_messages_path(@risk_assistant), params: { message: { content: "42" } }
            end
            runner_mock.verify

            user_msg = Message.where(sender: "user").order(:created_at).last
            assert_equal "second", user_msg.field_asked

            final = Message.where(sender: "assistant").order(:created_at).last
            assert_equal "second", final.field_asked
          end
        end
      end
    end
  end
end