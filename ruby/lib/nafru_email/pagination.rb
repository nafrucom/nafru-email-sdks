# frozen_string_literal: true

module Nafru
  module Email
    # Bir liste çağrısını tüm sayfalar boyunca gezer (`after` imleci, en yeni önce sırasında ileri). Hata gelirse
    # numaralandırıcı o hatayı fırlatır: sayfalama döngüsünde sessizce kesmek eksik veri okutur.
    #
    #   Nafru::Email.paginate(nafru.contacts.method(:list), limit: 100).each { |contact| ... }
    #
    # @param list [#call] sorgu Hash'i alıp liste zarfı (`{ object:, data:, has_more: }`) döndüren çağrı
    # @return [Enumerator]
    def self.paginate(list, query = {})
      query = query.reject { |key, _| %w[after before].include?(key.to_s) }
      Enumerator.new do |yielder|
        after = nil
        loop do
          page = list.call(after ? query.merge(after: after) : query)
          page[:data].each { |item| yielder << item }
          break if !page[:has_more] || page[:data].empty?

          after = page[:data].last[:id]
        end
      end
    end
  end
end
