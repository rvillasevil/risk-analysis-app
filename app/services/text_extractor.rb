# app/services/text_extractor.rb
require 'pdf-reader'

class TextExtractor
  def self.call(file)
    # 1) Obtener los bytes del fichero: si el objeto responde a `download` (ActiveStorage),
    #    usarlo; si no, asumimos que viene de params[:file] y usamos `read`.
    raw_bytes =
      if file.respond_to?(:download)
        file.download
      else
        file.read
      end

    return "" if raw_bytes.blank?

    # 2) Si es PDF, extraer con PDF::Reader; en caso contrario, asumimos texto plano.
    if file.content_type == 'application/pdf'
      extract_pdf_text(raw_bytes)
    else
      raw_bytes.force_encoding('UTF-8')
    end
  rescue => e
    Rails.logger.error "TextExtractor error: #{e.message}"
    ""
  end

  private_class_method def self.extract_pdf_text(raw_bytes)
    io = StringIO.new(raw_bytes)
    reader = PDF::Reader.new(io)
    reader.pages.map(&:text).join("\n\n")
  rescue => e
    Rails.logger.error "TextExtractor PDF error: #{e.message}"
    ""
  end
end
