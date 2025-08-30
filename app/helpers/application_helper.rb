module ApplicationHelper
  # Removes confirmation patterns like "##field## ... &&value&&" from a message
  # so that assistant2 messages are displayed without internal markers.
  def sanitized_content(message)
    return message.content unless message.sender == "assistant"

    message.content.gsub(/(?:\u2705[^#]*?)?##[^#]+##.*?&&.*?&&\s*[.,]?/m, "").strip
  end 
end
