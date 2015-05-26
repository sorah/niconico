require 'niconico/live/search_result'
class Niconico
  def live_client
    Live::Client.new(self.agent)
  end

  class Live
    class Client
      SEARCH_FILTER_ONAIR = ':onair:' # 放送中
      SEARCH_FILTER_RESERVED = ':reserved:' # 放送予定
      SEARCH_FILTER_CLOSED = ':closed:' # 放送終了

      # joined by 'OR'
      SEARCH_FILTER_OFFICIAL = ':official:' # 公式
      SEARCH_FILTER_CHANNEL = ':channel:' # チャンネル
      SEARCH_FILTER_COMMUNITY = ':community:' # コミュニティ

      SEARCH_FILTER_HIDE_TS_EXPIRED = ':hidetsexpired:' # タイムシフトが視聴できない番組を表示しない
      SEARCH_FILTER_NO_COMMUNITY_GROUP = ':nocommunitygroup:' # 同一コミュニティをまとめて表示しない
      SEARCH_FILTER_HIDE_COM_ONLY = ':hidecomonly:' # コミュニティ限定番組を表示しない

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

      def search(keyword, filters = [])
        filter = filters.join('+')
        page = @agent.get(
          'http://live.nicovideo.jp/search',
          track: '',
          sort: 'recent',
          date: '',
          kind: '',
          keyword: keyword,
          filter: filter
        )
        results_dom = page.at('.result_list')
        items = results_dom.css('.result_item')
        search_results = items.map do |item|
          title_dom = item.at('.search_stream_title a')
          next nil unless title_dom
          id = title_dom.attr(:href).scan(/lv[\d]+/).first
          title = title_dom.text.strip
          description = item.at('.search_stream_description').text.strip
          SearchResult.new(id, title, description)
        end
        search_results.compact
      end
    end
  end
end
