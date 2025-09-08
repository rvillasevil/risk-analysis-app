module ApplicationHelper
  # Removes confirmation patterns like "##field## ... &&value&&" from a message
  # so that assistant2 messages are displayed without internal markers.
  def sanitized_content(message)
    return message.content unless message.sender == "assistant"

    message.content.gsub(/(?:\u2705[^#]*?)?##[^#]+##.*?&&.*?&&\s*[.,]?/m, "").strip
  end

  def file_icon_for(file)
    ext = File.extname(file.filename.to_s).downcase
    case ext
    when ".pdf"
      "bi-file-earmark-pdf"
    when ".doc", ".docx"
      "bi-file-earmark-word"
    when ".xls", ".xlsx", ".csv"
      "bi-file-earmark-spreadsheet"
    when ".png", ".jpg", ".jpeg", ".gif"
      "bi-file-earmark-image"
    when ".zip", ".rar"
      "bi-file-earmark-zip"
    else
      "bi-file-earmark"
    end
  end
end
