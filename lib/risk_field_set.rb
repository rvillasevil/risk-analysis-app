# lib/risk_field_set.rb
require "yaml"

class RiskFieldSet
  CONFIG_PATH = Rails.root.join("config", "risk_assistant", "fields.yml")

  # Devuelve un array de hashes siempre fresco (puedes cachear si lo prefieres)
  def self.all
    @all ||= YAML.load_file(CONFIG_PATH).map(&:symbolize_keys)
  end

  # Útil si quieres llamar a .to_json directamente
  def self.to_json(*args)
    all.to_json(*args)
  end
end
