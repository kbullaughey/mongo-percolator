class TranscribeOperation < MongoPercolator::OperationDefinition
  # Transcription depends on the gene
  def emit(gene)
    raise ArgumentError, "expecting gene" unless gene.kind_of? Gene
  end

  computes :rna
  depends_on :gene, :dna
end
