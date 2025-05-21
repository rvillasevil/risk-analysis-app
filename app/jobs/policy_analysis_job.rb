class PolicyAnalysisJob < ApplicationJob
  queue_as :default

  def perform(policy_analysis_id)
    policy = PolicyAnalysis.find(policy_analysis_id)

    # extraemos y analizamos cada documento por separado
    extractor = PolicyAnalyzer.new(policy)
    extractor.run!  # asumimos que PolicyAnalyzer ahora sabe de varios docs

    # aquí podrías, por ejemplo, notificar al usuario vía ActionCable
  end
end