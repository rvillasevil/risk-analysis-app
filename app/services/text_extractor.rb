require 'pdf-reader'

class TextExtractor
  def self.call(attachment)
    if attachment.content_type == 'application/pdf'
      extract_pdf_text(attachment)
    else
      attachment.download.force_encoding('UTF-8')
    end
  end

  private_class_method def self.extract_pdf_text(attachment)
    # Cargamos el blob en memoria
    io = StringIO.new(attachment.download)
    reader = PDF::Reader.new(io)

    # Concatenamos el texto de todas las páginas
    reader.pages.map(&:text).join("\n\n")
  rescue => e
    Rails.logger.error "TextExtractor PDF error: #{e.message}"
    ""
  end
end
