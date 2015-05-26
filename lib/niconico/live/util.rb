class Niconico
  class Live
    class Util
      class << self
        def normalize_id(id, with_lv: true)
          id = id.to_s

          if with_lv
            id.start_with?('lv') ? id : "lv#{id}"
          else
            id.start_with?('lv') ? id[2..-1] : id
          end
        end

        def fetch_token(agent)
          page = agent.get('http://live.nicovideo.jp/my')
          page.at('#confirm').attr('value')
        end
      end
    end
  end
end
