# app/services/document_type_classifier.rb

class DocumentTypeClassifier
  KEYWORDS = {
    "póliza" => [/p[óo]liza/i],
    "factura" => [/factura/i]
  }.freeze

  def self.call(text)
    content = text.to_s
    return nil if content.blank?

    KEYWORDS.each do |type, patterns|
      return type if patterns.any? { |regex| content.match?(regex) }
    end
    "otros"
  end
end