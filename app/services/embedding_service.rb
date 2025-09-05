# frozen_string_literal: true

require "http"
require "json"

class EmbeddingService
  EMBEDDING_URL = "https://api.openai.com/v1/embeddings".freeze
  MODEL = "text-embedding-3-small".freeze
  HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze
  CHAT_URL = "https://api.openai.com/v1/chat/completions".freeze
  CHAT_MODEL = "gpt-4o-mini".freeze

  # Generates an embedding vector for the given text
  def self.embed(text)
    resp = HTTP.headers(HEADERS).post(EMBEDDING_URL, json: { model: MODEL, input: text })
    body = JSON.parse(resp.body.to_s) rescue {}
    body.dig("data", 0, "embedding")
  end

  # Stores a passage and its embedding in the database
  def self.index(content)
    embedding = embed(content)
    Passage.create!(content: content, embedding: embedding)
  end

  # Retrieves the most similar passages for the query text
  def self.search(query, k: 5)
    query_embedding = embed(query)
    vector = "[#{query_embedding.join(',')}]"
    Passage.order(Arel.sql("embedding <-> '#{vector}'")).limit(k)
  end

  # Returns a combined context string for the query
  def self.context_for(query, k: 5)
    search(query, k: k).pluck(:content).join("\n")
  end

  # Answers a question using retrieved passages as context
  def self.answer_with_context(question, model: CHAT_MODEL)
    context = context_for(question)
    messages = [
      { role: "system", content: "Usa el contexto proporcionado para responder" },
      { role: "user", content: "Contexto:\n#{context}\n\nPregunta: #{question}" }
    ]
    resp = HTTP.headers(HEADERS).post(CHAT_URL, json: { model: model, messages: messages })
    body = JSON.parse(resp.body.to_s) rescue {}
    body.dig("choices", 0, "message", "content")
  end
end