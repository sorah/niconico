class Niconico
  def live_client
    Live::Client.new(self.agent)
  end

  class Live
    class Client
      def initialize(agent)
        @agent = agent
        @api = API.new(agent)
      end

      def remove_timeshifts(ids)
        post_body = "delete=timeshift&confirm=#{Util::fetch_token(@agent)}"
        if ids.size == 0
          return
        end
        ids.each do |id|
          id = Util::normalize_id(id, with_lv: false)
          # mechanize doesn't support multiple values for the same key in query.
          post_body += "&vid%5B%5D=#{id}"
        end
        @agent.post(
          'http://live.nicovideo.jp/my.php',
          post_body,
          'Content-Type' => 'application/x-www-form-urlencoded'
        )
      end
    end
  end
end
