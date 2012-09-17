# RNA is computed from gene
class Rna
  include MongoMapper::Document

  key :transcript, String
  one :transcribe, :class => TranscribeOperation
end
